//! Shared SELECT fragments — PostgreSQL enums must be cast to `text` for sqlx `String` reads.

pub const MASTER_ENTRY_COLS: &str =
    r#"id, type::text AS type, label, value, icon, category, "cityId", "isActive", "createdAt", "updatedAt""#;

pub const JOB_POST_COLS: &str = r#"
    id, "employerId", title, description, "requiredSkills", "jobType", experience, location,
    "salaryMin", "salaryMax", "isActive", "createdAt", "updatedAt"
"#;

pub const JOB_APPLICATION_COLS: &str =
    r#"id, "jobPostId", "applicantId", status::text AS status, "coverLetter", "resumeUrl", "createdAt", "updatedAt""#;

pub const BOOKING_COLS: &str = r#"
    id, "customerId", "operatorId", skill, "serviceLocation", "serviceLat", "serviceLng",
    amount, type::text AS type, status::text AS status, "paymentMethod", description
"#;

pub const BUSINESS_COLS: &str =
    r#"id, "ownerId", name, type::text AS type, status::text AS status, "createdAt", "updatedAt""#;

pub const RENTAL_ITEM_COLS: &str = r#"
    id, "ownerId", name, description, "imageUrl", "hourlyRate", "dailyRate", "minHoursToRent",
    "isAvailable", "createdAt", "updatedAt"
"#;

pub const RENTAL_RESERVATION_COLS: &str = r#"
    id, "itemId", "renterId", "startTime", "endTime", "totalPrice", status::text AS status,
    "createdAt", "updatedAt"
"#;

pub const PROFESSIONAL_SKILL_COLS: &str =
    r#"id, "userId", skill, status::text AS status, "createdAt", "updatedAt""#;

pub const JOB_PREFERENCE_COLS: &str =
    r#"id, "userId", "jobType"::text AS "jobType", status::text AS status, "createdAt", "updatedAt""#;

pub const HIRING_REQUEST_COLS: &str =
    r#"id, "employerId", "jobType"::text AS "jobType", status::text AS status, "matchFeeInr", "createdAt", "updatedAt""#;

pub const HIRING_INTEREST_COLS: &str =
    r#"id, "requestId", "candidateId", status::text AS status, "createdAt", "updatedAt""#;

pub const ADMIN_STAFF_COLS: &str =
    r#"id, username, "displayName", "staffRole"::text AS "staffRole", "allowedPages", "isActive""#;

pub const WORKER_PROFILE_COLS: &str = r#"
    w.id, w."userId", w.skills, w."hourlyRate", w."serviceRadiusKm", w."isLive", w.lat, w.lng,
    w."verificationStatus"::text AS "verificationStatus", w."createdAt", w."updatedAt"
"#;
