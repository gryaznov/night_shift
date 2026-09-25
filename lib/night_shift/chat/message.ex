defmodule NightShift.Chat.Message do
  @moduledoc """
  One posted message. Lives in the tenant schema; never deleted (invariant 8).

  `member_id` names a row in `public.members`. The database has a real foreign
  key for it, but this schema deliberately has no `belongs_to`: an association
  across schemas would let a preload inherit this query's tenant prefix and look
  for `members` in the wrong place. The author's email is filled into
  `:author_email` by `NightShift.Chat` with a second, unprefixed query.

  `seq` is assigned by a `bigserial` in the tenant schema and read back after
  insert. It is the unread cursor: `:utc_datetime` is second-granular, so two
  messages posted in the same second could not be ordered by time.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NightShift.Chat.Group

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_length 2000

  @type t :: %__MODULE__{}

  schema "messages" do
    belongs_to :group, Group

    field :member_id, :binary_id
    field :body, :string
    field :seq, :integer, read_after_writes: true

    field :author_email, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a new message.

  `group_id` and `member_id` are arguments rather than castable fields, so
  neither can arrive from a param or a client event.

  The body is trimmed before it is measured, so a whitespace-only message is
  empty, and it is measured in graphemes, so an emoji counts once. The database
  check constraint uses `char_length`, which counts the same units.
  """
  @spec create_changeset(t(), map(), Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Changeset.t()
  def create_changeset(message, attrs, group_id, member_id) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> put_change(:group_id, group_id)
    |> put_change(:member_id, member_id)
    |> validate_required([:body, :group_id, :member_id],
      message: "can't be blank — write a message"
    )
    |> validate_length(:body,
      max: @max_length,
      count: :graphemes,
      message: "is too long — keep it under #{@max_length} characters"
    )
    |> check_constraint(:body, name: :body_length)
  end

  @doc "The longest message the product accepts."
  @spec max_length() :: pos_integer()
  def max_length, do: @max_length
end
