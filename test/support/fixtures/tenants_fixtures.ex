defmodule NightShift.TenantsFixtures do
  @moduledoc """
  Test helpers for tenants.

  A tenant's Postgres schema is DDL, which the sandbox would roll back, so
  tenants are not created per test: `test/test_helper.exs` provisions two before
  the suite starts and these helpers hand them out.
  """

  alias NightShift.Tenants
  alias NightShift.TenantSetup

  @doc """
  One of the two tenants the suite is run against.

  Use `:two` for the other side of an isolation test.
  """
  def tenant_fixture(which \\ :one) do
    schema = TenantSetup.schema(which)

    Tenants.get_tenant_by_schema(schema) ||
      raise "test tenant #{inspect(schema)} is missing; run `mix test` so test_helper.exs provisions it"
  end
end
