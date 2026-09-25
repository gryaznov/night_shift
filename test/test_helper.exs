# Tenant schemas must be committed before the sandbox takes the connection, so
# this runs before `ExUnit.start/0` and `Sandbox.mode/2`. See
# `NightShift.TenantSetup`.
:ok = NightShift.TenantSetup.run!()

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(NightShift.Repo, :manual)
