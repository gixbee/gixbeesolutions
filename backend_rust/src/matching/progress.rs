use super::*;
use chrono::{DateTime, Utc};
use sqlx::Row;

pub(super) async fn detail(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let row = sqlx::query(
        r#"SELECT hi.progress, hi.revision, hi.decision::text AS decision, hi.response::text AS response,
        hi."requestId", hi."candidateId", hr."jobType", hr.description, hr.location, hr."employerId",
        u.name AS "candidateName", b.name AS "businessName", b.phone AS "businessPhoneRaw",
        cand."phoneNumber" AS "candidatePhoneRaw"
        FROM hiring_interests hi JOIN hiring_requests hr ON hr.id=hi."requestId"
        JOIN users u ON u.id=hi."candidateId"
        JOIN users cand ON cand.id=hi."candidateId"
        LEFT JOIN businesses b ON b.id=hr."businessId"
        WHERE hi.id=$1 AND (hi."candidateId"=$2 OR hr."employerId"=$2)"#,
    )
    .bind(Uuid::parse_str(&id)?)
    .bind(Uuid::parse_str(&user.user_id)?)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Application not found".into()))?;
    let progress: Value = row.try_get("progress").ok().unwrap_or(json!({}));
    let decision = row.get::<String, _>("decision");
    let response = row.get::<String, _>("response");
    let unlocked = super::flow::contact_unlocked(&progress, &decision);
    Ok(Json(json!({
        "interestId": id,
        "requestId": row.get::<Uuid, _>("requestId"),
        "candidateId": row.get::<Uuid, _>("candidateId"),
        "employerId": row.get::<Uuid, _>("employerId"),
        "progress": progress,
        "revision": row.get::<i32, _>("revision"),
        "decision": decision,
        "response": response,
        "pipelineStage": super::flow::pipeline_label(&response, &decision, &progress),
        "canChat": super::flow::can_chat(&response, &decision),
        "contactShared": progress.get("contactShared").and_then(Value::as_bool).unwrap_or(false),
        "contactRequested": progress.get("contactRequested").and_then(Value::as_bool).unwrap_or(false),
        "phoneLocked": !unlocked,
        "emailLocked": !unlocked,
        "jobType": row.get::<String, _>("jobType"),
        "description": row.try_get::<Option<String>, _>("description").ok().flatten(),
        "location": row.get::<Option<String>, _>("location"),
        "candidateName": row.get::<Option<String>, _>("candidateName"),
        "businessName": row.get::<Option<String>, _>("businessName"),
        "businessPhone": if unlocked { json!(row.get::<Option<String>, _>("businessPhoneRaw")) } else { Value::Null },
        "candidatePhone": if unlocked { json!(row.get::<Option<String>, _>("candidatePhoneRaw")) } else { Value::Null },
        "isEmployer": row.get::<Uuid, _>("employerId").to_string() == user.user_id,
    })))
}

pub(super) async fn action(
    State(state): State<AppState>,
    user: AuthUser,
    Path((id, action)): Path<(String, String)>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let iid = Uuid::parse_str(&id)?;
    let mut tx = state.db.begin().await?;
    let request = sqlx::query(
        r#"SELECT hr.id, hr."employerId", hr.vacancies FROM hiring_requests hr
           JOIN hiring_interests hi ON hi."requestId"=hr.id WHERE hi.id=$1 FOR UPDATE OF hr"#,
    )
    .bind(iid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Application not found".into()))?;
    let interest = sqlx::query(
        r#"SELECT "candidateId", decision::text AS decision, response::text AS response, progress, revision
           FROM hiring_interests WHERE id=$1 FOR UPDATE"#,
    )
    .bind(iid)
    .fetch_one(&mut *tx)
    .await?;
    let employer = request.get::<Uuid, _>("employerId");
    let candidate = interest.get::<Uuid, _>("candidateId");
    let is_employer = uid == employer;
    if !is_employer && uid != candidate {
        return Err(AppError::NotFound("Application not found".into()));
    }
    let decision = interest.get::<String, _>("decision");
    let response = interest.get::<String, _>("response");
    let revision = interest.get::<i32, _>("revision");
    let early = matches!(
        action.as_str(),
        "view" | "invite" | "accept-invite" | "request-contact" | "share-contact" | "decline-contact"
    );
    if !early {
        if response != "INTERESTED" {
            return Err(AppError::NotFound("Application not found".into()));
        }
        if decision != "SHORTLISTED" {
            return Err(AppError::Conflict(
                "This action requires an active shortlisted application".into(),
            ));
        }
        if body.get("revision").and_then(Value::as_i64) != Some(i64::from(revision)) {
            return Err(AppError::Conflict(
                "The application has changed. Refresh and review the latest details".into(),
            ));
        }
    }
    let mut progress: Value = interest.get("progress");
    let stage = progress
        .get("stage")
        .and_then(Value::as_str)
        .unwrap_or("SHORTLISTED")
        .to_string();
    let mut next_decision = decision.clone();
    let mut next_response = response.clone();
    let request_id: Uuid = request.get("id");
    match action.as_str() {
        "view" => {
            let key = if is_employer {
                "viewedByEmployer"
            } else {
                "viewedByCandidate"
            };
            let mut patch = serde_json::Map::new();
            patch.insert(key.into(), json!(true));
            super::flow::merge_progress(&mut progress, Value::Object(patch));
            if progress
                .get("stage")
                .and_then(Value::as_str)
                .unwrap_or("")
                .is_empty()
                && next_response == "PENDING"
            {
                progress["stage"] = json!("VIEWED");
            }
        }
        "invite" => {
            require_role(is_employer, true)?;
            if next_response == "NOT_INTERESTED" {
                return Err(AppError::Conflict("This candidate passed on the job".into()));
            }
            if next_response == "INTERESTED" {
                return Err(AppError::Conflict("Chat is already open".into()));
            }
            super::flow::merge_progress(&mut progress, json!({"invited": true, "stage": "INVITED"}));
        }
        "accept-invite" => {
            require_role(is_employer, false)?;
            if next_response != "PENDING"
                || progress.get("invited").and_then(Value::as_bool) != Some(true)
            {
                return Err(AppError::Conflict("No open invite to accept".into()));
            }
            next_response = "INTERESTED".into();
            super::flow::merge_progress(
                &mut progress,
                json!({"mutualInterest": true, "stage": "CHATTING"}),
            );
        }
        "request-contact" => {
            require_role(is_employer, true)?;
            if next_response != "INTERESTED" {
                return Err(AppError::Conflict("Chat must be open before requesting contact".into()));
            }
            super::flow::merge_progress(&mut progress, json!({"contactRequested": true}));
        }
        "share-contact" => {
            require_role(is_employer, false)?;
            if next_response != "INTERESTED" && next_decision != "HIRED" {
                return Err(AppError::Conflict(
                    "Share contact after you mark Interested".into(),
                ));
            }
            super::flow::merge_progress(
                &mut progress,
                json!({"contactShared": true, "contactDeclined": false}),
            );
        }
        "decline-contact" => {
            require_role(is_employer, false)?;
            super::flow::merge_progress(
                &mut progress,
                json!({"contactDeclined": true, "contactRequested": false}),
            );
        }
        "interview" => {
            require_role(is_employer, true)?;
            if ["OFFERED", "ACCEPTED", "JOINED", "WITHDRAWN"].contains(&stage.as_str()) {
                return Err(AppError::Conflict(
                    "Resolve the current offer before scheduling an interview".into(),
                ));
            }
            let at = future_time(&body, "interviewAt")?;
            let place = required_text(&body, "interviewPlace", 2000)?;
            let kind = body
                .get("interviewType")
                .and_then(Value::as_str)
                .unwrap_or("IN_PERSON");
            if !matches!(kind, "IN_PERSON" | "PHONE" | "VIDEO") {
                return Err(AppError::BadRequest(
                    "Interview type must be IN_PERSON, PHONE or VIDEO".into(),
                ));
            }
            progress["interviewAt"] = json!(at);
            progress["interviewPlace"] = json!(place);
            progress["interviewType"] = json!(kind);
            progress["stage"] = json!("INTERVIEW_PROPOSED");
        }
        "accept-interview" | "decline-interview" => {
            require_role(is_employer, false)?;
            require_stage(&stage, &["INTERVIEW_PROPOSED"])?;
            if saved_time(&progress, "interviewAt")? <= Utc::now() {
                return Err(AppError::Conflict(
                    "This interview time has passed. Ask the employer to reschedule".into(),
                ));
            }
            progress["stage"] = json!(if action == "accept-interview" {
                "INTERVIEW_ACCEPTED"
            } else {
                "INTERVIEW_DECLINED"
            });
        }
        "complete-interview" => {
            require_role(is_employer, true)?;
            require_stage(&stage, &["INTERVIEW_ACCEPTED"])?;
            if saved_time(&progress, "interviewAt")? > Utc::now() {
                return Err(AppError::Conflict("The interview has not started".into()));
            }
            progress["stage"] = json!("INTERVIEW_COMPLETED");
        }
        "offer" => {
            require_role(is_employer, true)?;
            require_stage(
                &stage,
                &["SHORTLISTED", "INTERVIEW_COMPLETED", "OFFER_DECLINED", "OFFERED"],
            )?;
            let occupied: i64 = sqlx::query_scalar(
                r#"SELECT count(*) FROM hiring_interests WHERE "requestId"=$1 AND id<>$2
                AND (decision='HIRED' OR (decision='SHORTLISTED' AND progress->>'stage' IN ('OFFERED','ACCEPTED','JOINED')))"#,
            )
            .bind(request_id)
            .bind(iid)
            .fetch_one(&mut *tx)
            .await?;
            if occupied >= i64::from(request.get::<i32, _>("vacancies")) {
                return Err(AppError::Conflict(
                    "All vacancies have an outstanding offer or a joined candidate".into(),
                ));
            }
            let salary = body.get("salary").and_then(Value::as_f64).unwrap_or(0.0);
            if !salary.is_finite() || !(0.01..=99_999_999.0).contains(&salary) {
                return Err(AppError::BadRequest("Enter a positive monthly salary".into()));
            }
            let at = future_time(&body, "joiningAt")?;
            let terms = required_text(&body, "offerTerms", 5000)?;
            progress["salary"] = json!(salary);
            progress["joiningAt"] = json!(at);
            progress["offerTerms"] = json!(terms);
            progress["employerJoinedAt"] = Value::Null;
            progress["candidateJoinedAt"] = Value::Null;
            progress["stage"] = json!("OFFERED");
        }
        "accept-offer" | "decline-offer" => {
            require_role(is_employer, false)?;
            require_stage(&stage, &["OFFERED"])?;
            if action == "accept-offer" && saved_time(&progress, "joiningAt")? <= Utc::now() {
                return Err(AppError::Conflict(
                    "The joining time has passed. Ask the employer for an updated offer".into(),
                ));
            }
            progress["stage"] = json!(if action == "accept-offer" {
                "ACCEPTED"
            } else {
                "OFFER_DECLINED"
            });
        }
        "joined" => {
            require_stage(&stage, &["ACCEPTED"])?;
            if saved_time(&progress, "joiningAt")? > Utc::now() {
                return Err(AppError::Conflict(
                    "The agreed joining time has not arrived".into(),
                ));
            }
            progress[if is_employer {
                "employerJoinedAt"
            } else {
                "candidateJoinedAt"
            }] = json!(Utc::now());
            if !progress["employerJoinedAt"].is_null() && !progress["candidateJoinedAt"].is_null()
            {
                progress["stage"] = json!("JOINED");
                next_decision = "HIRED".into();
            }
        }
        "withdraw" => {
            if stage == "JOINED" {
                return Err(AppError::Conflict("Joining is already confirmed".into()));
            }
            progress["withdrawalReason"] = json!(required_text(&body, "reason", 2000)?);
            progress["stage"] = json!("WITHDRAWN");
            next_decision = "REJECTED".into();
        }
        _ => return Err(AppError::BadRequest("Unknown hiring action".into())),
    }
    let mut history = progress["history"].as_array().cloned().unwrap_or_default();
    history.push(json!({
        "action": action,
        "by": if is_employer { "Employer" } else { "Candidate" },
        "at": Utc::now(),
        "stage": progress["stage"],
        "details": body.as_object().map(|m| m.iter().filter(|(k,_)| k.as_str() != "revision")
            .map(|(k,v)| (k.clone(), v.clone())).collect::<serde_json::Map<String,Value>>())
    }));
    if history.len() > 256 {
        return Err(AppError::Conflict(
            "Application update limit reached. Contact support".into(),
        ));
    }
    progress["history"] = json!(history);
    sqlx::query(
        r#"UPDATE hiring_interests SET progress=$1, revision=revision+1,
           decision=$2::hiring_interests_decision_enum,
           response=$3::hiring_interests_response_enum,
           "respondedAt"=CASE WHEN $3='INTERESTED' AND response<>'INTERESTED' THEN NOW() ELSE "respondedAt" END,
           "updatedAt"=NOW() WHERE id=$4"#,
    )
    .bind(&progress)
    .bind(&next_decision)
    .bind(&next_response)
    .bind(iid)
    .execute(&mut *tx)
    .await?;
    if action != "view" {
        crate::outbox::notify(
            &mut tx,
            request_id,
            if is_employer { candidate } else { employer },
            "Hiring application update",
            "Open the application to review the latest invite, chat or offer update.",
            json!({"type":"hiring_progress","interestId":iid,"requestId":request_id}),
        )
        .await?;
    }
    tx.commit().await?;
    if action == "accept-invite" {
        super::engine::maybe_deliver_on_response(&state, request_id).await?;
    }
    detail(State(state), user, Path(id)).await
}

fn require_role(is_employer: bool, expected: bool) -> AppResult<()> {
    if is_employer != expected {
        return Err(AppError::Forbidden(
            "Only the other participant can take this action".into(),
        ));
    }
    Ok(())
}
fn require_stage(stage: &str, allowed: &[&str]) -> AppResult<()> {
    if !allowed.contains(&stage) {
        return Err(AppError::Conflict(
            "This action is not available at the current application stage".into(),
        ));
    }
    Ok(())
}
fn required_text(body: &Value, key: &str, max: usize) -> AppResult<String> {
    let value = body.get(key).and_then(Value::as_str).unwrap_or("").trim();
    if value.is_empty() || value.len() > max {
        return Err(AppError::BadRequest(format!("Provide valid {key}")));
    }
    Ok(value.to_string())
}
fn saved_time(body: &Value, key: &str) -> AppResult<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(body.get(key).and_then(Value::as_str).unwrap_or(""))
        .map(|d| d.with_timezone(&Utc))
        .map_err(|_| AppError::BadRequest(format!("Provide {key} with a timezone")))
}
fn future_time(body: &Value, key: &str) -> AppResult<DateTime<Utc>> {
    let at = saved_time(body, key)?;
    if at <= Utc::now() || at > Utc::now() + chrono::Duration::days(730) {
        return Err(AppError::BadRequest(
            "Choose a future time within two years".into(),
        ));
    }
    Ok(at)
}
