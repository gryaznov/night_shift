defmodule NightShift.Tenants do
  @moduledoc """
  Companies and their Postgres schemas.

  A tenant is a hospitality business. Creating one writes its row in `public`
  and provisions the schema that holds its data; no other code calls Triplex.
  """

  import Ecto.Query, only: [order_by: 2]

  alias NightShift.Repo
  alias NightShift.Tenancy
  alias NightShift.Tenants.Tenant

  @doc """
  Creates a tenant: its row, its Postgres schema, and its tenant migrations.

  Returns `{:error, changeset}` for invalid attributes. A failure to provision
  the schema or run its migrations raises — it is an infrastructure fault, not
  something a caller can correct — and leaves no tenant row and no schema
  behind.
  """
  @spec create_tenant(map()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def create_tenant(attrs) when is_map(attrs) do
    with {:ok, tenant} <- %Tenant{} |> Tenant.changeset(attrs) |> Repo.insert() do
      provision!(tenant)
    end
  end

  @doc """
  The tenant owning the Postgres schema `schema`, or `nil`.
  """
  @spec get_tenant_by_schema(String.t()) :: Tenant.t() | nil
  def get_tenant_by_schema(schema) when is_binary(schema), do: Repo.get_by(Tenant, schema: schema)

  @doc """
  Every tenant, from the `tenants` table.

  Not `Triplex.all/0`, which reports physical Postgres schemas and is never a
  basis for authorization.
  """
  @spec list_tenants() :: [Tenant.t()]
  def list_tenants, do: Tenant |> order_by(asc: :name) |> Repo.all()

  # Triplex drops the schema itself when a tenant migration fails, so the row is
  # all that is left to undo.
  defp provision!(%Tenant{} = tenant) do
    case Triplex.create(Tenancy.prefix(tenant)) do
      {:ok, _schema} ->
        {:ok, tenant}

      {:error, reason} ->
        Repo.delete!(tenant)
        raise "could not provision schema #{inspect(Tenancy.prefix(tenant))}: #{reason}"
    end
  end
end
