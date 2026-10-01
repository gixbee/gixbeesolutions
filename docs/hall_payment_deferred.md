# Hall payment (Phase 5 — deferred)

Product has not approved a payment model for hall bookings.

Until then:

- Package step 4 stores advance settings as **commercial terms** only.
- Phase 3 customer accept creates a `CONFIRMED` hall reservation without wallet debit.
- Hall-linked quotes complete on dual completion acknowledgements (no payment timestamps required).

When product chooses:

| Mode | Meaning |
|------|---------|
| Gixbee collects | Wire payment orders / checkout (explicit approval required) |
| Owner-recorded | Attestation that advance was received outside Gixbee |

Do not implement wallet flows for halls without that approval.
