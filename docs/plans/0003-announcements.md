# 0003 — Announcements with acknowledgement

Status: draft
Brief: none

## Intent

The important operational information might get buried in a chat between tons of regular memders' messages (e.g. "hi all!", "check this mem out", etc.), and a manager has no way to know who actually saw it.

Announcements are separate from chat, cannot be replied to, and require each recipient to mark them as "read". The manager sees who has not.

## Acceptance criteria

1. A manager can post an announcement to the whole tenant or to one site. A staff member cannot post announcements.
2. A member sees announcements targeted at them, newest first.
3. A recipient can "read" an announcement once. The next seeing, reading if the announcement changes nothing. The time of that initial read is recorded.
4. A manager sees, for each announcement, how many of its current audience have read it, and the names of those who have not. A member deactivated after posting is not counted; a member added after posting is counted as not yet read.
5. A new announcement appears for recipients viewing the announcements page instantly, without reloading.
6. A member sees how many announcements they have not read, from any page (an integer counter).
7. After the publication, an announcement cannot be edited, updated, or deleted by anyone, including its author.

## Out of scope

- Replies, comments, reactions.
- Scheduling, expiry, reminders, escalation.
- Targeting by team or by individual.
- Push, email or SMS delivery.
