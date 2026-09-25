---
paths:
  - "lib/night_shift_web/**"
---

# Web layer

## Hard constraints

- LiveView only. No JSON API, no SPA, no JS framework. JS hooks only where
  LiveView cannot do it.
- Mobile-first layouts. Primary users are on phones.

## Rules

- Tenant and acting member are assigned in the `on_mount` hook
  (`:current_member`, `:tenant`). LiveViews never resolve them.
- LiveViews call context functions, passing `:current_member`. No `Repo`, no
  queries, no permission decisions in this layer.
- Subscribe only when `connected?(socket)`. Topics come from the tenancy topic
  helper, never string literals.
- Message lists use streams.
- Every element a test targets carries `data-test-id`.
- Inline Tailwind styling only.
