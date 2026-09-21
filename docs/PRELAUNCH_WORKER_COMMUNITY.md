# Pre-launch worker community for Gixbee

Operating playbook • Instant Help first • One Indian city • Supply density over follower count

This document is the execution plan for collecting **verified, nearby professionals** before paid customer launch. It extends [GIXBEE_BUSINESS_FLOW.md](./GIXBEE_BUSINESS_FLOW.md) §3. It does not authorize paid ads, bulk SMS, or customer push campaigns.

## 1. What success actually is

Gixbee Instant Help only works if a request in a small map polygon finds a **verified, Go Live professional** who can accept, travel, and finish the job. A 20,000-member WhatsApp group across India, or a viral Instagram reel, does not create that. A marketplace with empty supply in the customer's neighborhood dies on the first request.

**Primary goal (pre-launch):** enough *usable* professionals in 2–3 adjacent neighborhoods and 3–4 household trades that a test request at staffed hours is usually accepted.

**Not the goal:** national brand community, follower count, or "maximum workers" as a raw number.

| Metric | Why it matters | Launch gate (internal, not a customer promise) |
| --- | --- | --- |
| Verified professionals per trade per neighborhood | Instant Help matching is local | Aim for **8–12 verified** people who actually work that trade in that area, not 8 names on a list |
| Share who completed identity + skill profile | Unverified names cannot Go Live | **≥70%** of waitlist in the launch polygon complete verification |
| Share who completed a supervised test job | Proof they can use the app | **≥5 people per launch trade** in the polygon |
| Typical travel time inside the polygon | Long travel kills earnings and response | Most accepts should be a short local trip, not city-wide |
| Languages recorded | Booking language matching | Every verified pro has spoken languages set |

A city-wide list of 500 electricians with no pin-level location is weaker than **30 electricians who live or already work in the two launch wards**.

## 2. Why "big community first" fails here

Independent household professionals in India already have work from neighbors, contractors, and existing WhatsApp contacts. They join a new app only if it looks like **more local jobs without losing control of cash**. They will not wait months for a national community to "activate."

| Approach | What it produces | Risk for Gixbee |
| --- | --- | --- |
| One huge city/state WhatsApp group | Noise, spam, people from the wrong area | Unusable for matching; group dies |
| Instagram-first worker recruitment | Views from students and other cities | High awareness, low verified local supply |
| Facebook groups / LinkedIn | Wrong occupational mix for Instant Help | Time spent on people who will never Go Live |
| National waitlist with no area filter | Impressive spreadsheet | Cannot open Instant Help anywhere |
| Field + neighborhood WhatsApp + referrals | Smaller list, high density | This is the working model |

Customer demand should stay **quiet** until the launch polygon can fulfill. Recruiting customers first creates failed searches and a reputation the product cannot recover from.

## 3. Channel ranking (use in this order)

WhatsApp is the home of this community. Instagram, YouTube Shorts, and printed material exist to **feed WhatsApp and field onboarding**, not to replace them.

| Rank | Channel | Role | Convert to |
| --- | --- | --- | --- |
| 1 | Street and trade-network field work | Highest trust. Meet the person, see tools, record area. | Waitlist row + neighborhood WhatsApp cell |
| 2 | Worker-to-worker referral | Same trade, same area, already trusted | Waitlist with referrer id |
| 3 | Neighborhood / trade WhatsApp cells | Daily contact, launch instructions, rumor control | Verified profile when the app opens |
| 4 | Existing trade associations, unions, tool shops, hardware stores | Clusters of the right people | Saturday onboarding desk |
| 5 | Short video (Instagram Reels, YouTube Shorts, WhatsApp Status) | Proof that Gixbee is real; not the CRM | Link-in-bio / QR to waitlist |
| 6 | Printed QR cards at hardware shops and tea stalls in the polygon | Reaches people who do not follow brands | Waitlist |
| 7 | Paid ads | Only after organic density is measurable | Same waitlist, with UTM / referral code |

Do not build Telegram, Discord, or a public Facebook "community" as the primary home. Those are extra rooms to moderate. One CRM (spreadsheet or simple form) plus WhatsApp is enough before launch.

## 4. Community architecture (WhatsApp)

Never put all professionals in one group. Split by **place** first, then **trade**. One person may sit in a neighborhood group and a trade group. Broadcast (WhatsApp Business) is for announcements. Groups are for questions and local coordination.

```
City ops (internal staff only)
  └── Launch city hub (staff + 8–12 worker captains)
        ├── Neighborhood A cell (all launch trades in that polygon)
        ├── Neighborhood B cell
        ├── Neighborhood C cell (only if A and B are dense)
        ├── Trade: Electrician (city-launch, optional)
        ├── Trade: Plumber
        ├── Trade: AC technician
        └── Trade: Household cleaning
```

### Rules that keep groups alive

- **Size:** keep cells under ~80 people. Above that, split by neighborhood. WhatsApp's hard cap is not the operating target.
- **Captains:** one paid or stipend city lead; one volunteer captain per cell (a respected local pro). Captains get early access, a named badge later, and the first test jobs. They do not get fake "manager" powers inside the product.
- **Content:** jobs, onboarding steps, verification status, honest "no customer jobs yet" messages. Ban rate talk that is not Gixbee policy, ban forwarding of unrelated work, ban customer phone-number dumping.
- **Language:** run the cell in the language those workers actually speak. Hindi/English-only groups in a Malayalam or Tamil launch city will empty out.
- **Broadcast vs group:** weekly status and launch date go out as a Business broadcast to people who opted in. Groups are not a newsletter.
- **No job spam before supply is live:** do not forward random "need electrician" customer messages into groups. That trains people to ignore Gixbee and work off-platform, and it skips verification, tracking, and dual payment confirm.

### What to collect on join (same fields as field onboarding)

A Google Form / WhatsApp flow is enough. Every row needs:

1. Full name as on ID  
2. Mobile (WhatsApp)  
3. Launch neighborhood (pick list, not free text)  
4. Primary trade (Electrician, Plumber, AC Technician, Cleaner; optionally Carpenter later)  
5. Sub-skills (from the Register as Pro list: switch/socket, leak, AC gas, bathroom clean, …)  
6. Tools they already own  
7. Languages they can work in  
8. Typical working hours  
9. Indicative hourly expectation (for ops, not a published rate card)  
10. How they heard (field / referral / reel / shop QR)  
11. Referrer mobile if any  
12. Consent: Gixbee will contact them for verification and test jobs; no guarantee of job volume  

This is the waitlist. It is **not** a user account. Accounts are created at onboarding with OTP, profile, and identity review.

## 5. Which trades to recruit first

Open Instant Help with household tasks that are frequent, local, and do not need specialist operating procedures Gixbee does not yet staff.

| Open at launch (recommended) | Delay until ops is ready |
| --- | --- |
| Electrician (switch, fan, light, MCB) | Nurse / bedside care (credential + safety) |
| Plumber (tap, blockage, leak) | Driver (licensing, insurance, different matching) |
| AC technician (service, gas, leak) if seasonal demand exists | Beautician, pest control, renovation (scope and materials disputes) |
| Household cleaner (bathroom, kitchen, home) | Electronics / appliance beyond AC unless a captain exists |

Carpenter can be a fifth trade **if** field recruiting already found a cluster in the same polygon. Do not add trades to look complete.

## 6. Field playbook (this is the main engine)

City lead plus 1–2 local coordinators walk the launch polygon. Target places where independent pros already gather.

**Where to stand**

- Electrical / plumbing / AC spare-part shops  
- Hardware stores and paint shops  
- Morning tea stalls near labor addas  
- Housing-society maintenance rooms (introduce the product to the supervisor, then to the regular electrician/plumber)  
- Trade association meetings if they exist in that city  

**What to say (honest, 30 seconds)**

Gixbee is an app for nearby household jobs. The customer pays you directly by cash or UPI. Gixbee is not a contractor and does not hold your job money. Before public launch we are taking only local professionals in *this* area, checking ID and skills, and running a few paid test jobs. If you join the waitlist you get the app first in this neighborhood. There is a small access credit pack later if you want to accept Instant Help jobs. No salary. No guarantee of daily jobs.

**What to do on the spot**

1. Scan QR → form, or fill it on the coordinator's phone.  
2. Add them to the **neighborhood cell**, not a giant city group.  
3. Photograph tools only with consent, for later capability review.  
4. Give a printed card: "Gixbee [City] professionals — WhatsApp [number]".  
5. Ask: "Who else in this ward does the same work?" Capture two referrals.

**Cadence:** 5 field days per week in the polygon until the density table in §1 is met. One Saturday "document camp" for ID photos and profile completion once the APK is ready for closed testing.

## 7. Instagram and short video (support channel, not the community)

Use video to make the waitlist feel real. Do not try to recruit India. Geo and language should match the launch city.

**Who should appear:** actual local professionals (with consent), the city lead, short clips of a test booking flow. Avoid actor-heavy ads that look like a national brand the product cannot support.

**Formats that convert tradespeople**

| Format | Length | Hook | End card |
| --- | --- | --- | --- |
| "I got a nearby fan-repair job and the customer paid me on UPI" (after test jobs exist) | 20–30s | Face + neighborhood name | QR / WhatsApp |
| Tool-shop standup: "If you work in [ward], join this list" | 15s | Local landmark | WhatsApp |
| Screen recording: request → accept → OTP → bill (no fake 5-minute promise) | 25s | "How a Gixbee job works" | Waitlist |
| Captain Q&A in local language | 45s | "Is this a company job?" Answer: no | WhatsApp |
| Myth clip: "We do not take your job money" | 15s | Direct cash/UPI | Waitlist |

Post the same file to Instagram Reels, YouTube Shorts, and WhatsApp Status of captains. Status and WhatsApp forwards will outperform Instagram for this audience.

**Do not claim** in any video: guaranteed daily income, Urban Company-style arrival SLAs, platform insurance, escrow, or "we pay your salary." Gixbee currently settles job money customer-to-professional. Platform revenue is access credits and period fees, explained at Go Live, not in a hype reel.

**Profile hygiene:** one Instagram account named Gixbee, city in bio, WhatsApp link, waitlist link, highlight "For professionals" vs "For households." Household content stays off until supply gates pass.

## 8. Referral mechanic (workers bring workers)

Before the app, run this on WhatsApp. After the app, the same codes can become in-app later.

- Each waitlist person gets a short code: `GX-EL-WARD-042`.  
- If they bring **two verified professionals in the same launch polygon and trade**, they get first-wave test jobs and a captain nomination.  
- After paid launch, convert that to a **one-time credit pack or fee holiday**, not cash that looks like a pyramid. Keep it attributable.  
- Reject referrals from other cities. Thank them and say Gixbee is not open there.

## 9. 10-week sequence (do not skip weeks)

Weeks assume the APK and verification ops can actually onboard. If product gates in [GIXBEE_BUSINESS_FLOW.md](./GIXBEE_BUSINESS_FLOW.md) §10 are still red, keep collecting the waitlist but do not promise a date.

| Week | Supply work | Demand / content | Exit check |
| --- | --- | --- | --- |
| 1 | Freeze launch city, 2–3 neighborhoods, 3–4 trades. Print QR. Open form. | Zero customer ads. | Map polygons and pick-list neighborhoods exist |
| 2–3 | Field every day. Seed 3 neighborhood WhatsApp cells. Appoint captains. | 3 local-language reels pointing at WhatsApp | ≥40 waitlist rows with neighborhood + trade filled |
| 4 | Saturday document camp. Start identity/capability review for the densest trade | Reels using real waitlist faces (consent) | First trade has 8+ complete profiles in one polygon |
| 5 | Repeat camp for remaining launch trades. Drop people outside the polygon from cells (move to "later city" broadcast) | Shop posters in the polygon only | Density table started for each trade |
| 6 | Closed APK: captains + 10 volunteers complete Register as Pro, languages, radius | No public Play Store push | Captains can Go Live in staging/prod as designed |
| 7 | Supervised test bookings with consenting households (staff, friends, society offices). Pay the professional the real bill. | Film *real* test jobs only | OTP, GPS, bill, dual pay confirm work |
| 8 | Fill coverage holes from declined/missed test offers. Do not add new neighborhoods. | Prepare household waitlist (separate, small) | Unmet test demand has a recruiting response |
| 9 | Staffed hours defined. Only open trades/areas that passed tests. | Household WhatsApp for the same polygon only | Fulfillment rate on tests is acceptable to city lead |
| 10 | Paid Instant Help on for those hours/areas. Keep worker cells. Start customer referrals after completed jobs. | Light local household content | Daily ops review: missed demand, earnings, disputes |

If week 6 fails (app/verification), do not run week 9 customer open. Keep the worker cells warm with honest status, not invented job pings.

## 10. How to talk about money (so the community does not revolt)

Professionals will ask three questions. Answer the same way in every group and reel.

1. **Who pays me?** The household, cash or UPI, to you. Gixbee does not hold that money.  
2. **What do I pay Gixbee?** Access to Instant Help (job credits and a period fee after a configured number of jobs). Explain both together at onboarding. Do not hide them in a viral video and surprise people at Go Live.  
3. **How much will I earn?** Unknown. Share only what test jobs in *this* polygon actually paid, after travel. Never publish a "₹X per day" promise.

Travel on Instant Help is a one-way petrol component at the configured per-km rate. Say that clearly. Materials are extra and need customer agreement in chat.

## 11. Community moderation and trust

- One staff member reads every cell daily.  
- Pin: launch area, "no job volume promise," support number, verification steps.  
- Remove recruiters selling other apps, people asking for customer numbers, and anyone sharing ID documents in-group (IDs go only through the app/admin path).  
- Safety: Gixbee is not an emergency service. Do not imply 24×7 coverage until hours are staffed.  
- Women professionals (cleaning, and later other trades): offer a smaller women-only cell if they ask; do not force mixed groups.

## 12. Lightweight CRM (before building product)

A single sheet (or Airtable) with columns matching §4, plus: verification status, APK installed, test job done, neighborhood cell, captain, drop reason. Tag every row with a source code (`field`, `referral`, `reel`, `shop-qr`). Review twice a week: **usable density**, not total rows.

When the app launches, this sheet is the call list for "install, verify, Go Live." It is not a substitute for `worker_profiles` in production.

## 13. What to stop doing

- Creating 20 Instagram accounts or city pages you cannot post to.  
- Mixing job-seekers (Find a Job / Smart Hiring) into Instant Help worker cells. Different product, different promise.  
- Buying group members or running "forward this to 10 groups" contests.  
- Opening customer ads while waitlist people still live across the whole city.  
- Promising that a WhatsApp community *is* Gixbee. The community is a waiting room. The product is verified Go Live + completed jobs.

## 14. Best idea, compressed

**Treat pre-launch as a density campaign in two or three neighborhoods, not a national community launch.**

1. Pick the polygon and 3–4 trades.  
2. Put a city lead on the street with a QR waitlist.  
3. Hold professionals in small neighborhood WhatsApp cells with local captains.  
4. Use Instagram/Reels only as a local proof engine that points at WhatsApp.  
5. Verify, test-book, then open Instant Help only where those tests worked.  
6. Let completed jobs and worker referrals grow the next street. Keep customer marketing one step behind supply.

That sequence matches how Instant Help matching actually works in the product. A large undifferentiated community does not.
