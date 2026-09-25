defmodule NightShift.Members.Site do
  @moduledoc """
  One location of a business. Lives in the tenant schema, so every query for a
  site carries `prefix: NightShift.Tenancy.prefix(tenant)`.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "sites" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end
end
