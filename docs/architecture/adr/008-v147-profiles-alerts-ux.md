# ADR-008: v147 UX — Profiles + Alerts on Existing Smart Hiring API

**Status:** Proposed (architecture recommendation — awaiting product sign-off)  
**Date:** 2026-08-30  
**Deciders:** Product (Kelly / Jan) + architecture (Jim)

## Context

HTML prototype v147 (`Gixbee_v147 (3).html`) presents Find a Job as:

- **Profiles** home (multi career profiles, 2 free)
- **Alerts** (smart matches)
- **Status** (post-Interested pipeline)
- **Settings**

Shipped Flutter (2026-08-17) uses **Jobs · Offers · Job Types · Apps** tabs on the same Smart Hiring backend (`JobPreference`, `HiringRequest`, `HiringInterest`).

Backend matching rules (salary ceiling, job type equality, skill overlap, estimate API, Interested privacy) already implement the **engine** described in v147. The gap is primarily **information architecture and employer wizard depth**, not a second matching system.

## Decision

**Target direction:** Adopt v147 **navigation and screen metaphors** as the UX north star while **retaining the current NestJS matching module and payment purposes**.

Concretely:

1. **Do not** build a parallel "alert engine" or new entities for prototype `profiles[]` — map them to `JobPreference`.
2. **Do not** remove classic job board without PM decision — keep as secondary tab (prototype de-emphasizes but shipped still uses it).
3. **Do** plan Flutter IA migration: Profiles-centric home + Alerts-first smart loop (see [PROTOTYPE_v147_HIRING_FLOWS.md](../PROTOTYPE_v147_HIRING_FLOWS.md) §7).
4. **Do** extend API when prototype requires fields absent today: employment type, salary range, negotiable flags (contract change — Oscar review required).

**Rejected alternative:** Freeze shipped tabs forever — leaves persistent PM/engineering confusion (Jobs tab ≠ alerts).

**Rejected alternative:** Rewrite matching from scratch to match HTML mock — wasteful; backend already aligned.

## Consequences

**Positive**
- Single matching source of truth
- PM can prioritize UI migration without blocking on P0 secrets (MSG91/Razorpay)
- Kelly/Jan share one gap table against prototype

**Negative**
- Tab rename / re-home is user-visible churn for existing APK users
- Salary range + negotiable needs migration + matcher change before v147 employer `hj3` is fully honest
- Prototype Shop (`s1–s8`) and ₹299 unlimited subscription remain out of scope until separate ADRs

## Review triggers

- Product chooses classic-only or smart-only → update this ADR
- Any new monetization (subscription vs per-slot) → update ADR-001/006 + `money-model.ts`
- Employer wizard ships salary range → update `matching.service.ts` + ADR-006 contract appendix
