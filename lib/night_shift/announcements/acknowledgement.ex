defmodule NightShift.Announcements.Acknowledgement do
  @moduledoc """
  One member's record of having seen one announcement. Lives in the tenant
  schema.

  The primary key is `(announcement_id, member_id)`, which is what makes a
  second sighting a no-op rather than a second row with a later time: the first
  read is the recorded one and it is never overwritten. `group_reads` in 0002 is
  keyed the same way.

  `member_id` carries no `belongs_to`, for the reason
  `NightShift.Announcements.Announcement` records: the row it names is in
  `public`, and an association would inherit the tenant prefix.

  There is no `updated_at`. A read happens once.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NightShift.Announcements.Announcement

  @primary_key false
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "announcement_acknowledgements" do
    belongs_to :announcement, Announcement, primary_key: true
    field :member_id, :binary_id, primary_key: true
    field :inserted_at, :utc_datetime
  end

  @doc """
  Changeset for a first sighting.

  Both ids are arguments rather than castable fields: neither the reader nor
  what they read may arrive from a param or a client event.
  """
  @spec create_changeset(t(), Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) :: Ecto.Changeset.t()
  def create_changeset(acknowledgement, announcement_id, member_id, read_at) do
    acknowledgement
    |> change(%{
      announcement_id: announcement_id,
      member_id: member_id,
      inserted_at: DateTime.truncate(read_at, :second)
    })
    |> unique_constraint([:announcement_id, :member_id],
      name: :announcement_acknowledgements_pkey,
      message: "has already been read"
    )
    |> foreign_key_constraint(:announcement_id)
    |> foreign_key_constraint(:member_id)
  end
end
