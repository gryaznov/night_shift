# 0003 — Announcements with acknowledgement

Status: draft
Brief: none

## Intent

The important operational information might get buried in a chat between tons of regular memders' messages (e.g. "hi all!", "check this mem out", etc.), and a manager has no way to know who actually saw it.

Announcements are separate from chat, cannot be replied to, and require each recipient to mark them as "read". The manager sees who has not.

## Acceptance criteria

1. A manager can post an announcement to the whole tenant or to any one site of
   that tenant. A staff member cannot post announcements.
2. A member sees announcements targeted at them — tenant-wide, or at their own
   site — newest first. An author does not see their own announcement in that
   list.
3. An announcement is recorded as read when it appears in a recipient's list;
   they need do nothing. The time of that first read is recorded and never
   changes — seeing it again changes nothing.
4. Any manager of the tenant sees, for each announcement, how many of its
   current audience have read it and the names of those who have not. The
   audience is every active member the announcement targets, excluding its
   author. A member deactivated after posting is not counted; a member added
   after posting is counted as not yet read. These figures change while the
   manager is watching, without reloading.
5. A new announcement appears for recipients viewing the announcements page
   instantly, without reloading.
6. A member sees how many announcements they have not read (an integer
   counter) on every page where they are acting in a tenant. It rises when an
   announcement arrives and falls when one is read, without reloading. Pages
   with no tenant in scope — sign-in, settings, no-access — show no counter.
7. After the publication, an announcement cannot be edited, updated, or
   deleted by anyone, including its author.

## Out of scope

- Replies, comments, reactions.
- Scheduling, expiry, reminders, escalation.
- Targeting by team or by individual.
- Push, email or SMS delivery.

## Notes on the criteria

Criteria 1–7 were amended after the rulings given when this plan was written;
everything below was written against the amended text.

Two things the criteria deliberately do not say. Criterion 5's "instantly" has
no threshold and is tested as "without a reload", which is what
`Phoenix.LiveViewTest` can observe. Criterion 7 is enforced by the context
exposing no update or delete function and by no route reaching one — not by a
database trigger, so a console still can.

`## Intent` still says recipients "mark them as read", which criterion 3 no
longer requires. That section is yours; it is left as written.

## Running alongside 0002

0002 is in flight on the `chat` branch (through its step 5 at 19132ce). This
plan follows the conventions 0002 has already committed rather than inventing
parallel ones.

- **Actor-only signatures.** `Chat` takes the acting member and derives the
  tenant from `member.tenant_id` (`lib/night_shift/chat.ex:74`); so does
  `Announcements`. No function takes a tenant alongside a member, so no caller
  can pass a mismatched pair.
- **A private `acting/1`, not a shared helper.** `Chat` re-reads liveness
  through its own private `acting/1` (`lib/night_shift/chat.ex:162`).
  `Announcements` does the same. Extracting a public
  `Members.fetch_active/1` while 0002 is mid-flight would edit
  `lib/night_shift/members.ex` — which 0002 has already changed and changes
  again at its step 6 — and would leave three copies of the invariant-4 check
  rather than one. The extraction is a job for after both land, collapsing all
  three at once.
- **`seq`, not a timestamp, for ordering.** Adopted from 0002's `messages`:
  `timestamps` are `:utc_datetime`, so two announcements posted in the same
  second cannot be ordered by `inserted_at`, and criterion 2's "newest first"
  would be unstable — most visibly in a test that posts three in a loop.
- **Files 0002 also touches** are deferred to the last two steps:
  `priv/repo/seeds.exs` (its step 11) and `docs/DECISIONS.md` plus
  `docs/CHANGELOG.md` (its step 12). Whichever plan wraps second renumbers its
  DECISIONS entries.
- **Opposite read semantics, deliberately.** 0002 ruling 3 makes a new hire's
  inherited chat history count as *already read*; criterion 4 here makes a
  member added after posting count as *not yet read*. Chat unread is a cursor
  over a stream; an announcement needs a receipt per person. The wrap step
  records why they differ.
- `test/support/fixtures/accounts_fixtures.ex` is touched by step 1 only.
  `user_fixture` must default the new name, so none of 0002's tests have to
  mention it.

## Implementation plan

### Placement

`announcements` and `announcement_acknowledgements` are business data, so both
live in the tenant schema (invariant 1) and are created by a tenant migration
(invariant 9). The audience is `public.members`, so every audience question is
a cross-schema question: a tenant-prefixed query for the announcement and its
acknowledgements, a `public` query on an explicitly passed `tenant_id` for the
members, and the set difference in Elixir. Cross-schema joins are avoided; the
two halves never share a query.

`users.name` is a new `public` column, because criterion 4 needs a person's
name and `users` has only `email` today.

### Data

`users` gains `name`, `:string`, not null, max 160. Existing rows are
backfilled from the local part of the email in the same migration, so the
column can be `NOT NULL` from the start.

`announcements` (tenant schema)

| column | type | note |
| --- | --- | --- |
| `id` | `binary_id` | |
| `author_member_id` | `references(:members, prefix: "public")`, `on_delete: :restrict` | never deleted (invariant 8) |
| `site_id` | `references(:sites)`, nullable | `NULL` = whole tenant; any site of this tenant |
| `body` | `text`, not null, `char_length between 1 and 2000` | as 0002's `messages` |
| `seq` | `bigserial`, unique | the ordering key for criterion 2 |
| `inserted_at` | `utc_datetime` | **no `updated_at`** — criterion 7 in the table shape |

`announcement_acknowledgements` (tenant schema)

| column | type | note |
| --- | --- | --- |
| `announcement_id` | `references(:announcements)` | composite primary key |
| `member_id` | `references(:members, prefix: "public")` | composite primary key |
| `inserted_at` | `utc_datetime`, not null | the recorded read time (criterion 3) |

The composite primary key is what makes criterion 3 idempotent at the database
rather than only in code: the first view wins and its timestamp is never
overwritten. It follows 0002's `group_reads`, which is keyed the same way.

### Reading is implicit

A read is recorded when the announcement is rendered in the member's list, not
by a control they click. Consequences, accepted:

- Criterion 4's "who has not" means "who has not opened the announcements page
  since it was posted".
- Criterion 6's counter falls to zero on every visit to that page.
- A row is written at most once per member per announcement, so the read
  broadcast is bounded by audience size, not by page views.

### Modules

- `NightShift.Announcements` — the whole context. Every function takes the
  acting member first (invariant 5), derives the tenant from
  `member.tenant_id`, and re-reads liveness through a private `acting/1`
  (invariant 4).
  - `post_announcement(actor, attrs)` — manager only; `site_id` is `nil` or any
    site of this tenant.
  - `list_for_member(actor)` — pure read, newest `seq` first, each with its
    `read_at` or `nil`.
  - `record_views(actor, announcements)` — writes the missing
    acknowledgements, idempotent, returns what it wrote. Kept separate from
    `list_for_member/1` so the list stays a query and the tests can assert each
    half on its own.
  - `get_for_member(actor, id)` — `{:error, :forbidden}` when not targeted;
    this is what a LiveView calls on a broadcast, so targeting stays a context
    decision.
  - `unread_count(actor)` — integer.
  - `list_with_read_state(actor)` — any manager of the tenant: per
    announcement, the current audience, the read count and the unread members
    with their names.
  - `subscribe(actor)` — authorizes, then subscribes, as 0002's
    `Chat.subscribe/2` does.
- `NightShift.Announcements.Announcement`, `.Acknowledgement` — schemas.
  `member_id` is a plain `:binary_id` with no `belongs_to`, for the reason
  0002 records: an association across schemas would let a preload inherit the
  tenant prefix and look for `members` inside the tenant schema.
- `NightShift.Accounts` — `name` cast and validated in the registration
  changeset.
- `NightShiftWeb.AnnouncementsLive` — replaces the 0001 placeholder.
- `NightShiftWeb.TenantAuth` — assigns the unread counter and subscribes to
  `Tenancy.topic(tenant, :announcements)`, next to the existing `:members`
  subscription (`lib/night_shift_web/tenant_auth.ex:35-58`). Its announcement
  hook must return `{:cont, socket}` so `AnnouncementsLive` still receives the
  message.
- `lib/night_shift_web/components/layouts/app.html.heex` — the counter badge on
  the existing `nav-announcements` link.

### Audience

Active members of the tenant whose `site_id` matches the announcement, or all
active members when `site_id` is `NULL`, excluding `author_member_id`. The
author never appears in their own announcement's denominator, never sees it in
their own list and it never raises their counter. Managers other than the
author are ordinary recipients.

### Web contract

Fixed here so spec-tester has selectors before implementation, as 0002 had to
do at its step 4.

- `/announcements` — `AnnouncementsLive`, `:index`. Container
  `data-test-id="announcements"`; one `data-test-id="announcement-<id>"` per
  announcement in a stream, newest first.
- Manager compose form `data-test-id="announcement-form"`, fields
  `announcement[body]` and `announcement[site_id]` (blank = whole tenant);
  `data-test-id="announcement-error"` for the validation message. Absent
  entirely for staff.
- Read state, managers only: `data-test-id="read-count-<id>"` carrying
  `read/audience`, and `data-test-id="unread-members-<id>"` listing names.
- The nav badge is `data-test-id="nav-announcements-unread"`, absent entirely
  when the count is zero — following 0002 ruling 7.

### Broadcasts

Both on `Tenancy.topic(tenant, :announcements)` (invariant 6), both after the
transaction commits:

- `{:announcement_posted, id}` — recipients' lists and counters (criterion 5).
- `{:announcement_read, announcement_id}` — a manager watching the read-state
  panel updates (criterion 4).

A subscriber receives its own tenant's traffic only; whether a given
announcement concerns it is re-decided by `get_for_member/2`, never by reading
the payload.

### Approaches

**Audience derived at query time (recommended).** Criterion 4 demands exactly
this — a member deactivated after posting drops out, a member added after
posting appears as unread — so no snapshot satisfies it without a backfill.

**Audience snapshotted at post time** into a `recipients` row per member.
Rejected: contradicts criterion 4 in both directions, and costs a write per
recipient per announcement. It becomes right only if the read-state query
becomes a measured problem at a tenant size we do not have.

**Read counts denormalised onto the announcement row.** Rejected: the
denominator changes when anyone is deactivated, so the stored number is wrong
the moment it is stored.

**Counter in `on_mount` (recommended) vs in each LiveView.** In `on_mount` it
cannot be forgotten by a page added later — the argument decision 0010 made for
the deactivation hook. Cost: one extra query on every mount of every tenant
page.

### Risks

- `list_with_read_state/1` is N+1 by construction if written per announcement.
  It must fetch all acknowledgements for the listed announcements in one query,
  and the active members with their users once.
- The read broadcast fires for every recipient's first view. Bounded by
  audience size per announcement, but a tenant-wide announcement in a large
  business is one message per member to every subscribed socket.
- The counter query runs on every tenant page mount. One indexed tenant-schema
  query; the member's `site_id` is already in the assign, so no `public` round
  trip.
- The `users.name` backfill is a one-way guess for existing rows. Seeds set
  real names; anything already in a developer's database gets its email local
  part.
- Chat and announcements both add `async: false` tenant-schema tests. 0002
  already notes the 30s mark in `.claude/rules/testing.md` may come due; this
  plan pushes it further.

## Steps

1. Public migration adding `users.name` (not null, backfilled from the email
   local part), `name` cast and validated in `Accounts.registration_changeset/3`,
   and `user_fixture` defaulting it so no existing test has to change.
   `priv/repo/seeds.exs` is deliberately left for step 14. **Flagged:** public
   migration. Verify: `mix ecto.migrate` on a populated database, then
   `mix test`.
2. Tenant migration creating `announcements` and
   `announcement_acknowledgements` as specified, timestamped after 0002's
   `20260925120000`. **Flagged:** migration, invariants 1, 8, 9. Verify:
   `mix ecto.reset`, then `psql` showing both tables, the unique `seq` index,
   the composite primary key, the body check constraint and the two
   `public.members` foreign keys; rolled-back inserts proving each constraint
   refuses; one down/up cycle on a seeded tenant.
3. `Announcement` and `Acknowledgement` schemas and changesets, and the
   `NightShift.Announcements` contract — `@moduledoc`, `@spec` and raising
   stubs for all seven functions, no logic. **Flagged:** invariant 5
   (actor-first shape). Verify: compiles warning-free; seven functions raise.
4. *(spec-tester, fresh session, parallel from here)*
   `test/support/fixtures/announcements_fixtures.ex` and context plus LiveView
   tests for criteria 1–7, from the criteria and the web contract alone, with
   the negative cases `.claude/rules/testing.md` requires: staff posting,
   another tenant's member, a deactivated member reading and posting, another
   tenant's announcement id, another tenant's `site_id` as a target.
5. Implement `post_announcement/2`: manager only, body trimmed then 1–2000
   graphemes, `site_id` `nil` or a site of this tenant. **Flagged:** permission
   boundary (criterion 1), invariant 4.
6. Implement `list_for_member/1`, `get_for_member/2` and `unread_count/1`,
   author excluded from the audience (criteria 2, 6). **Flagged:** permission
   boundary — targeting decides what a member may read.
7. Implement `record_views/2`, idempotent through the composite primary key,
   preserving the first `inserted_at` (criterion 3).
8. Implement `list_with_read_state/1` for any manager of the tenant: current
   audience, read count, unread members with names (criterion 4). **Flagged:**
   permission boundary.
9. Both broadcasts and `subscribe/1`, after their transactions commit
   (criteria 4, 5). **Flagged:** invariant 6.
10. `AnnouncementsLive`: the list newest first, views recorded on render, the
    manager compose form with a site picker, and the manager read-state panel
    updating on `{:announcement_read, _}`. Context calls only, no `Repo`, no
    permission decisions.
11. `TenantAuth`: subscribe to the announcements topic, assign the unread
    counter, recompute on both broadcasts. The announcement hook returns
    `{:cont, socket}`. **Flagged:** permission boundary — it runs for every
    tenant page.
12. Layout badge on `nav-announcements`, absent at zero.
13. *(after 0002 wraps)* Seed a tenant-wide and a per-site announcement, and
    real names on seeded users, in `priv/repo/seeds.exs` — the file 0002's step
    11 also edits.
14. *(after 0002 wraps)* `/verify` with output shown; `docs/DECISIONS.md`
    entries for the derived audience, for implicit reads, for `users.name`, and
    for the two read models differing from 0002's; `docs/CHANGELOG.md`.
    Renumber against whatever 0002 took.

## Notes / deviations

- Steps 1–12 touch no file 0002 touches. Steps 13 and 14 do, and wait for it.
- `Members.fetch_active/1`, planned before 0002's shape was known, is dropped.
  `Announcements` carries its own private `acting/1`, matching `Chat`. The
  three copies of the invariant-4 liveness read are a deliberate debt, to be
  collapsed once both plans have landed.
