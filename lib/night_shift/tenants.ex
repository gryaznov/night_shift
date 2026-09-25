defmodule NightShift.Tenants do
  @moduledoc """
  Companies and their Postgres schemas.

  A tenant is a hospitality business. Creating one writes its row in `public`
  and provisions the schema that holds its data; no other code calls Triplex.
  """

  alias NightShift.Tenants.Tenant

  @doc """
  Creates a tenant: its row, its Postgres schema, and its tenant migrations.

  Returns `{:error, changeset}` for invalid attributes. A failure to provision
  the schema or run its migrations raises — it is an infrastructure fault, not
  something a caller can correct — and leaves no tenant row and no schema
  behind.
  """
  @spec create_tenant(map()) :: {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def create_tenant(attrs) when is_map(attrs), do: raise("not implemented")

  @doc """
  The tenant owning the Postgres schema `schema`, or `nil`.
  """
  @spec get_tenant_by_schema(String.t()) :: Tenant.t() | nil
  def get_tenant_by_schema(schema) when is_binary(schema), do: raise("not implemented")

  @doc """
  Every tenant, from the `tenants` table.

  Not `Triplex.all/0`, which reports physical Postgres schemas and is never a
  basis for authorization.
  """
  @spec list_tenants() :: [Tenant.t()]
  def list_tenants, do: raise("not implemented")
end
