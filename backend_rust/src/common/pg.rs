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

pub const BUSINESS_COLS: &str = r#"
    id, "ownerId", name, type::text AS type, "serviceType"::text AS "serviceType", location, "cityId",
    description, "documentUrl", status::text AS status, "operatorIds", "offlineDays", "createdAt", "updatedAt"
"#;

pub const RENTAL_ITEM_COLS: &str = r#"
    id, "ownerId", name, description, "imageUrl", "hourlyRate", "dailyRate", "minHoursToRent",
    "isAvailable", "createdAt", "updatedAt"
"#;

pub const RENTAL_RESERVATION_COLS: &str = r#"
    id, "itemId", "renterId", "startTime", "endTime", "totalPrice", status::text AS status,
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
    id, "employerId", "jobType", skills, location, "salaryOffered", "salaryMin", "salaryMax",
    "salaryNegotiable", "employmentType"::text AS "employmentType", "experienceMinYears", vacancies,
    "targetInterested", "feeAmount", "creditApplied", status::text AS status, "deadlineAt", "createdAt", "updatedAt"
"#;

pub const HIRING_INTEREST_COLS: &str =
    r#"id, "requestId", "candidateId", status::text AS status, "createdAt", "updatedAt""#;

pub const ADMIN_STAFF_COLS: &str =
    r#"id, username, "displayName", "staffRole"::text AS "staffRole", "allowedPages", "isActive""#;

pub const WORKER_PROFILE_COLS: &str = r#"
    id, "userId", skills, "activeSkills", languages, "serviceRadiusKm", "hourlyRate",
    "isActive", "goLiveToggleCountToday", "goLiveToggleDate", "jobsSincePayment",
    "strikeCount", "verificationStatus"::text AS "verificationStatus",
    bio, title, rating, "completedJobs", "reviewCount", "lastLat", "lastLng",
    "createdAt", "updatedAt"
"#;
