//! Shared SELECT fragments — PostgreSQL enums must be cast to `text` for sqlx `String` reads.

pub fn date_json(row: &sqlx::postgres::PgRow, column: &str) -> serde_json::Value {
    timestamp_utc(row, column)
        .map(|d| serde_json::json!(d))
        .unwrap_or(serde_json::Value::Null)
}

/// Read a timestamp column that may be `timestamptz` or naive `timestamp`.
/// Azure bookings."startedAt" is `timestamp` without time zone; sqlx DateTime<Utc>
/// fails on that type and must not be treated as missing.
pub fn timestamp_utc(
    row: &sqlx::postgres::PgRow,
    column: &str,
) -> Option<chrono::DateTime<chrono::Utc>> {
    use sqlx::Row;
    if let Ok(Some(d)) = row.try_get::<Option<chrono::DateTime<chrono::Utc>>, _>(column) {
        return Some(d);
    }
    if let Ok(d) = row.try_get::<chrono::DateTime<chrono::Utc>, _>(column) {
        return Some(d);
    }
    if let Ok(Some(d)) = row.try_get::<Option<chrono::NaiveDateTime>, _>(column) {
        return Some(d.and_utc());
    }
    row.try_get::<chrono::NaiveDateTime, _>(column)
        .ok()
        .map(|d| d.and_utc())
}

pub fn string_list(row: &sqlx::postgres::PgRow, column: &str) -> Vec<String> {
    use sqlx::Row;
    if let Ok(values) = row.try_get::<Vec<String>, _>(column) { return values; }
    row.try_get::<Option<String>, _>(column).ok().flatten().unwrap_or_default()
        .split(',').map(str::trim).filter(|s| !s.is_empty()).map(str::to_owned).collect()
}

pub const MASTER_ENTRY_COLS: &str =
    r#"id, type::text AS type, label, value, icon, category, "cityId", "isActive", "createdAt", "updatedAt""#;

pub const JOB_POST_COLS: &str = r#"
    id, "employerId", "businessId", title, description, "requiredSkills", "jobType", experience, location,
    "salaryMin", "salaryMax", "isActive", "workMode", "salaryPeriod", "experienceMin", "experienceMax",
    lat, lng, openings, "joiningType", status, "createdAt", "updatedAt"
"#;

pub const JOB_APPLICATION_COLS: &str =
    r#"id, "jobPostId", "applicantId", status::text AS status, "coverLetter", "resumeUrl", "createdAt", "updatedAt""#;

pub const BOOKING_COLS: &str = r#"
    id, "customerId", "operatorId", skill, "serviceLocation", "serviceLat", "serviceLng",
    amount, "totalAmount", type::text AS type, status::text AS status, "paymentMethod", description,
    "isPaid", "workerPaidConfirmed", "customerPaidConfirmed",
    "paymentCollectionMethod", "workerHonestyCheck", "customerSafetyCheck",
    "billingHours", "workedMinutes", "petrolDistanceKm", "petrolRatePerKm", "petrolAmount",
    "scheduledAt", "createdAt", "completedAt", "acceptedAt", "startedAt"
"#;

pub const BUSINESS_COLS: &str = r#"
    id, "ownerId", name, type::text AS type, "serviceType"::text AS "serviceType", location, "cityId",
    description, phone, "eventServices", "documentUrl", status::text AS status, "operatorIds", "offlineDays",
    "hiringProfile", "createdAt", "updatedAt"
"#;

pub const RENTAL_ITEM_COLS: &str = r#"
    id, "ownerId", name, description, "imageUrl", "imageUrls", "hourlyRate", "dailyRate", "minHoursToRent",
    "businessId", quantity, "pickupAddress", "deliveryAvailable", "deliveryFee", "depositPerUnit",
    "pickupLat", "pickupLng", "advanceAmount", "advancePercent", "pickupInstructions", "lateFeePerHour",
    condition, category, "cancellationPolicy", "availableFrom", "availableUntil", "availableWeekdays",
    "slotStartMinute", "slotEndMinute",
    "isAvailable", "createdAt", "updatedAt"
"#;

pub const RENTAL_RESERVATION_COLS: &str = r#"
    id, "itemId", "renterId", "startTime", "endTime", "totalPrice", status::text AS status,
    quantity, fulfillment, "fulfillmentAddress", "priceBreakdown", "ownerHandedOverAt", "renterCollectedAt",
    "ownerReturnedAt", "renterReturnedAt", "ownerPaidAt", "renterPaidAt", "ownerRefundedAt", "renterRefundedAt",
    "paymentStatus", "holdExpiresAt", "advanceAmount", "remainingAmount", "lateFee", "damageAmount",
    "handoverOtp", "returnOtp",
    "createdAt", "updatedAt"
"#;

pub const PROFESSIONAL_SKILL_COLS: &str =
    r#"id, "talentProfileId", name, "hourlyRate", bio, "rateChart", status::text AS status, "createdAt", "updatedAt""#;

pub const JOB_PREFERENCE_COLS: &str = r#"
    id, "userId", "jobType", skills, "preferredLocation", "expectedSalary", "salaryNegotiable",
    "employmentType"::text AS "employmentType", "experienceYears", "noticePeriod"::text AS "noticePeriod",
    "isActive", "isPaid", "paidUntil", "createdAt", "updatedAt"
"#;

pub const HIRING_REQUEST_COLS: &str = r#"
    id, "employerId", "businessId", "jobType", skills, location, "salaryOffered", "salaryMin", "salaryMax",
    "salaryNegotiable", "employmentType"::text AS "employmentType", "experienceMinYears", vacancies,
    "targetInterested", "feeAmount", "creditApplied", status::text AS status, "deadlineAt", "createdAt", "updatedAt"
"#;

pub const HIRING_INTEREST_COLS: &str = r#"id, "requestId", "candidateId", "preferenceId", response::text AS response, decision::text AS decision, "notifiedAt", "respondedAt", "createdAt", "updatedAt""#;

pub const ADMIN_STAFF_COLS: &str =
    r#"id, username, "displayName", "staffRole"::text AS "staffRole", "allowedPages", "isActive""#;

pub const WORKER_PROFILE_COLS: &str = r#"
    id, "userId", skills, "activeSkills", languages, "serviceRadiusKm", "hourlyRate",
    "isActive", "goLiveToggleCountToday", "goLiveToggleDate", "jobsSincePayment",
    "strikeCount", "verificationStatus"::text AS "verificationStatus",
    bio, title, rating, "completedJobs", "reviewCount", "lastLat", "lastLng",
    "createdAt", "updatedAt"
"#;

/// Qualify worker_profiles columns so JOINs with users/talent_profiles
/// do not hit Postgres "column reference id is ambiguous".
pub fn worker_profile_cols(alias: &str) -> String {
    format!(
        r#"{a}.id, {a}."userId", {a}.skills, {a}."activeSkills", {a}.languages, {a}."serviceRadiusKm", {a}."hourlyRate",
    {a}."isActive", {a}."goLiveToggleCountToday", {a}."goLiveToggleDate", {a}."jobsSincePayment",
    {a}."strikeCount", {a}."verificationStatus"::text AS "verificationStatus",
    {a}.bio, {a}.title, {a}.rating, {a}."completedJobs", {a}."reviewCount", {a}."lastLat", {a}."lastLng",
    {a}."createdAt", {a}."updatedAt""#,
        a = alias
    )
}
