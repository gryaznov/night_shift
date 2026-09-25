defmodule NightShift.Chat do
  @moduledoc """
  Site and team groups, their messages, and how far each member has read.

  Nobody manages membership. A member's groups are derived, on every call, from
  the `site_id` and `team` on their member record (invariant 7):

      site group   the group of their site, with no team
      team group   the group of their site and their team

  Every function that decides something takes the acting member first
  (invariant 5) and re-reads that member before deciding, so a member
  deactivated or moved since the session opened cannot read or post
  (invariants 3 and 4). The tenant is derived from the re-read member's
  `tenant_id` — never from a param, a path or a client event — and reaches Ecto
  only as `NightShift.Tenancy.prefix/1`, which is why a group id belonging to
  another tenant cannot be found at all rather than merely refused.

  `{:error, :forbidden}` is returned for a group that is not one of the acting
  member's two, for a group of another tenant, and for a group id that does not
  exist. The caller cannot tell those apart, so nothing here reveals whether an
  id is real.
  """

  import Ecto.Query

  alias NightShift.Chat.Group
  alias NightShift.Chat.Message
  alias NightShift.Members.Member
  alias NightShift.Members.Site
  alias NightShift.Repo
  alias NightShift.Tenancy
  alias NightShift.Tenants.Tenant

  @doc """
  Creates the groups a new site needs: its site group and one group per team.

  Takes a tenant rather than an acting member, for the reason
  `NightShift.Members.create_site/2` does — nothing in the product creates a
  site, so there is no actor whose permission could be decided.

  Idempotent: a site that already has its groups keeps them, and the existing
  rows are returned. `NightShift.Members.create_site/2` calls this, so a caller
  that also calls it directly must not be punished for it, and two concurrent
  calls cannot produce a second site group — the unique indexes decide, not the
  read that preceded them.
  """
  @spec create_groups_for_site(Tenant.t(), Site.t()) :: {:ok, [Group.t()]}
  def create_groups_for_site(%Tenant{} = tenant, %Site{} = site) do
    prefix = Tenancy.prefix(tenant)

    for team <- [nil | Member.teams()] do
      %Group{}
      |> Group.create_changeset(site.id, team)
      |> Repo.insert(prefix: prefix, on_conflict: :nothing)
    end

    groups =
      Group
      |> where(site_id: ^site.id)
      |> Repo.all(prefix: prefix)
      |> sort_site_group_first()

    {:ok, groups}
  end

  @doc """
  The acting member's two groups, site group first, each with `:site` loaded and
  `:unread_count` filled.

  A member's first sight of a group seeds their read cursor to that group's
  current newest message, so inherited history counts as read.
  """
  @spec list_groups(Member.t()) :: {:ok, [Group.t()]} | {:error, :forbidden}
  def list_groups(%Member{} = actor) do
    with {:ok, member, tenant} <- acting(actor) do
      groups =
        Group
        |> where([g], g.site_id == ^member.site_id)
        |> where([g], is_nil(g.team) or g.team == ^member.team)
        |> preload(:site)
        |> Repo.all(prefix: Tenancy.prefix(tenant))
        |> sort_site_group_first()

      {:ok, groups}
    else
      :error -> {:error, :forbidden}
    end
  end

  @doc """
  One of the acting member's groups by id, with `:site` loaded.
  """
  @spec get_group(Member.t(), Ecto.UUID.t()) :: {:ok, Group.t()} | {:error, :forbidden}
  def get_group(%Member{} = actor, group_id) when is_binary(group_id) do
    with {:ok, member, tenant} <- acting(actor),
         {:ok, group} <- fetch_group(member, tenant, group_id) do
      {:ok, Repo.preload(group, :site, prefix: Tenancy.prefix(tenant))}
    else
      _ -> {:error, :forbidden}
    end
  end

  @doc """
  The newest 200 messages of `group`, oldest first, each with `:author_email`
  filled.

  Older messages are retained and unreachable: 0002 ships no way to page back.
  """
  @spec list_messages(Member.t(), Group.t()) :: {:ok, [Message.t()]} | {:error, :forbidden}
  def list_messages(%Member{} = _actor, %Group{} = _group) do
    raise "not implemented"
  end

  @doc """
  Posts a message to `group` as the acting member, then broadcasts it on that
  group's topic so every other member viewing the group sees it without
  reloading.

  The broadcast happens after the insert commits.
  """
  @spec post_message(Member.t(), Group.t(), map()) ::
          {:ok, Message.t()} | {:error, :forbidden} | {:error, Ecto.Changeset.t()}
  def post_message(%Member{} = _actor, %Group{} = _group, attrs) when is_map(attrs) do
    raise "not implemented"
  end

  @doc """
  Marks `group` read for the acting member, up to its newest message.
  """
  @spec mark_read(Member.t(), Group.t()) :: :ok | {:error, :forbidden}
  def mark_read(%Member{} = _actor, %Group{} = _group) do
    raise "not implemented"
  end

  @doc """
  How many messages in `group` the acting member has not seen.

  Their own messages never count.
  """
  @spec unread_count(Member.t(), Group.t()) ::
          {:ok, non_neg_integer()} | {:error, :forbidden}
  def unread_count(%Member{} = _actor, %Group{} = _group) do
    raise "not implemented"
  end

  @doc """
  Subscribes the caller to `group`'s topic, if the acting member belongs to it.

  Authorization lives here rather than in the LiveView so that a view cannot
  subscribe to a group it may not read.
  """
  @spec subscribe(Member.t(), Group.t()) :: :ok | {:error, :forbidden}
  def subscribe(%Member{} = _actor, %Group{} = _group) do
    raise "not implemented"
  end

  # The acting member is re-read before every decision, and the tenant comes from
  # the row that read returns. Invariant 3 fixes identity at the session boundary
  # and forbids re-deriving it; it does not make a stale `active`, `site_id` or
  # `team` authoritative, which invariants 4 and 7 both forbid.
  defp acting(%Member{id: id}) do
    case Repo.get(Member, id) do
      %Member{active: true} = member -> {:ok, member, Repo.get!(Tenant, member.tenant_id)}
      _ -> :error
    end
  end

  # A group is always re-read by id under the acting member's own prefix, so
  # another tenant's group is not refused — it is not there to find. The caller's
  # struct is never trusted: it may be stale, or from anywhere.
  defp fetch_group(%Member{} = member, %Tenant{} = tenant, group_id) do
    with {:ok, id} <- Ecto.UUID.cast(group_id),
         %Group{} = group <- Repo.get(Group, id, prefix: Tenancy.prefix(tenant)),
         true <- member_of?(member, group) do
      {:ok, group}
    else
      _ -> :error
    end
  end

  # The whole of group membership (invariant 7). Nothing is stored, nothing is
  # managed: a member is in their site's group and in their own team's group.
  defp member_of?(%Member{} = member, %Group{} = group) do
    group.site_id == member.site_id and (is_nil(group.team) or group.team == member.team)
  end

  defp sort_site_group_first(groups) do
    Enum.sort_by(groups, fn
      %Group{team: nil} -> {0, nil}
      %Group{team: team} -> {1, Enum.find_index(Member.teams(), &(&1 == team))}
    end)
  end
end
