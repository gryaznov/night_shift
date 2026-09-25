defmodule NightShift.Chat.Group do
  @moduledoc """
  One conversation: either a site's group (`team` is `nil`) or one team at that
  site.

  Lives in the tenant schema, so every query for a group carries
  `prefix: NightShift.Tenancy.prefix(tenant)`.

  Membership is not stored here and never will be (invariant 7). A member's two
  groups are the rows matching their `site_id` and their `team`, read from
  `public.members`, so a group has no row to fall out of step with employment.

  `:site` is `NightShift.Members.Site` — the site that owns the group — because
  the display name is the site's name, optionally qualified by the team.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NightShift.Members.Member
  alias NightShift.Members.Site

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "groups" do
    belongs_to :site, Site

    field :team, Ecto.Enum, values: Member.teams()

    # Filled by `NightShift.Chat.list_groups/1`; never read from the database.
    field :unread_count, :integer, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a group.

  `site_id` and `team` are arguments rather than castable fields: groups are
  created by `NightShift.Chat.create_groups_for_site/2` from a site this tenant
  owns, never from anything a client sent.
  """
  @spec create_changeset(t(), Ecto.UUID.t(), Member.team() | nil) :: Ecto.Changeset.t()
  def create_changeset(group, site_id, team) do
    group
    |> change(%{site_id: site_id, team: team})
    |> validate_required([:site_id])
    |> unique_constraint([:site_id, :team],
      message: "already has a group for this team"
    )
    |> unique_constraint(:site_id,
      name: :groups_site_group_unique,
      message: "already has a site group"
    )
    |> foreign_key_constraint(:site_id)
    |> check_constraint(:team, name: :team_is_known)
  end

  @doc """
  What the member sees in their group list: the site's name, and the team when
  the group is a team group.

  Requires `:site` to be loaded.
  """
  @spec display_name(t()) :: String.t()
  def display_name(%__MODULE__{team: nil, site: %Site{name: name}}), do: name

  def display_name(%__MODULE__{team: team, site: %Site{name: name}}),
    do: "#{name} · #{team_name(team)}"

  defp team_name(:front_of_house), do: "Front of house"
  defp team_name(:kitchen), do: "Kitchen"
  defp team_name(:bar), do: "Bar"
end
