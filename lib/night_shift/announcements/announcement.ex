defmodule NightShift.Announcements.Announcement do
  @moduledoc """
  One announcement. Lives in the tenant schema, so every query for one carries
  `prefix: NightShift.Tenancy.prefix(tenant)`.

  `site_id` is the whole of its targeting: `nil` addresses the tenant, a site id
  addresses that site. Nothing records who received it — the audience is derived
  from `public.members` on every read, so a member deactivated or hired after
  publication is counted as they stand now.

  `author_member_id` is a plain `:binary_id` with no `belongs_to`, although the
  database has a real foreign key into `public.members`. An association across
  schemas would let a preload inherit the tenant prefix and look for `members`
  inside the tenant schema. `site_id` does carry one, because `sites` is in this
  same schema.

  There is no `updated_at` and no changeset that updates anything: an
  announcement is never edited after publication.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NightShift.Members.Site

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_body 2000

  @type t :: %__MODULE__{}

  schema "announcements" do
    belongs_to :site, Site

    field :author_member_id, :binary_id
    field :body, :string

    # Ordering. `:utc_datetime` is second-granular, so two announcements
    # published in one second could not be ordered by `inserted_at`.
    field :seq, :integer, read_after_writes: true

    # Filled by the context, per reader and per query; never stored.
    field :read_at, :utc_datetime, virtual: true
    field :author_name, :string, virtual: true

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Changeset for a new announcement.

  `author_member_id` is an argument rather than a castable field, so an author
  can never arrive from a param, a path or a client event — the shape
  `NightShift.Members.Member.create_changeset/3` uses for `tenant_id`.

  The body is trimmed before it is measured, so a body of nothing but
  whitespace is empty and rejected. Length is counted in graphemes, as 0002
  counts a message.
  """
  @spec create_changeset(t(), map(), Ecto.UUID.t()) :: Ecto.Changeset.t()
  def create_changeset(announcement, attrs, author_member_id) do
    announcement
    |> cast(attrs, [:body, :site_id])
    |> put_change(:author_member_id, author_member_id)
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body, :author_member_id])
    |> validate_length(:body, min: 1, max: @max_body, count: :graphemes)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:author_member_id)
    |> check_constraint(:body, name: :body_length)
  end

  @doc "The longest body an announcement may carry."
  @spec max_body() :: pos_integer()
  def max_body, do: @max_body
end
