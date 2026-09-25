defmodule NightShift.Tenants.Tenant do
  @moduledoc """
  A company.

  `name` is the business name. `schema` is the Postgres schema holding that
  business's tenant data, and is the value every tenant query uses as its
  prefix — see `NightShift.Tenancy`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # A schema name becomes a Postgres identifier in DDL, so the accepted shape is
  # narrow on purpose: lowercase, no quoting required, 63 bytes at most.
  @schema_format ~r/^[a-z][a-z0-9_]*$/
  @schema_max_length 63

  @type t :: %__MODULE__{}

  schema "tenants" do
    field :name, :string
    field :schema, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a tenant.

  Rejects a `schema` that Postgres would need quoted, that is too long to be an
  identifier, or that Triplex reserves (`public`, `information_schema`, `pg_*`).
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :schema])
    |> validate_required([:name, :schema])
    |> validate_length(:name, max: 160)
    |> validate_length(:schema, max: @schema_max_length)
    |> validate_format(:schema, @schema_format)
    |> validate_not_reserved(:schema)
    |> unique_constraint(:schema)
  end

  defp validate_not_reserved(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if Triplex.reserved_tenant?(value), do: [{field, "is reserved"}], else: []
    end)
  end
end
