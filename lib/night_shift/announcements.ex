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

  alias NightShift.Announcements.Acknowledgement
  alias NightShift.Announcements.Announcement
  alias NightShift.Members.Member

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
  once the insert has committed.

  Returns `{:error, :forbidden}` when `actor` is not an active manager, and a
  changeset for a body or a site the announcement cannot carry.
  """
  @spec post_announcement(Member.t(), map()) ::
          {:ok, Announcement.t()} | {:error, :forbidden} | {:error, Ecto.Changeset.t()}
  def post_announcement(%Member{} = _actor, attrs) when is_map(attrs) do
    raise "not implemented"
  end

  @doc """
  The announcements addressed to `actor`, newest first.

  Each carries `:read_at` — the time `actor` first saw it, or `nil` — and
  `:author_name`. Reading this records nothing; `record_views/2` does that.

  Returns `{:error, :forbidden}` when `actor` is no longer active.
  """
  @spec list_for_member(Member.t()) :: {:ok, [Announcement.t()]} | {:error, :forbidden}
  def list_for_member(%Member{} = _actor) do
    raise "not implemented"
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
  def get_for_member(%Member{} = _actor, announcement_id) when is_binary(announcement_id) do
    raise "not implemented"
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
  def record_views(%Member{} = _actor, announcements) when is_list(announcements) do
    raise "not implemented"
  end

  @doc """
  How many announcements addressed to `actor` they have not yet seen.

  Their own announcements never count, because an author is not in their own
  audience.

  Returns `{:error, :forbidden}` when `actor` is no longer active.
  """
  @spec unread_count(Member.t()) :: {:ok, non_neg_integer()} | {:error, :forbidden}
  def unread_count(%Member{} = _actor) do
    raise "not implemented"
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
  def list_with_read_state(%Member{} = _actor) do
    raise "not implemented"
  end

  @doc """
  Subscribes the caller to `actor`'s tenant's announcements topic.

  Authorizes first, so a caller cannot subscribe to a tenant it may not act in,
  and takes no topic or tenant of its own — both come from the re-read member.
  """
  @spec subscribe(Member.t()) :: :ok | {:error, :forbidden}
  def subscribe(%Member{} = _actor) do
    raise "not implemented"
  end
end
