use super::*;
use axum::{
    body::Body, extract::{DefaultBodyLimit, Multipart},
    http::{header, StatusCode}, response::Response,
};
use sha2::{Digest, Sha256};
use sqlx::Row;
use super::commerce_common::{access, active, milestone, notify_other, validate_text, complete_milestone};

const MAX_FILE: usize = 12 * 1024 * 1024;

pub(super) fn routes() -> Router<AppState> {
    Router::new()
        .route("/quotes/{id}/deliveries/{milestone_id}",
            get(list).post(upload).layer(DefaultBodyLimit::max(MAX_FILE + 65536)))
        .route("/quotes/{id}/deliveries/{milestone_id}/review", post(review))
        .route("/quotes/{id}/deliveries/file/{file_id}", get(download))
}

fn media_type(filename: &str, data: &[u8]) -> AppResult<&'static str> {
    let ext = filename.rsplit_once('.').map(|(_, v)| v.to_ascii_lowercase());
    match ext.as_deref() {
        Some("jpg" | "jpeg") if data.starts_with(&[0xff,0xd8,0xff]) =>
            Ok("image/jpeg"),
        Some("png") if data.starts_with(b"\x89PNG\r\n\x1a\n") =>
            Ok("image/png"),
        Some("webp") if data.starts_with(b"RIFF") && data.get(8..12) == Some(b"WEBP") =>
            Ok("image/webp"),
        Some("pdf") if data.starts_with(b"%PDF-") => Ok("application/pdf"),
        Some("zip") if data.starts_with(b"PK\x03\x04") => Ok("application/zip"),
        _ => Err(AppError::BadRequest(
            "Upload a genuine JPG, PNG, WebP, PDF or ZIP file".into())),
    }
}

pub(super) async fn list(
    State(state): State<AppState>, user: AuthUser,
    Path((id, milestone_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    let context = access(&mut tx, id, uid, false).await?;
    if context.service != "PHOTOGRAPHY" {
        return Err(AppError::NotFound("Photography delivery not found".into()));
    }
    milestone(&mut tx, id, milestone_id, "DELIVERY").await?;
    let records = sqlx::query_scalar::<_,Value>(
        r#"SELECT to_jsonb(d)-'fileBytes' FROM event_delivery_revisions d
           WHERE d."quoteId"=$1 AND d."milestoneId"=$2 ORDER BY version DESC"#,
    ).bind(id).bind(milestone_id)
    .fetch_all(&mut *tx).await?;
    tx.commit().await?;
    Ok(Json(records))
}

pub(super) async fn upload(
    State(state): State<AppState>, user: AuthUser,
    Path((id, milestone_id)): Path<(Uuid, Uuid)>,
    mut multipart: Multipart,
) -> AppResult<Json<Value>> {
    let mut file = None;
    let mut note = String::new();
    while let Some(field) = multipart.next_field().await
        .map_err(|e| AppError::BadRequest(e.to_string()))? {
        match field.name() {
            Some("file") if file.is_none() => {
                let name = field.file_name().unwrap_or("").trim().to_owned();
                if name.is_empty() || name.len() > 180 {
                    return Err(AppError::BadRequest("Choose a file with a short name".into()));
                }
                let bytes = field.bytes().await
                    .map_err(|e| AppError::BadRequest(e.to_string()))?;
                if bytes.is_empty() || bytes.len() > MAX_FILE {
                    return Err(AppError::BadRequest("File size must be 1 byte to 12 MB".into()));
                }
                let kind = media_type(&name, &bytes)?;
                file = Some((name, kind, bytes.to_vec()));
            },
            Some("note") => {
                note = field.text().await
                    .map_err(|e| AppError::BadRequest(e.to_string()))?;
            },
            _ => return Err(AppError::BadRequest("Only one file and a note are supported".into())),
        }
    }
    let (name, kind, bytes) = file.ok_or_else(|| AppError::BadRequest("Select a file".into()))?;
    let note = validate_text(&note, 0, 1200)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    let context = access(&mut tx, id, uid, true).await?;
    active(&context)?;
    if context.customer || context.service != "PHOTOGRAPHY" {
        return Err(AppError::Forbidden("Only the photographer can submit delivery files".into()));
    }
    let m = milestone(&mut tx, id, milestone_id, "DELIVERY").await?;
    if m.get::<Option<DateTime<Utc>>,_>("completedAt").is_some() {
        return Err(AppError::Conflict("This deliverable is already approved".into()));
    }
    let previous = sqlx::query(
        r#"SELECT version,status FROM event_delivery_revisions
           WHERE "milestoneId"=$1 ORDER BY version DESC LIMIT 1"#,
    ).bind(milestone_id).fetch_optional(&mut *tx).await?;
    let version = previous.as_ref().map_or(1, |r| r.get::<i32,_>("version") + 1);
    if version > 30 || previous.as_ref().is_some_and(|r| {
        r.get::<String,_>("status") != "REVISION_REQUESTED"
    }) {
        return Err(AppError::Conflict("Wait for customer review before submitting another version".into()));
    }
    let digest = format!("{:x}", Sha256::digest(&bytes));
    let revision_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO event_delivery_revisions
           (id,"quoteId","milestoneId",version,"fileName","mediaType","fileBytes","sha256",note,"uploadedBy")
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)"#,
    ).bind(revision_id).bind(id).bind(milestone_id).bind(version)
    .bind(&name).bind(kind).bind(&bytes).bind(&digest).bind(&note).bind(uid)
    .execute(&mut *tx).await?;
    notify_other(&mut tx, &context, "Photography delivery uploaded",
        "A new deliverable version is ready for your review.").await?;
    tx.commit().await?;
    Ok(Json(json!({"id":revision_id,"version":version,"status":"SUBMITTED",
        "fileName":name,"mediaType":kind,"sha256":digest})))
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(super) struct Review {
    decision: String,
    #[serde(default)]
    feedback: String,
}

pub(super) async fn review(
    State(state): State<AppState>, user: AuthUser,
    Path((id, milestone_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<Review>,
) -> AppResult<Json<Value>> {
    if !matches!(body.decision.as_str(),"APPROVE"|"REQUEST_REVISION") {
        return Err(AppError::BadRequest("Choose approval or request a revision".into()));
    }
    let feedback = validate_text(&body.feedback,
        if body.decision == "REQUEST_REVISION" {10} else {0}, 1500)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    let context = access(&mut tx, id, uid, true).await?;
    active(&context)?;
    if !context.customer || context.service != "PHOTOGRAPHY" {
        return Err(AppError::Forbidden("Only the customer can review a photography delivery".into()));
    }
    milestone(&mut tx, id, milestone_id, "DELIVERY").await?;
    let latest = sqlx::query(
        r#"SELECT id,version,status FROM event_delivery_revisions
           WHERE "quoteId"=$1 AND "milestoneId"=$2 ORDER BY version DESC LIMIT 1 FOR UPDATE"#,
    ).bind(id).bind(milestone_id).fetch_optional(&mut *tx).await?
    .ok_or_else(|| AppError::NotFound("No file is ready for review".into()))?;
    if latest.get::<String,_>("status") != "SUBMITTED" {
        return Err(AppError::Conflict("This delivery version was already reviewed".into()));
    }
    let next_status = if body.decision == "APPROVE" {"APPROVED"} else {"REVISION_REQUESTED"};
    sqlx::query(
        r#"UPDATE event_delivery_revisions SET status=$2,"feedback"=$3,
           "reviewedBy"=$4,"reviewedAt"=NOW() WHERE id=$1"#,
    ).bind(latest.get::<Uuid,_>("id")).bind(next_status).bind(&feedback).bind(uid)
    .execute(&mut *tx).await?;
    if body.decision == "APPROVE" {
        complete_milestone(&mut tx, milestone_id, context.customer_id, context.vendor_id).await?;
    }
    notify_other(&mut tx, &context, "Photography delivery reviewed",
        if body.decision == "APPROVE" {"The customer approved the deliverable."}
        else {"The customer requested a delivery revision."}).await?;
    tx.commit().await?;
    Ok(Json(json!({"status":next_status,"version":latest.get::<i32,_>("version")})))
}

pub(super) async fn download(
    State(state): State<AppState>, user: AuthUser,
    Path((id, file_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Response> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    let context = access(&mut tx, id, uid, false).await?;
    if context.service != "PHOTOGRAPHY" {
        return Err(AppError::NotFound("File not found".into()));
    }
    let row = sqlx::query(
        r#"SELECT "fileBytes","mediaType" FROM event_delivery_revisions
           WHERE id=$1 AND "quoteId"=$2"#,
    ).bind(file_id).bind(id).fetch_optional(&mut *tx).await?
    .ok_or_else(|| AppError::NotFound("File not found".into()))?;
    let bytes: Vec<u8> = row.get("fileBytes");
    let media: String = row.get("mediaType");
    let extension = match media.as_str() {
        "image/jpeg" => "jpg","image/png"=>"png","image/webp"=>"webp",
        "application/pdf"=>"pdf", _=>"zip"
    };
    tx.commit().await?;
    let response = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/octet-stream")
        .header(header::CONTENT_DISPOSITION,
            format!("attachment; filename=\"photography-delivery.{extension}\""))
        .header(header::CACHE_CONTROL, "private, no-store")
        .header("X-Content-Type-Options", "nosniff")
        .body(Body::from(bytes))
        .map_err(|_| AppError::Internal("Unable to build file response".into()))?;
    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_file_extension_spoofing() {
        assert!(media_type("photo.jpg", b"%PDF-1.7").is_err());
        assert!(media_type("invoice.pdf.exe", b"%PDF-1.7").is_err());
        assert!(media_type("photo.jpg", &[0xff,0xd8,0xff,0xe0]).is_ok());
        assert!(media_type("evidence.pdf", b"%PDF-1.7\n").is_ok());
    }
}
