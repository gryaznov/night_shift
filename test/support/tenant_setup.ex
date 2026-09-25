defmodule NightShift.TenantSetup do
  @moduledoc """
  Provisions the tenants the suite runs against.

  Tenant schemas are DDL, which the sandbox would roll back, so they cannot be
  created per test. `test/test_helper.exs` calls `run!/0` once, before
  `ExUnit.start/0` and before the sandbox takes the connection.

  The tenants persist between runs. Migrating them unconditionally is a no-op
  when nothing is pending, which is what lets a tenant migration added later be
  picked up without dropping the test database.
  """

  alias NightShift.Tenancy
  alias NightShift.Tenants
  alias NightShift.Tenants.Tenant

  @tenants %{
    one: %{name: "Test Tenant One", schema: "tenant_one"},
    two: %{name: "Test Tenant Two", schema: "tenant_two"}
  }

  @doc "The Postgres schema name of the given test tenant."
  @spec schema(:one | :two) :: String.t()
  def schema(which), do: @tenants |> Map.fetch!(which) |> Map.fetch!(:schema)

  @doc """
  Creates any missing test tenant, migrates all of them, and raises unless every
  schema is present afterwards.
  """
  @spec run!() :: :ok
  def run! do
    for {_which, attrs} <- @tenants do
      attrs |> find_or_create!() |> migrate!()
    end

    verify!()
  end

  defp find_or_create!(attrs) do
    case Tenants.get_tenant_by_schema(attrs.schema) do
      nil ->
        {:ok, tenant} = Tenants.create_tenant(attrs)
        tenant

      %Tenant{} = tenant ->
        tenant
    end
  end

  defp migrate!(tenant) do
    {:ok, _versions} = Triplex.migrate(Tenancy.prefix(tenant))
    tenant
  end

  defp verify! do
    provisioned = Triplex.all()
    expected = Enum.map(Map.values(@tenants), & &1.schema)

    case Enum.reject(expected, &(&1 in provisioned)) do
      [] ->
        :ok

      missing ->
        raise """
        test tenants have no Postgres schema: #{inspect(missing)}

        Provisioned: #{inspect(provisioned)}
        """
    end
  end
end
