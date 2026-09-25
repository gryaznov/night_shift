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

  import Ecto.Changeset

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

  @doc """
  Changeset for a new member.

  `tenant_id` is an argument rather than a castable field: a member's tenant can
  then never arrive from a param, a path or a client event.

  Requires a site, a team and a role, so a member without all three cannot be
  written.
  """
  @spec create_changeset(t(), map(), Ecto.UUID.t()) :: Ecto.Changeset.t()
  def create_changeset(member, attrs, tenant_id) do
    member
    |> cast(attrs, [:user_id, :site_id, :team, :role])
    |> put_change(:tenant_id, tenant_id)
    |> validate_required([:user_id, :tenant_id, :site_id, :team, :role])
    |> unique_constraint([:user_id, :tenant_id],
      message: "already has a member record in this tenant"
    )
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tenant_id)
    |> check_constraint(:team, name: :team_is_known)
    |> check_constraint(:role, name: :role_is_known)
  end

  @doc """
  Changeset moving a member to another site or team.

  Casts `:site_id` and `:team` and nothing else, so a move can never change a
  role, a tenant or a user. Both remain required: a member without a site or a
  team has no groups, which criterion 1 forbids. Passing only one of them keeps
  the other as it is.
  """
  @spec assignment_changeset(t(), map()) :: Ecto.Changeset.t()
  def assignment_changeset(member, attrs) do
    member
    |> cast(attrs, [:site_id, :team])
    |> validate_required([:site_id, :team])
    |> check_constraint(:team, name: :team_is_known)
  end

  @doc """
  Changeset ending a member's access. Keeps the record; nothing is deleted.
  """
  @spec deactivation_changeset(t()) :: Ecto.Changeset.t()
  def deactivation_changeset(member) do
    change(member, active: false, deactivated_at: DateTime.utc_now(:second))
  end

  @doc "The teams a member can belong to."
  @spec teams() :: [team()]
  def teams, do: @teams

  @doc "The roles a member can hold."
  @spec roles() :: [role()]
  def roles, do: @roles
end
