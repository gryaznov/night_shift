---
paths:
  - "test/**"
---

# Testing

## Structure

- Context tests: `test/night_shift/`, `use NighShift.DataCase`.
- LiveView tests: `test/night_shift_web/live/`, `use NighShiftWeb.ConnCase`.
- Tenant data comes only from fixture helpers in `test/support/fixtures/`.
  `tenant_fixture/0` hands out one of the two tenants `NightShift.TenantSetup`
  provisions before the suite starts; `tenant_fixture(:two)` is the other side
  of an isolation test. Neither creates a schema. Never call Triplex directly
  from a test.
- Tests touching tenant schemas are `async: false` (schema DDL and sandbox).
  Provisional — revisit if the suite exceeds 30s.

## Assertions

- Assert observable behaviour, never internals.
- A test that would still pass with the feature removed is a defect.
- Never fabricate ids — construct real records via fixtures.
- Every authorization or isolation criterion gets a negative test: other
  tenant, other member, deactivated member, insufficient role.

## Selectors

- `data-test-id="..."` only. If markup lacks it, propose the markup change.

## Contract

- Context tests call only public functions with a `@spec`.
- Tests derive from acceptance criteria, never from the implementation.

## Prohibited

- Weakening an assertion, narrowing a check or deleting a case to go green.
