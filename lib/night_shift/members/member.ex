defmodule NightShift.Members.Member do
  @moduledoc """
  One person's employment at one business: their site, team and role there.

  Lives in `public`, not in the tenant schema, so that resolving whether a user
  may act in a tenant is one indexed query rather than a scan of every tenant
  schema. A user may hold a member record in several tenants at once, with a
  different role in each.

  `site_id` names a row in that tenant's own `sites` table, so it cannot be a
  foreign key and carries no `belongs_to`. `NightShift.Members` is what keeps it
  pointing at a site of the right tenant.
  """

  use Ecto.Schema

  alias NightShift.Accounts.User
  alias NightShift.Tenants.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @teams [:kitchen, :front_of_house, :bar]
  @roles [:manager, :staff]

  @type t :: %__MODULE__{}
  @type team :: :kitchen | :front_of_house | :bar
  @type role :: :manager | :staff

  schema "members" do
    belongs_to :user, User
    belongs_to :tenant, Tenant

    field :site_id, :binary_id
    field :team, Ecto.Enum, values: @teams
    field :role, Ecto.Enum, values: @roles
    field :active, :boolean, default: true
    field :deactivated_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "The teams a member can belong to."
  @spec teams() :: [team()]
  def teams, do: @teams

  @doc "The roles a member can hold."
  @spec roles() :: [role()]
  def roles, do: @roles
end
