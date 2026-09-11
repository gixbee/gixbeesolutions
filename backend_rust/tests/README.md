# Rust marketplace contracts

These tests exercise the real Axum router and PostgreSQL schema produced by Nest's entity metadata. No SMS, Firebase, Razorpay, production database or real Redis service is used. Each test creates uniquely identified fixtures; use a disposable database.

1. Build `backend` with `npm run build` to generate current entity metadata.
2. Start local PostgreSQL. Use a dedicated test account and database name beginning with `gixbee_contract_`.
3. Set `GIXBEE_TEST_DATABASE_URL` to that local database, then run `node backend_rust/tests/setup-database.cjs` from the repository root.
4. From `backend_rust`, run `cargo test --bin gixbee-backend -- --include-ignored`.

On Windows, `scripts/test-contracts.ps1 -DatabaseUrl <local-test-url>` runs steps 3 and 4. `scripts/cargo-local.ps1` recognizes the isolated Rust and GNU tools under the current user's `.codex/toolchains` directory; otherwise it uses the installed Rust/Visual Studio toolchain. Pass arguments as `-CargoArguments @('test','--bin','gixbee-backend','--','--include-ignored')` when forwarding Cargo's `--` separator through PowerShell.

Database tests are explicitly ignored in a plain `cargo test` run. Do not treat a run that skipped them as evidence that database contracts passed. Setup never loads `.env`, rejects remote hosts and rejects database names outside `gixbee_contract_*`.

Coverage includes owner permissions, persistent business calendars and moderation, multi-day rental billing, competing confirmations, career-profile criteria, hiring fee enforcement, candidate-contact privacy, deadline recovery and duplicate guarantee remedies.

Live payment delivery, real devices, deployment migrations and the remaining event/inventory/interview features require separate release verification.
