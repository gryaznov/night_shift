# Changelog

Newest first. One entry per closed plan.

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
