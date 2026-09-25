# Changelog

Newest first. One entry per closed plan.

## 0003 — Announcements with acknowledgement

A manager can now publish an announcement to a whole business or to one of its
sites, and see who has read it. Announcements are separate from chat and cannot
be replied to. Staff cannot publish. Nothing about an announcement can be
edited or deleted afterwards, by anyone, including its author.

A recipient's announcements are listed newest first, and one counts as read
when it appears on their page — there is nothing to click. The first time is
the recorded time and it never changes. An announcement published while someone
has the page open appears there without a reload, and an unread count rides on
every page of a business, rising as announcements arrive and falling as they are
read.

The manager's view of who has read is worked out fresh each time, so it follows
the staff list rather than the past: someone deactivated after publication drops
out of the figures, and someone hired after it appears as not yet read. An
author is never in their own audience. Users now carry a name, which is what
that list shows.

There is no scheduling, expiry, reminder or escalation, no targeting by team or
by individual, and no push, email or SMS delivery.

## 0002 — Chat: site and team groups

Every site now has a group, and every team at that site has one. Nobody
maintains them: a member is in their site's group and their own team's group
because of their member record, so a new hire is in the right two groups on
day one, someone moved to another site is moved with them, and a deactivated
member is out of both immediately. Messages are text, 1 to 2000 characters,
and appear for everyone else looking at the group without a reload. Each group
carries an unread count that clears when you open it, counting from a member's
first sight of the group rather than from the beginning of its history.

A group shows its newest 200 messages and no further back; nothing is deleted,
the older messages are simply unreachable. There are still no direct messages,
ad-hoc groups, attachments, reactions, replies, editing or push notifications.
Managers can move a member between sites and teams through
`NightShift.Members.update_assignment/3`, which has no screen yet.

Someone moved while they have a group open keeps that page until the next
message arrives in it; at that point they are sent back to their group list,
because they are no longer in the group they were reading. An unread count
never goes backwards, so reading on your phone cannot make a group look unread
again on the desk.

## 0001 — Foundation: tenants, members, access

A business is now a tenant with its own Postgres schema, and a person reaches
it only through a member record naming their site, team and role. Signing in
puts you in your own business's workspace and nowhere else: without an active
membership you get a no-access page and no tenant data, and a manager
deactivating someone ends their access on the spot, including any page they
already have open. Managers can only deactivate inside their own business, and
never the last remaining manager. Nothing is ever deleted — deactivation is
recorded, not erased.

Chat and announcements have routes and a nav entry but no behaviour yet. There
is no sign-up, invitation, password reset or member-creation screen; members
come from `priv/repo/seeds.exs`, which sets up two businesses with two sites
each and prints their sign-in credentials. Generated registration,
password-reset and email-confirmation pages were removed rather than left
reachable.
