# Gixbee Platform — Complete Flow Diagrams

> Generated from full codebase analysis. All flows verified against actual service code.

---

## 1. System Architecture Overview

```mermaid
graph TB
    subgraph Clients
        FLUTTER[Flutter App\nAndroid / iOS / Web]
        ADMIN[Angular Admin Panel\nsuper-admin-web]
    end

    subgraph Gateway
        NGINX[Nginx Reverse Proxy\nport 80/443]
    end

    subgraph Backend["NestJS Backend :3000"]
        REST[REST API\nExpress]
        WS[Socket.IO Gateway\nWebSocket]
        BULL[Bull Queue\nBackground Jobs]
    end

    subgraph DataStores
        PG[(PostgreSQL 16\nPrimary DB)]
        REDIS[(Redis 7\nCache + Queue + GEO)]
    end

    subgraph External
        FCM[Firebase FCM\nPush Notifications]
        GMAPS[Google Maps API\nLocation + Routing]
        RAZORPAY[Razorpay\nPayments]
    end

    FLUTTER -- "HTTP REST /api/*" --> NGINX
    FLUTTER -- "WebSocket /socket.io/*" --> NGINX
    ADMIN -- "HTTP REST /api/*" --> NGINX
    NGINX -- "proxy_pass :3000" --> REST
    NGINX -- "ws upgrade" --> WS
    REST --> PG
    REST --> REDIS
    WS --> REDIS
    BULL --> REDIS
    REST --> FCM
    FLUTTER --> GMAPS
    FLUTTER --> RAZORPAY
```

---

## 2. Authentication Flow

```mermaid
sequenceDiagram
    participant APP as Flutter App
    participant API as NestJS Auth API
    participant REDIS as Redis
    participant DB as PostgreSQL
    participant FCM as Firebase FCM

    APP->>API: POST /auth/request-otp {phone}
    API->>REDIS: SET otp:{phone} = "654321" (TTL 5min)
    API-->>APP: {devOtp: "654321"} (dev mode only)

    APP->>API: POST /auth/verify-otp {phone, otp}
    API->>REDIS: GET otp:{phone}
    REDIS-->>API: "654321"
    API->>REDIS: DEL otp:{phone} (single-use)
    API->>DB: findOne(phoneNumber) or create User
    DB-->>API: User entity
    API->>API: signAsync(payload) → accessToken (1h)
    API->>API: signAsync(payload) → refreshToken (30d)
    API->>REDIS: SET refresh:{userId} = sha256(refreshToken) (TTL 30d)
    API-->>APP: {accessToken, refreshToken}

    APP->>APP: Store tokens in FlutterSecureStorage
    APP->>API: PATCH /auth/fcm-token {fcmToken}
    API->>DB: user.fcmToken = fcmToken
    API->>REDIS: SET user:fcm:{userId} = fcmToken (TTL 7d)
    API-->>APP: 200 OK

    Note over APP,API: Every subsequent request
    APP->>API: Authorization: Bearer {accessToken}
    API->>API: JwtStrategy.validate(payload) → req.user

    Note over APP,API: Token expiry (1h)
    APP->>API: POST /auth/refresh {refreshToken}
    API->>REDIS: GET refresh:{userId}
    API->>API: Compare sha256(refreshToken) == storedHash
    API-->>APP: {accessToken} (new 1h token)
```

---

## 3. Customer Booking Flow — Instant Help

```mermaid
flowchart TD
    A([HomeScreen]) --> B[BookServicesSplitScreen]
    B --> C{Instant or Planned?}

    C -- Instant --> D[PresenceCheckScreen\nSelf or Contact?]
    D --> E[POST /bookings\ntype=INSTANT, skill, location,\nonSiteContact]

    C -- Plan Ahead --> F[WorkerListScreen\nBrowse workers]
    F --> G[WorkerDetailScreen\nView profile & packages]
    G --> H[BookingScreen\nDate / Address / Payment]
    H --> E

    E --> I{Backend: createBooking}
    I --> J[Generate arrivalOtp\n& completionOtp → Redis 24h]
    I --> K[Cache booking:status → Redis]
    I --> L[ZADD worker:pending sorted set]
    I --> M[Bull: enqueue requestTimeout\ndelay=90s]
    I --> N[Query skill:index → worker IDs\nSend FCM to workers]

    N --> O[WaitingForWorkerScreen\nPolls GET /bookings/id/status\nevery 3s]

    O --> P{Worker responds\nwithin 90s?}
    P -- No --> Q[Bull fires requestTimeout\nStatus = CANCELLED\nFCM to customer: No workers]
    P -- Yes --> R[PATCH /bookings/id/accept]

    R --> S[acceptBooking TRANSACTION:\nStatus = ACCEPTED\nWorker wallet -12 Rs\nOther bookings → CANCELLED\nBull: 7min reminder + 10min GPS check]

    S --> T[LiveTrackingMapScreen\nSocket.IO: joinJobRoom\nWorker streams GPS every 5s]

    T --> U[Worker: PATCH /bookings/id/arrive\narrivalOtp sent to customer]

    U --> V[ArrivalOtpScreen\nCustomer shows OTP to worker]
    V --> W[POST /bookings/id/arrival OTP\nverifyArrivalOtp\nStatus = ACTIVE\nstartedAt recorded]

    W --> X[Work in Progress]
    X --> Y[Worker: PATCH /bookings/id/complete\ncompletionOtp generated\nFCM to customer]

    Y --> Z[CompletionOtpScreen\nCustomer enters OTP]
    Z --> AA[POST /bookings/id/completion OTP\nStatus = COMPLETED\nbillingHours calculated\nWallet deduct Rs.12]

    AA --> AB{Payment Method?}
    AB -- WALLET --> AC[Auto-deducted ✓\nWalletTransaction DEBIT]
    AB -- DIRECT --> AD[CollectPaymentScreen\nWorker marks paid\nPATCH /bookings/id/mark-paid]

    AC --> AE[Rate worker 1-5 ⭐\nPOST /bookings/id/rating]
    AD --> AE
```

---

## 4. Worker Job Flow

```mermaid
flowchart TD
    A([Worker Logs In]) --> B[MainWrapper.initState]
    B --> C[_initSocket: Connect Socket.IO with JWT]
    B --> D[_initNotifications: FCM Setup]
    B --> E[_maybeStartWorkerPoll\nTimer every 5s → GET /bookings/pending]

    subgraph JobReceived["Job Received — 3 Parallel Channels"]
        F1[Socket.IO: new_booking_request]
        F2[FCM: type=new_booking notification]
        F3[HTTP Poll: pending bookings list]
    end

    C --> F1
    D --> F2
    E --> F3

    F1 --> G{_shownBookingIds dedup check}
    F2 --> G
    F3 --> G

    G -- New --> H[IncomingJobScreen\nFull-screen modal\n90s countdown timer]

    H --> I{Worker Decision}
    I -- Accept --> J[PATCH /bookings/id/accept]
    I -- Decline --> K[PATCH /bookings/id/reject\nNext job in queue]
    I -- Timeout --> L[Auto-decline after 90s]

    J --> M[Backend Transaction:\nStatus=ACCEPTED\nOther jobs auto-cancelled\nRs.12 deducted\nBull jobs scheduled]

    M --> N[Navigate to Bookings tab\nmyBookingsProvider invalidated]

    N --> O[LiveTrackingMapScreen\nWorker sees route to customer\nSocket: joinJobRoom + startLocationStream]

    O --> P[Geolocator.getPositionStream\n10m threshold OR every 5s\nSocket.emit: updateLocation]

    P --> Q{Bull GPS Check @10min}
    Q -- Within 5km --> R[Check passes ✓]
    Q -- Beyond 5km --> S[gpsStrikes++]
    S --> T{Strikes >= 3?}
    T -- Yes --> U[CANCELLED\nNotify both parties\nWorker available again]
    T -- No --> V[Reschedule check in 3min\nNotify worker]

    O --> W[Mark Arrived:\nPATCH /bookings/id/arrive]
    W --> X[Enter customer's arrivalOTP\nPOST /bookings/id/arrival\nStatus = ACTIVE]

    X --> Y[Do the work]
    Y --> Z[PATCH /bookings/id/complete\ncompletionOtp sent to customer]
    Z --> AA[Customer enters OTP\nStatus = COMPLETED\nWorker status = available]
```

---

## 5. Background Jobs Flow (Bull Queue)

```mermaid
sequenceDiagram
    participant BS as BookingsService
    participant BULL as Bull Queue (Redis)
    participant BP as BookingsProcessor
    participant NS as NotificationsService
    participant RS as RedisService
    participant DB as PostgreSQL

    Note over BS,DB: On booking creation
    BS->>BULL: add('requestTimeout', {bookingId}, delay=90s)

    Note over BS,DB: On booking accepted
    BS->>BULL: add('sevenMinuteReminder', {bookingId}, delay=7min)
    BS->>BULL: add('tenMinuteGpsCheck', {bookingId}, delay=10min)

    rect rgb(255, 240, 200)
        Note over BULL,BP: Job 1: requestTimeout fires at t+90s
        BULL->>BP: process('requestTimeout')
        BP->>DB: getBooking(bookingId)
        alt Status is still REQUESTED
            BP->>DB: updateStatus(CANCELLED)
            BP->>NS: sendToUser(customerId, "No workers available")
        else Already handled
            BP-->>BULL: skip
        end
    end

    rect rgb(200, 255, 200)
        Note over BULL,BP: Job 2: sevenMinuteReminder fires at t+7min
        BULL->>BP: process('sevenMinuteReminder')
        BP->>DB: getBooking(bookingId)
        alt Status is ACCEPTED
            BP->>NS: sendToUser(workerId, "Customer is waiting reminder")
        else Not ACCEPTED
            BP-->>BULL: skip
        end
    end

    rect rgb(200, 220, 255)
        Note over BULL,BP: Job 3: tenMinuteGpsCheck fires at t+10min (reschedules)
        BULL->>BP: process('tenMinuteGpsCheck')
        BP->>DB: getBooking(bookingId)
        alt Status is not ACCEPTED
            BP-->>BULL: return "Monitoring Stopped"
        else Status is ACCEPTED
            BP->>RS: getWorkerLocation(workerId)
            alt No location cached
                BP->>BS: addGpsStrike(bookingId)
            else Location found
                BP->>BP: calculateDistance(cached, destination)
                alt Distance > 5km
                    BP->>BS: addGpsStrike(bookingId)
                else Within range
                    BP-->>BULL: return "GPS Verified"
                end
            end
            alt gpsStrikes >= 3
                BS->>DB: updateStatus(CANCELLED)
                BS->>NS: Notify worker + customer
                BS->>RS: SET worker:status = available
            else gpsStrikes < 3
                BS->>NS: notifyGpsStrike(workerId, strikeCount)
                BULL->>BULL: add('tenMinuteGpsCheck', delay=3min)
            end
        end
    end
```

---

## 6. Real-time Communication Flow

```mermaid
flowchart LR
    subgraph Worker["Worker Device"]
        WA[Flutter App]
        GEO[Geolocator\nStream]
    end

    subgraph Customer["Customer Device"]
        CA[Flutter App\nLiveTrackingMapScreen]
    end

    subgraph Backend["NestJS Backend"]
        GW[WorkerGateway\nSocket.IO]
        RS[RedisService]
        NS[NotificationsService]
        BS[BookingsService]
    end

    subgraph Infra["Infrastructure"]
        REDIS[(Redis\nGEO + Cache)]
        FCM[Firebase FCM]
    end

    GEO -- "position every 5s\n(10m threshold)" --> WA
    WA -- "emit: updateLocation\n{userId,lat,lng,jobId}" --> GW
    GW -- "SET worker:location:{id}\nGEOADD workers:geo" --> RS
    RS --> REDIS
    GW -- "emit to room job_{jobId}:\nlocationUpdated" --> CA
    CA -- "updates Google Maps marker" --> CA

    WA -- "emit: joinJobRoom\n{jobId}" --> GW
    GW -- "client.join(job_{jobId})" --> GW

    BS -- "booking created/accepted/completed" --> NS
    NS -- "getCachedFcmToken → Redis\nfallback → DB" --> REDIS
    NS -- "sendToDevice(token,payload)" --> FCM
    FCM -- "push notification" --> WA
    FCM -- "push notification" --> CA

    subgraph Fallback["HTTP Polling Fallback"]
        P1[Worker: GET /bookings/pending\nevery 5s]
        P2[Customer: GET /bookings/id/status\nevery 3s — Redis first]
    end

    P2 -- "cache hit" --> REDIS
    P2 -- "cache miss → DB query" --> Backend
```

---

## 7. Hiring & Talent Flow

```mermaid
flowchart TD
    subgraph TalentSide["Talent Side"]
        T1[POST /talent/profile\neducation, skills, experience] --> T2[TalentProfile saved to DB]
        T2 --> T3[Redis: SADD skill:index:skillName → talentId]
        T3 --> T4[GET /hiring/jobs?skills=React]
        T4 --> T5[DB query: JobPost by requiredSkills]
        T5 --> T6[POST /hiring/jobs/id/apply\ncoverLetter]
        T6 --> T7[JobApplication: status=APPLIED]
        T7 --> T8[GET /hiring/my-applications\nTrack status in ApplicationTrackerScreen]
    end

    subgraph HRSide["HR Manager Side"]
        H1[POST /businesses\ntype=HIRING] --> H2[Business entity\nstatus=PENDING]
        H2 --> H3[Admin approves → VERIFIED]
        H3 --> H4[POST /hiring/jobs\ntitle, skills, salary range]
        H4 --> H5[JobPost: isActive=true\nFCM to matched talent]
        H5 --> H6[GET /hiring/jobs/id/applications\nHiringPipelineScreen]
        H6 --> H7[PATCH /hiring/applications/id/status]
        H7 --> H8{Status Decision}
        H8 -- INTERVIEW --> H9[Notify talent via FCM]
        H8 -- SELECTED --> H9
        H8 -- REJECTED --> H9
        H8 -- NO_SHOW --> H10[noShowCount++ on TalentProfile]
    end

    subgraph AdminSide["Admin Panel"]
        A1[GET /admin-user-list\nUsersComponent] --> A2[View talent skills\nProfessionalSkill list]
        A2 --> A3[PATCH /admin-user-list/skill/id/status]
        A3 --> A4{Skill Decision}
        A4 -- APPROVED --> A5[Skill visible in marketplace]
        A4 -- REJECTED --> A6[Skill hidden]
    end
```

---

## 8. Rental Flow

```mermaid
sequenceDiagram
    participant V as Vendor (Flutter)
    participant API as NestJS API
    participant DB as PostgreSQL
    participant R as Renter (Flutter)

    V->>API: POST /rentals {name, hourlyRate, dailyRate, minHoursToRent}
    API->>DB: INSERT RentalItem (isAvailable=true)
    API-->>V: {rentalItem}

    R->>API: GET /rentals
    API->>DB: SELECT items WHERE isAvailable=true
    API-->>R: [{rentalItem...}]

    R->>API: POST /rentals/:id/reserve {startTime, endTime}
    API->>API: Validate minHoursToRent constraint
    API->>DB: SELECT reservations WHERE overlap AND status IN (CONFIRMED, ACTIVE)
    alt Overlap found
        API-->>R: 409 Conflict — Already reserved
    else Available
        API->>API: totalPrice = hours × hourlyRate (or dailyRate)
        API->>DB: INSERT RentalReservation (status=PENDING)
        API-->>R: {reservation, totalPrice}
    end

    V->>API: PATCH /rentals/reservations/:id/confirm
    API->>DB: Re-validate no overlap created since PENDING
    API->>DB: UPDATE status = CONFIRMED
    API-->>V: {reservation}

    Note over V,R: Reservation lifecycle continues
    Note over V,R: CONFIRMED → ACTIVE → COMPLETED
    Note over V,R: or CONFIRMED → CANCELLED / REJECTED
```

---

## 9. Admin Panel Flow

```mermaid
flowchart TD
    A([Browser: Angular App]) --> B{Auth Guard Check\nlocalStorage token?}
    B -- No token --> C[/login route\nLoginComponent]
    C --> D[POST /auth/admin-login\nusername + password]
    D --> E{Valid credentials?}
    E -- No --> F[Show error]
    E -- Yes --> G[Store accessToken in localStorage\nNavigate to /dashboard]

    B -- Has token --> G

    G --> H[LayoutComponent\nSide nav + content area]

    H --> I[DashboardComponent\nGET /admin-user-list/summary]
    I --> I1[Display: Total Users\nActive Workers\nBookings\nPending Approvals]

    H --> J[UsersComponent\nGET /admin-user-list]
    J --> J1[User table with\nname, role, phone, approval status]
    J1 --> J2[Click user → Modal]
    J2 --> J3[Show TalentProfile\n+ ProfessionalSkills table]
    J3 --> J4[PATCH /admin-user-list/id/status\nAPPROVED or REJECTED]
    J3 --> J5[PATCH /admin-user-list/skill/id/status\nAPPROVED or REJECTED]

    H --> K[MasterEntriesComponent\nGET /master-entries]
    K --> K1[Filter by type:\nCATEGORY / SERVICE / ROLE\nCONFIGURATION / BANNER]
    K1 --> K2[POST /master-entries\nCreate entry]
    K1 --> K3[PATCH /master-entries/id\nUpdate entry]
    K1 --> K4[DELETE /master-entries/id]
    K1 --> K5[POST /uploads/image\nUpload banner image]

    H --> L[BusinessesComponent\nGET /businesses]
```

---

## 10. Database Entity Relationships

```mermaid
erDiagram
    USER {
        uuid id PK
        string phoneNumber UK
        string name
        enum role
        decimal walletBalance
        boolean isVerified
        string fcmToken
        boolean hasWorkerProfile
        boolean isAvailableForWork
        enum approvalStatus
    }

    WORKER_PROFILE {
        uuid id PK
        string[] skills
        decimal hourlyRate
        jsonb availabilitySchedule
        boolean isActive
        int goLiveToggleCountToday
        int noShowCount
        int strikeCount
        enum verificationStatus
        decimal rating
        int completedJobs
        float lastLat
        float lastLng
    }

    TALENT_PROFILE {
        uuid id PK
        string[] education
        string[] skills
        string experience
        decimal hourlyRate
        enum currentStatus
        boolean jobAlertsEnabled
        int noShowCount
        int searchRank
    }

    PROFESSIONAL_SKILL {
        uuid id PK
        string name
        decimal hourlyRate
        enum status
        string bio
        jsonb rateChart
    }

    BOOKING {
        uuid id PK
        string skill
        string serviceLocation
        float serviceLat
        float serviceLng
        jsonb onSiteContact
        enum type
        enum status
        decimal amount
        string arrivalOtp
        string completionOtp
        timestamp scheduledAt
        timestamp startedAt
        timestamp completedAt
        int gpsStrikes
        decimal billingHours
        int rating
        boolean isPaid
    }

    WALLET_TRANSACTION {
        uuid id PK
        decimal amount
        enum type
        string description
        timestamp timestamp
    }

    BUSINESS {
        uuid id PK
        enum type
        string name
        string location
        enum status
        string[] operatorIds
    }

    RENTAL_ITEM {
        uuid id PK
        string name
        decimal hourlyRate
        decimal dailyRate
        int minHoursToRent
        boolean isAvailable
    }

    RENTAL_RESERVATION {
        uuid id PK
        timestamp startTime
        timestamp endTime
        decimal totalPrice
        enum status
    }

    JOB_POST {
        uuid id PK
        string title
        string description
        string[] requiredSkills
        decimal salaryMin
        decimal salaryMax
        boolean isActive
    }

    JOB_APPLICATION {
        uuid id PK
        string coverLetter
        enum status
    }

    MASTER_ENTRY {
        uuid id PK
        enum type
        string label
        string value
        string icon
        boolean isActive
    }

    USER ||--o| WORKER_PROFILE : "has"
    USER ||--o| TALENT_PROFILE : "has"
    TALENT_PROFILE ||--o{ PROFESSIONAL_SKILL : "has"
    USER ||--o{ BOOKING : "books (customer)"
    USER ||--o{ BOOKING : "works (operator)"
    USER ||--o{ WALLET_TRANSACTION : "has"
    USER ||--o{ BUSINESS : "owns"
    USER ||--o{ RENTAL_ITEM : "lists"
    USER ||--o{ RENTAL_RESERVATION : "rents"
    USER ||--o{ JOB_POST : "posts"
    USER ||--o{ JOB_APPLICATION : "applies"
    RENTAL_ITEM ||--o{ RENTAL_RESERVATION : "reserved via"
    JOB_POST ||--o{ JOB_APPLICATION : "receives"
```

---

## 11. Redis Key Map

```mermaid
mindmap
  root((Redis Keys))
    Auth
      otp:{phone}
        TTL: 5 min
        OTP login code
      otp:booking:{id}:arrival
        TTL: 24h
        Arrival gate OTP
      otp:booking:{id}:completion
        TTL: 24h
        Completion gate OTP
      refresh:{userId}
        TTL: 30 days
        SHA256 refresh token hash
    Notifications
      user:fcm:{userId}
        TTL: 7 days
        FCM device token
    Bookings
      booking:status:{id}
        TTL: 24h
        Status + OTPs JSON
      worker:pending:{workerId}
        TTL: 120s
        Sorted Set of pending booking IDs
    Workers
      worker:location:{id}
        TTL: 1h
        lat, lng, timestamp JSON
      worker:status:{id}
        TTL: 1h
        available or busy
      worker:snapshot:{id}
        TTL: 24h
        Full WorkerDTO JSON
    Discovery
      skill:index:{skillName}
        TTL: 24h
        Set of worker IDs
      workers:geo
        TTL: permanent
        Redis GEO index
```

---

## 12. Module Dependency Graph

```mermaid
graph TD
    APP[AppModule]

    APP --> AUTH[AuthModule]
    APP --> USERS[UsersModule]
    APP --> REDIS[RedisModule\nGlobal]
    APP --> NOTIF[NotificationsModule]
    APP --> WALLETS[WalletsModule]
    APP --> WORKERS[WorkersModule]
    APP --> TALENT[TalentModule]
    APP --> BOOKINGS[BookingsModule]
    APP --> ENGINE[WorkerEngineModule\nSocket.IO Gateway]
    APP --> RENTALS[RentalsModule]
    APP --> HIRING[HiringModule]
    APP --> BIZ[BusinessesModule]
    APP --> MASTER[MasterEntriesModule]

    AUTH --> USERS
    USERS --> TALENT
    BOOKINGS --> WALLETS
    BOOKINGS --> NOTIF
    BOOKINGS --> WORKERS
    WORKERS --> WALLETS
    HIRING --> NOTIF
    HIRING --> TALENT
    ENGINE --> REDIS

    style REDIS fill:#f96,stroke:#f60
    style APP fill:#69f,stroke:#36c
```
