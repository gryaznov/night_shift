defmodule NightShift.Announcements do
  @moduledoc """
  Announcements, who they reach, and who has seen them.

  An announcement is addressed to a tenant or to one of its sites, and nothing
  records its recipients. The audience is derived on every call from
  `public.members`:

      tenant-wide   every active member of the tenant
      site          every active member whose `site_id` is the announcement's

  minus its author, who neither sees their own announcement nor counts against
  it. That derivation is what makes a member deactivated after publication drop
  out of the figures and a member hired after publication appear in them as not
  yet read.

  Every function that decides something takes the acting member first
  (invariant 5) and re-reads that member before deciding, so a member
  deactivated since the session opened can neither read nor post (invariants 3
  and 4). The tenant is derived from the re-read member's `tenant_id` — never
  from a param, a path or a client event — and reaches Ecto only as
  `NightShift.Tenancy.prefix/1`, which is why another tenant's announcement id
  cannot be found at all rather than merely refused. This is the shape
  `NightShift.Chat` uses.

  Reading is not an act: an announcement is recorded as read when it is put in
  front of its reader, through `record_views/2`. The first time is the recorded
  time and it never changes.

  Nothing here updates or deletes an announcement, and there is no private
  function that would. That absence is the whole of criterion 7 — the database
  still permits it, so no console is stopped.
  """

  import Ecto.Query

  alias NightShift.Accounts.User
  alias NightShift.Announcements.Acknowledgement
  alias NightShift.Announcements.Announcement
  alias NightShift.Members.Member
  alias NightShift.Repo
  alias NightShift.Tenancy
  alias NightShift.Tenants.Tenant

  @typedoc """
  One announcement as a manager sees it: the audience as it currently stands,
  how many of them have seen it, and which of them have not.
  """
  @type read_state :: %{
          announcement: Announcement.t(),
          audience: non_neg_integer(),
          read: non_neg_integer(),
          unread: [Member.t()]
        }

  @doc """
  Publishes an announcement by `actor`.

  `actor` must be an active manager. `attrs` carries `:body` and `:site_id`;
  a `:site_id` of `nil` addresses the whole tenant, and any other value must be
  a site of `actor`'s tenant. The body is trimmed, then must be 1 to
  #{Announcement.max_body()} graphemes.

  Broadcasts `{:announcement_posted, id}` on the tenant's announcements topic
  once the insert has committed, never before: a subscriber that re-read a
  rolled-back announcement would find nothing.

  Returns `{:error, :forbidden}` when `actor` is not an active manager, and a
  changeset for a body or a site the announcement cannot carry. A `:site_id`
  belonging to another tenant is a changeset error, not a crash: the insert runs
  under this tenant's prefix, and `sites` there does not contain it.
  """
  @spec post_announcement(Member.t(), map()) ::
          {:ok, Announcement.t()} | {:error, :forbidden} | {:error, Ecto.Changeset.t()}
  def post_announcement(%Member{} = actor, attrs) when is_map(attrs) do
    with {:ok, member, tenant} <- acting(actor),
         :manager <- member.role do
      case Repo.insert(Announcement.create_changeset(%Announcement{}, attrs, member.id),
             prefix: Tenancy.prefix(tenant)
           ) do
        {:ok, announcement} ->
          broadcast(tenant, {:announcement_posted, announcement.id})
          {:ok, announcement}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      _ -> {:error, :forbidden}
    end
  end

  @doc """
  The announcements addressed to `actor`, newest first.

  Each carries `:read_at` — the time `actor` first saw it, or `nil` — and
  `:author_name`. Reading this records nothing; `record_views/2` does that.

  Returns `{:error, :forbidden}` when `actor` is no longer active.
  """
  @spec list_for_member(Member.t()) :: {:ok, [Announcement.t()]} | {:error, :forbidden}
  def list_for_member(%Member{} = actor) do
    with {:ok, member, tenant} <- acting(actor) do
      announcements =
        member
        |> addressed_to()
        |> with_read_at(member)
        |> order_by([a], desc: a.seq)
        |> Repo.all(prefix: Tenancy.prefix(tenant))
        |> with_author_names()

      {:ok, announcements}
    end
  end

  @doc """
  One announcement addressed to `actor`, by id.

  What a LiveView calls when the topic tells it something was published, so
  that whether an announcement concerns this member stays a decision made here
  and never one made from a broadcast payload.

  Returns `{:error, :forbidden}` for an announcement addressed to another site,
  for one belonging to another tenant, and for an id that does not exist. The
  caller cannot tell those apart.
  """
  @spec get_for_member(Member.t(), Ecto.UUID.t()) ::
          {:ok, Announcement.t()} | {:error, :forbidden}
  def get_for_member(%Member{} = actor, announcement_id) when is_binary(announcement_id) do
    with {:ok, member, tenant} <- acting(actor),
         {:ok, id} <- Ecto.UUID.cast(announcement_id),
         %Announcement{} = announcement <-
           member
           |> addressed_to()
           |> where([a], a.id == ^id)
           |> with_read_at(member)
           |> Repo.one(prefix: Tenancy.prefix(tenant)) do
      [announcement] = with_author_names([announcement])
      {:ok, announcement}
    else
      _ -> {:error, :forbidden}
    end
  end

  @doc """
  Records that `actor` has now seen `announcements`, and returns the
  acknowledgements written.

  Idempotent: an announcement `actor` has already seen is skipped, keeping its
  original time, and an announcement not addressed to `actor` is ignored.
  Announcements the caller did not obtain from `list_for_member/1` are
  therefore harmless.

  Broadcasts `{:announcement_read, id}` for each row actually written, so a
  manager watching the read state sees it move, and so that the broadcast is
  bounded by the size of the audience rather than by page views.

  Returns `{:error, :forbidden}` when `actor` is no longer active.
  """
  @spec record_views(Member.t(), [Announcement.t()]) ::
          {:ok, [Acknowledgement.t()]} | {:error, :forbidden}
  def record_views(%Member{} = actor, announcements) when is_list(announcements) do
    with {:ok, member, tenant} <- acting(actor) do
      ids = for %Announcement{id: id} <- announcements, is_binary(id), do: id
      rows = acknowledge(Tenancy.prefix(tenant), member, ids)
      Enum.each(rows, &broadcast(tenant, {:announcement_read, &1.announcement_id}))
      {:ok, rows}
    end
  end

  @doc """
  How many announcements addressed to `actor` they have not yet seen.

  Their own announcements never count, because an author is not in their own
  audience.

  Returns `{:error, :forbidden}` when `actor` is no longer active.
  """
  @spec unread_count(Member.t()) :: {:ok, non_neg_integer()} | {:error, :forbidden}
  def unread_count(%Member{} = actor) do
    with {:ok, member, tenant} <- acting(actor) do
      count =
        member
        |> addressed_to()
        |> unread_by(member)
        |> Repo.aggregate(:count, prefix: Tenancy.prefix(tenant))

      {:ok, count}
    end
  end

  @doc """
  Every announcement of `actor`'s tenant with its read state, newest first.

  For managers: any active manager of the tenant sees this, not only the author
  of each announcement. Each entry gives the audience as it currently stands,
  how many of them have seen it, and the members who have not, each with the
  user's name preloaded.

  Returns `{:error, :forbidden}` when `actor` is not an active manager.
  """
  @spec list_with_read_state(Member.t()) :: {:ok, [read_state()]} | {:error, :forbidden}
  def list_with_read_state(%Member{} = actor) do
    with {:ok, member, tenant} <- acting(actor),
         :manager <- member.role do
      prefix = Tenancy.prefix(tenant)

      announcements =
        Announcement
        |> order_by([a], desc: a.seq)
        |> Repo.all(prefix: prefix)
        |> with_author_names()

      readers = readers_by_announcement(prefix, Enum.map(announcements, & &1.id))
      members = active_members(tenant)

      {:ok,
       Enum.map(announcements, &read_state(&1, members, Map.get(readers, &1.id, MapSet.new())))}
    else
      _ -> {:error, :forbidden}
    end
  end

  @doc """
  Subscribes the caller to `actor`'s tenant's announcements topic.

  Authorizes first, so a caller cannot subscribe to a tenant it may not act in,
  and takes no topic or tenant of its own — both come from the re-read member.
  """
  @spec subscribe(Member.t()) :: :ok | {:error, :forbidden}
  def subscribe(%Member{} = actor) do
    with {:ok, _member, tenant} <- acting(actor) do
      Phoenix.PubSub.subscribe(NightShift.PubSub, Tenancy.topic(tenant, :announcements))
    end
  end

  # Every broadcast carries the tenant in its topic (invariant 6), and the
  # tenant comes from the re-read member, so nothing here can reach another
  # tenant's subscribers.
  defp broadcast(%Tenant{} = tenant, message) do
    Phoenix.PubSub.broadcast(NightShift.PubSub, Tenancy.topic(tenant, :announcements), message)
  end

  # Targeting, and the whole of it: an announcement with no site addresses the
  # tenant, one with a site addresses that site, and an author is never in their
  # own audience. Nothing is stored per recipient, so a member deactivated or
  # hired since publication is counted as they stand now.
  defp addressed_to(%Member{} = member) do
    from a in Announcement,
      where: a.author_member_id != ^member.id,
      where: is_nil(a.site_id) or a.site_id == ^member.site_id
  end

  defp with_read_at(query, %Member{} = member) do
    from a in query,
      left_join: k in Acknowledgement,
      on: k.announcement_id == a.id and k.member_id == ^member.id,
      select: %{a | read_at: k.inserted_at}
  end

  defp unread_by(query, %Member{} = member) do
    from a in query,
      left_join: k in Acknowledgement,
      on: k.announcement_id == a.id and k.member_id == ^member.id,
      where: is_nil(k.announcement_id)
  end

  # Re-read from the tenant's own schema rather than trusting the structs the
  # caller passed: an id that is not addressed to this member is dropped here,
  # so a stale or forged list writes nothing.
  defp acknowledge(_prefix, _member, []), do: []

  defp acknowledge(prefix, %Member{} = member, ids) do
    addressed =
      member
      |> addressed_to()
      |> unread_by(member)
      |> where([a], a.id in ^ids)
      |> select([a], a.id)
      |> Repo.all(prefix: prefix)

    entries =
      Enum.map(addressed, fn id ->
        %{announcement_id: id, member_id: member.id, inserted_at: DateTime.utc_now(:second)}
      end)

    case entries do
      [] ->
        []

      entries ->
        # `on_conflict: :nothing` makes two concurrent first sightings safe, and
        # `returning` then yields only the rows this call actually wrote — so the
        # read broadcast step 9 sends is one per member per announcement, ever.
        {_count, rows} =
          Repo.insert_all(Acknowledgement, entries,
            prefix: prefix,
            on_conflict: :nothing,
            returning: [:announcement_id, :member_id, :inserted_at]
          )

        rows
    end
  end

  defp readers_by_announcement(_prefix, []), do: %{}

  defp readers_by_announcement(prefix, ids) do
    Acknowledgement
    |> where([k], k.announcement_id in ^ids)
    |> select([k], {k.announcement_id, k.member_id})
    |> Repo.all(prefix: prefix)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, member_ids} -> {id, MapSet.new(member_ids)} end)
  end

  # `members` is in `public`, so this filters on an explicitly passed
  # `tenant_id` rather than a prefix — the form invariant 2 requires.
  defp active_members(%Tenant{} = tenant) do
    Member
    |> where([m], m.tenant_id == ^tenant.id and m.active)
    |> preload(:user)
    |> Repo.all()
  end

  defp read_state(%Announcement{} = announcement, members, readers) do
    audience =
      members
      |> Enum.filter(fn m ->
        m.id != announcement.author_member_id and
          (is_nil(announcement.site_id) or m.site_id == announcement.site_id)
      end)
      |> Enum.sort_by(& &1.user.email)

    {read, unread} = Enum.split_with(audience, &MapSet.member?(readers, &1.id))

    %{
      announcement: announcement,
      audience: length(audience),
      read: length(read),
      unread: unread
    }
  end

  # One unprefixed query for every author on the page. An `Ecto` association
  # could not do this: `author_member_id` names a row in `public.members`, and a
  # preload would inherit the tenant prefix and look for `members` in the tenant
  # schema.
  defp with_author_names([]), do: []

  defp with_author_names(announcements) do
    ids = announcements |> Enum.map(& &1.author_member_id) |> Enum.uniq()

    names =
      from(m in Member,
        join: u in User,
        on: u.id == m.user_id,
        where: m.id in ^ids,
        select: {m.id, u.email}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(announcements, &%{&1 | author_name: Map.get(names, &1.author_member_id)})
  end

  # Invariant 3 fixes identity at the session boundary; it does not fix
  # liveness. Invariant 4 stops a member deactivated since the session opened
  # from reading or posting, which a stale `active` on a socket assign cannot
  # honour, so every entry point re-reads the member by its own id. The tenant
  # comes from that re-read record, never from an argument, so no caller can
  # pair a member with someone else's tenant.
  defp acting(%Member{id: id}) do
    case Repo.get(Member, id) do
      %Member{active: true} = member -> {:ok, member, Repo.get!(Tenant, member.tenant_id)}
      _ -> {:error, :forbidden}
    end
  end
end
