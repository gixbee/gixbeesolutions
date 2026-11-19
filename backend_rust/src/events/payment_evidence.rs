use super::*;
use axum::{
    body::Body, extract::{DefaultBodyLimit, Multipart},
    http::{header, StatusCode}, response::Response,
};
use sha2::{Digest, Sha256};
use sqlx::Row;
use super::commerce_common::{access, active, milestone, notify_other};

const MAX_RECEIPT: usize = 5 * 1024 * 1024;

pub(super) fn routes() -> Router<AppState> {
    Router::new()
        .route("/quotes/{id}/payments/{milestone_id}/evidence",
            get(list).post(upload).layer(DefaultBodyLimit::max(MAX_RECEIPT + 32768)))
        .route("/quotes/{id}/payments/evidence/{file_id}", get(download))
}

pub(super) async fn list(
    State(state):State<AppState>,user:AuthUser,
    Path((id,milestone_id)):Path<(Uuid,Uuid)>,
)->AppResult<Json<Vec<Value>>> {
    let uid=Uuid::parse_str(&user.user_id)?;
    let mut tx=state.db.begin().await?;
    access(&mut tx,id,uid,false).await?;
    milestone(&mut tx,id,milestone_id,"PAYMENT").await?;
    let rows=sqlx::query_scalar::<_,Value>(
        r#"SELECT jsonb_build_object(
             'id',e.id,'reportId',e."reportId",'fileName',e."fileName",
             'mediaType',e."mediaType",'sha256',e."sha256",
             'uploadedAt',e."uploadedAt")
           FROM event_payment_evidence e
           WHERE e."quoteId"=$1 AND e."milestoneId"=$2 ORDER BY e."uploadedAt",e.id"#,
    ).bind(id).bind(milestone_id).fetch_all(&mut *tx).await?;
    tx.commit().await?;
    Ok(Json(rows))
}

pub(super) async fn upload(
    State(state):State<AppState>,user:AuthUser,
    Path((id,milestone_id)):Path<(Uuid,Uuid)>,
    mut multipart:Multipart,
)->AppResult<Json<Value>>{
    let mut file=None;
    while let Some(field)=multipart.next_field().await
        .map_err(|e|AppError::BadRequest(e.to_string()))? {
        if field.name()!=Some("file") || file.is_some() {
            return Err(AppError::BadRequest("Attach one receipt file".into()));
        }
        let name=field.file_name().unwrap_or("").trim().to_owned();
        if name.is_empty() || name.len()>180 {
            return Err(AppError::BadRequest("Choose a file with a short name".into()));
        }
        let bytes=field.bytes().await
            .map_err(|e|AppError::BadRequest(e.to_string()))?;
        if bytes.is_empty() || bytes.len()>MAX_RECEIPT {
            return Err(AppError::BadRequest("Receipt file must be 1 byte to 5 MB".into()));
        }
        let mime=super::deliveries::media_type(&name,&bytes)?;
        if mime=="application/zip" {
            return Err(AppError::BadRequest("Receipts must be images or PDF".into()));
        }
        file=Some((name,mime,bytes.to_vec()));
    }
    let (name,mime,bytes)=file.ok_or_else(||AppError::BadRequest("Select a receipt".into()))?;
    let uid=Uuid::parse_str(&user.user_id)?;
    let mut tx=state.db.begin().await?;
    let context=access(&mut tx,id,uid,true).await?;
    active(&context)?;
    if !context.customer {
        return Err(AppError::Forbidden("Only the customer can attach payment receipts".into()));
    }
    milestone(&mut tx,id,milestone_id,"PAYMENT").await?;
    let report=sqlx::query(
        r#"SELECT id,status FROM event_payment_reports
           WHERE "milestoneId"=$1 AND "quoteId"=$2
           ORDER BY version DESC LIMIT 1"#,
    ).bind(milestone_id).bind(id).fetch_optional(&mut *tx).await?
    .ok_or_else(||AppError::NotFound("Report the payment before adding evidence".into()))?;
    let status:String=report.get("status");
    if !matches!(status.as_str(),"REPORTED"|"CONTESTED") {
        return Err(AppError::Conflict("This payment report cannot accept more evidence".into()));
    }
    let report_id:Uuid=report.get("id");
    let count:i64=sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM event_payment_evidence WHERE "reportId"=$1"#,
    ).bind(report_id).fetch_one(&mut *tx).await?;
    if count>=5 {
        return Err(AppError::Conflict("A report can include at most five receipts".into()));
    }
    let file_id=Uuid::new_v4();
    let hash=format!("{:x}",Sha256::digest(&bytes));
    sqlx::query(
        r#"INSERT INTO event_payment_evidence
           (id,"quoteId","milestoneId","reportId","fileName","mediaType","fileBytes","sha256","uploadedBy")
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)"#,
    ).bind(file_id).bind(id).bind(milestone_id).bind(report_id)
    .bind(&name).bind(mime).bind(&bytes).bind(&hash).bind(uid)
    .execute(&mut *tx).await?;
    notify_other(&mut tx,&context,"Payment receipt attached",
        "A customer supplied additional payment evidence for review.").await?;
    tx.commit().await?;
    Ok(Json(json!({"id":file_id,"reportId":report_id,"fileName":name,"sha256":hash})))
}

pub(super) async fn download(
    State(state):State<AppState>,user:AuthUser,
    Path((id,file_id)):Path<(Uuid,Uuid)>,
)->AppResult<Response>{
    let uid=Uuid::parse_str(&user.user_id)?;
    let mut tx=state.db.begin().await?;
    access(&mut tx,id,uid,false).await?;
    let row=sqlx::query(
        r#"SELECT "fileBytes","mediaType" FROM event_payment_evidence
           WHERE id=$1 AND "quoteId"=$2"#,
    ).bind(file_id).bind(id).fetch_optional(&mut *tx).await?
    .ok_or_else(||AppError::NotFound("Payment receipt not found".into()))?;
    let bytes:Vec<u8>=row.get("fileBytes");
    let mime:String=row.get("mediaType");
    let extension=match mime.as_str(){
        "image/jpeg"=>"jpg","image/png"=>"png","image/webp"=>"webp",_=>"pdf",
    };
    tx.commit().await?;
    Response::builder().status(StatusCode::OK)
        .header(header::CONTENT_TYPE,"application/octet-stream")
        .header(header::CONTENT_DISPOSITION,
            format!("attachment; filename=\"payment-receipt.{extension}\""))
        .header(header::CACHE_CONTROL,"private, no-store")
        .header("X-Content-Type-Options","nosniff")
        .body(Body::from(bytes))
        .map_err(|_|AppError::Internal("Unable to return private receipt".into()))
}
