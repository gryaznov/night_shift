defmodule NightShift.Chat.GroupRead do
  @moduledoc """
  How far one member has read in one group: the `seq` of the newest message they
  have seen.

  Lives in the tenant schema, keyed by `(group_id, member_id)`. As with
  `NightShift.Chat.Message`, `member_id` carries a database foreign key into
  `public.members` but no `belongs_to`.

  There is no default cursor. A member's first sight of a group writes the
  group's current maximum `seq`, so the history they inherit counts as read; a
  default of 0 would make a missing row read as "the whole history is unread".
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NightShift.Chat.Group

  @primary_key false
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "group_reads" do
    belongs_to :group, Group, primary_key: true

    field :member_id, :binary_id, primary_key: true
    field :last_read_seq, :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a member's cursor in a group.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(group_read, attrs) do
    group_read
    |> cast(attrs, [:group_id, :member_id, :last_read_seq])
    |> validate_required([:group_id, :member_id, :last_read_seq])
    |> validate_number(:last_read_seq, greater_than_or_equal_to: 0)
  end
end
