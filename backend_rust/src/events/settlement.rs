use super::*;
use sqlx::Row;
use super::commerce_common::{access, active, milestone, notify_other, validate_text, complete_milestone};

pub(super) fn routes() -> Router<AppState> {
    Router::new()
        .route("/quotes/{id}/payments/{milestone_id}", get(reports).post(report))
        .route("/quotes/{id}/payments/{milestone_id}/review", post(review_report))
        .route("/quotes/{id}/disputes", get(disputes).post(open_dispute))
        .route("/quotes/{id}/disputes/{dispute_id}/message", post(message))
        .route("/quotes/{id}/disputes/{dispute_id}/resolve", post(resolve))
}

fn payment_method(method: &str) -> bool {
    matches!(method, "UPI"|"BANK"|"CASH"|"OTHER")
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(super) struct ReportInput {
    method: String,
    reference: String,
    #[serde(default)]
    note: String,
}

pub(super) async fn reports(
    State(state): State<AppState>, user: AuthUser,
    Path((id, milestone_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    access(&mut tx,id,uid,false).await?;
    milestone(&mut tx,id,milestone_id,"PAYMENT").await?;
    let items = sqlx::query_scalar::<_,Value>(
        r#"SELECT to_jsonb(r) FROM event_payment_reports r
           WHERE r."quoteId"=$1 AND r."milestoneId"=$2 ORDER BY version DESC"#,
    ).bind(id).bind(milestone_id).fetch_all(&mut *tx).await?;
    tx.commit().await?;
    Ok(Json(items))
}

pub(super) async fn report(
    State(state): State<AppState>,user: AuthUser,
    Path((id,milestone_id)): Path<(Uuid,Uuid)>,
    Json(body): Json<ReportInput>,
) -> AppResult<Json<Value>> {
    if !payment_method(&body.method) {
        return Err(AppError::BadRequest("Choose UPI, bank, cash or other".into()));
    }
    let reference = validate_text(&body.reference,4,120)?;
    let note = validate_text(&body.note,0,1500)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    let context = access(&mut tx,id,uid,true).await?;
    active(&context)?;
    if !context.customer {
        return Err(AppError::Forbidden("Only the customer can report payment sent".into()));
    }
    let m = milestone(&mut tx,id,milestone_id,"PAYMENT").await?;
    if m.get::<Option<DateTime<Utc>>,_>("completedAt").is_some() {
        return Err(AppError::Conflict("This payment milestone is already complete".into()));
    }
    let active_dispute: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM event_quote_disputes
           WHERE "milestoneId"=$1 AND status='OPEN')"#,
    ).bind(milestone_id).fetch_one(&mut *tx).await?;
    if active_dispute {
        return Err(AppError::Conflict("Resolve the open dispute before reporting another payment".into()));
    }
    let previous = sqlx::query(
        r#"SELECT version,status FROM event_payment_reports
           WHERE "milestoneId"=$1 ORDER BY version DESC LIMIT 1"#,
    ).bind(milestone_id).fetch_optional(&mut *tx).await?;
    if previous.as_ref().is_some_and(|row| row.get::<String,_>("status") != "REJECTED") {
        return Err(AppError::Conflict("A payment report already awaits reconciliation".into()));
    }
    let version = previous.as_ref().map_or(1,|r|r.get::<i32,_>("version")+1);
    if version > 30 {
        return Err(AppError::Conflict("Maximum payment report attempts reached".into()));
    }
    let amount: Decimal = m.try_get::<Option<Decimal>,_>("amount")
        .ok().flatten().ok_or_else(|| AppError::BadRequest("Payment amount missing".into()))?;
    let report_id=Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO event_payment_reports
           (id,"quoteId","milestoneId",version,amount,method,reference,note,"reportedBy")
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)"#,
    ).bind(report_id).bind(id).bind(milestone_id).bind(version)
    .bind(amount).bind(&body.method).bind(&reference).bind(&note).bind(uid)
    .execute(&mut *tx).await?;
    notify_other(&mut tx,&context,"Payment claimed",
        "The customer reported an off-platform payment. Verify receipt independently.").await?;
    tx.commit().await?;
    Ok(Json(json!({"id":report_id,"version":version,"amount":amount,
        "status":"REPORTED","reference":reference})))
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(super) struct ReportReview {
    decision:String,
    #[serde(default)]
    note:String,
}

pub(super) async fn review_report(
    State(state): State<AppState>,user:AuthUser,
    Path((id,milestone_id)):Path<(Uuid,Uuid)>,
    Json(body):Json<ReportReview>,
)->AppResult<Json<Value>>{
    if !matches!(body.decision.as_str(),"CONFIRM"|"CONTEST") {
        return Err(AppError::BadRequest("Confirm receipt or contest the report".into()));
    }
    let note=validate_text(&body.note,if body.decision=="CONTEST"{10}else{0},1500)?;
    let uid=Uuid::parse_str(&user.user_id)?;
    let mut tx=state.db.begin().await?;
    let context=access(&mut tx,id,uid,true).await?;
    active(&context)?;
    if context.customer {
        return Err(AppError::Forbidden("Only the vendor can reconcile payment received".into()));
    }
    milestone(&mut tx,id,milestone_id,"PAYMENT").await?;
    let latest=sqlx::query(
        r#"SELECT id,status FROM event_payment_reports
           WHERE "quoteId"=$1 AND "milestoneId"=$2
           ORDER BY version DESC LIMIT 1 FOR UPDATE"#,
    ).bind(id).bind(milestone_id).fetch_optional(&mut *tx).await?
    .ok_or_else(||AppError::NotFound("No reported payment".into()))?;
    if latest.get::<String,_>("status")!="REPORTED" {
        return Err(AppError::Conflict("This report was already reviewed".into()));
    }
    let report_id:Uuid=latest.get("id");
    let next=if body.decision=="CONFIRM"{"CONFIRMED"}else{"CONTESTED"};
    sqlx::query(
        r#"UPDATE event_payment_reports SET status=$2,"reviewNote"=$3,
           "reviewedBy"=$4,"reviewedAt"=NOW() WHERE id=$1"#,
    ).bind(report_id).bind(next).bind(&note).bind(uid)
    .execute(&mut *tx).await?;
    if next=="CONFIRMED" {
        complete_milestone(&mut tx,milestone_id,context.customer_id,context.vendor_id).await?;
    } else {
        create_dispute(&mut tx,id,milestone_id,Some(report_id),uid,&note).await?;
    }
    notify_other(&mut tx,&context,"Payment reconciliation updated",
        if next=="CONFIRMED" {
            "The vendor acknowledged the reported payment."
        } else {
            "The vendor contested the payment report. Review the open dispute."
        }).await?;
    tx.commit().await?;
    Ok(Json(json!({"status":next,"reportId":report_id})))
}

async fn create_dispute(
    tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,
    quote_id:Uuid,milestone_id:Uuid,report_id:Option<Uuid>,
    uid:Uuid,reason:&str,
)->AppResult<Uuid>{
    let existing:bool=sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM event_quote_disputes
           WHERE "milestoneId"=$1 AND status='OPEN')"#,
    ).bind(milestone_id).fetch_one(&mut **tx).await?;
    if existing {
        return Err(AppError::Conflict("A dispute is already open for this milestone".into()));
    }
    let dispute_id=Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO event_quote_disputes
           (id,"quoteId","milestoneId","reportId","openedBy",reason)
           VALUES ($1,$2,$3,$4,$5,$6)"#,
    ).bind(dispute_id).bind(quote_id).bind(milestone_id)
    .bind(report_id).bind(uid).bind(reason).execute(&mut **tx).await?;
    append_event(tx,dispute_id,uid,"OPENED",reason).await?;
    Ok(dispute_id)
}

async fn append_event(
    tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,
    dispute_id:Uuid,uid:Uuid,action:&str,note:&str,
)->AppResult<()> {
    sqlx::query(
        r#"INSERT INTO event_quote_dispute_events
           (id,"disputeId","actorId",action,message) VALUES ($1,$2,$3,$4,$5)"#,
    ).bind(Uuid::new_v4()).bind(dispute_id).bind(uid).bind(action).bind(note)
    .execute(&mut **tx).await?;
    Ok(())
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(super) struct DisputeInput{
    milestone_id:Uuid,
    reason:String,
}

pub(super) async fn open_dispute(
    State(state):State<AppState>,user:AuthUser,
    Path(id):Path<Uuid>,Json(body):Json<DisputeInput>,
)->AppResult<Json<Value>>{
    let reason=validate_text(&body.reason,10,2000)?;
    let uid=Uuid::parse_str(&user.user_id)?;
    let mut tx=state.db.begin().await?;
    let context=access(&mut tx,id,uid,true).await?;
    active(&context)?;
    let m=milestone(&mut tx,id,body.milestone_id,"PAYMENT").await?;
    if m.get::<Option<DateTime<Utc>>,_>("completedAt").is_some() {
        return Err(AppError::Conflict("Use support for a completed payment; this reconciliation is closed".into()));
    }
    let latest:Option<Uuid>=sqlx::query_scalar(
        r#"SELECT id FROM event_payment_reports WHERE "milestoneId"=$1
           ORDER BY version DESC LIMIT 1"#,
    ).bind(body.milestone_id).fetch_optional(&mut *tx).await?;
    let dispute_id=create_dispute(&mut tx,id,body.milestone_id,latest,uid,&reason).await?;
    if let Some(report_id)=latest {
        sqlx::query(
            r#"UPDATE event_payment_reports SET status='CONTESTED'
               WHERE id=$1 AND status='REPORTED'"#,
        ).bind(report_id).execute(&mut *tx).await?;
    }
    notify_other(&mut tx,&context,"Payment dispute opened",
        "A payment dispute requires both participants to review the evidence.").await?;
    tx.commit().await?;
    Ok(Json(json!({"id":dispute_id,"status":"OPEN"})))
}

pub(super) async fn disputes(
    State(state):State<AppState>,user:AuthUser,
    Path(id):Path<Uuid>,
)->AppResult<Json<Vec<Value>>>{
    let uid=Uuid::parse_str(&user.user_id)?;
    let mut tx=state.db.begin().await?;
    access(&mut tx,id,uid,false).await?;
    let rows=sqlx::query_scalar::<_,Value>(
        r#"SELECT to_jsonb(d) || jsonb_build_object('events',
             COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e."createdAt",e.id)
               FROM event_quote_dispute_events e WHERE e."disputeId"=d.id),'[]'::jsonb))
           FROM event_quote_disputes d WHERE d."quoteId"=$1
           ORDER BY d."openedAt" DESC"#,
    ).bind(id).fetch_all(&mut *tx).await?;
    tx.commit().await?;
    Ok(Json(rows))
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(super) struct MessageInput {message:String}

pub(super) async fn message(
    State(state):State<AppState>,user:AuthUser,
    Path((id,dispute_id)):Path<(Uuid,Uuid)>,
    Json(body):Json<MessageInput>,
)->AppResult<Json<Value>>{
    let note=validate_text(&body.message,1,2000)?;
    let uid=Uuid::parse_str(&user.user_id)?;
    let mut tx=state.db.begin().await?;
    let context=access(&mut tx,id,uid,true).await?;
    let status:Option<String>=sqlx::query_scalar(
        r#"SELECT status FROM event_quote_disputes
           WHERE id=$1 AND "quoteId"=$2 FOR UPDATE"#,
    ).bind(dispute_id).bind(id).fetch_optional(&mut *tx).await?;
    if status.as_deref()!=Some("OPEN") {
        return Err(AppError::Conflict("This dispute is not open".into()));
    }
    append_event(&mut tx,dispute_id,uid,"MESSAGE",&note).await?;
    notify_other(&mut tx,&context,"Payment dispute message",
        "The other participant added information to your payment dispute.").await?;
    tx.commit().await?;
    Ok(Json(json!({"status":"OPEN"})))
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(super) struct ResolutionInput {
    resolution:String,
    #[serde(default)]
    note:String,
}

fn valid_resolution(value:&str)->bool{
    matches!(value,"SETTLED"|"UNPAID")
}

pub(super) async fn resolve(
    State(state):State<AppState>,user:AuthUser,
    Path((id,dispute_id)):Path<(Uuid,Uuid)>,
    Json(body):Json<ResolutionInput>,
)->AppResult<Json<Value>>{
    if !valid_resolution(&body.resolution) {
        return Err(AppError::BadRequest("Choose SETTLED or UNPAID".into()));
    }
    let note=validate_text(&body.note,0,2000)?;
    let uid=Uuid::parse_str(&user.user_id)?;
    let mut tx=state.db.begin().await?;
    let context=access(&mut tx,id,uid,true).await?;
    active(&context)?;
    let row=sqlx::query(
        r#"SELECT "milestoneId","reportId",status,"customerVote","vendorVote"
           FROM event_quote_disputes WHERE id=$1 AND "quoteId"=$2 FOR UPDATE"#,
    ).bind(dispute_id).bind(id).fetch_optional(&mut *tx).await?
    .ok_or_else(||AppError::NotFound("Dispute not found".into()))?;
    if row.get::<String,_>("status")!="OPEN" {
        return Err(AppError::Conflict("This dispute is already resolved".into()));
    }
    let own=if context.customer {"customerVote"} else {"vendorVote"};
    sqlx::query(&format!(
        r#"UPDATE event_quote_disputes SET "{own}"=$2 WHERE id=$1"#,
    )).bind(dispute_id).bind(&body.resolution)
    .execute(&mut *tx).await?;
    append_event(&mut tx,dispute_id,uid,"VOTED",
        &format!("{}: {}",body.resolution,note)).await?;
    let other:Option<String>=row.get(if context.customer {"vendorVote"}else{"customerVote"});
    let mut resolved=false;
    if other.as_deref()==Some(body.resolution.as_str()){
        let milestone_id:Uuid=row.get("milestoneId");
        let report_id:Option<Uuid>=row.get("reportId");
        milestone(&mut tx,id,milestone_id,"PAYMENT").await?;
        sqlx::query(
            r#"UPDATE event_quote_disputes SET status='RESOLVED',resolution=$2,
               "resolvedAt"=NOW() WHERE id=$1"#,
        ).bind(dispute_id).bind(&body.resolution)
        .execute(&mut *tx).await?;
        if let Some(report_id)=report_id {
            sqlx::query(
                r#"UPDATE event_payment_reports SET status=$2 WHERE id=$1"#,
            ).bind(report_id).bind(if body.resolution=="SETTLED"{"CONFIRMED"}else{"REJECTED"})
            .execute(&mut *tx).await?;
        }
        if body.resolution=="SETTLED" {
            complete_milestone(&mut tx,milestone_id,context.customer_id,context.vendor_id).await?;
        }
        append_event(&mut tx,dispute_id,uid,"RESOLVED",
            &format!("Agreed resolution: {}",body.resolution)).await?;
        resolved=true;
    }
    notify_other(&mut tx,&context,"Payment dispute updated",
        if resolved {"Both participants agreed on a dispute resolution."}
        else {"A participant recorded a proposed dispute resolution."}).await?;
    tx.commit().await?;
    Ok(Json(json!({"status":if resolved{"RESOLVED"}else{"OPEN"},
        "yourVote":body.resolution,"resolved":resolved})))
}

#[cfg(test)]
mod tests{
    use super::*;
    #[test]
    fn accepted_payment_methods_are_explicit(){
        assert!(payment_method("UPI"));
        assert!(payment_method("BANK"));
        assert!(!payment_method("CARD"));
    }
    #[test]
    fn dispute_resolutions_are_bilateral_choices(){
        assert!(valid_resolution("SETTLED"));
        assert!(valid_resolution("UNPAID"));
        assert!(!valid_resolution("REFUND_ISSUED"));
    }
}
