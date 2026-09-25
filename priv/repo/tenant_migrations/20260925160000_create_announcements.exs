defmodule NightShift.Repo.Migrations.CreateAnnouncements do
  use Ecto.Migration

  # An announcement's audience is never stored: it is every active member of
  # this tenant the announcement targets, read from `public.members` at query
  # time, so a member deactivated or hired after posting is counted correctly.
  def change do
    create table(:announcements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :author_member_id,
          references(:members, type: :binary_id, on_delete: :restrict, prefix: "public"),
          null: false

      # NULL targets the whole tenant. A real foreign key, unlike
      # `members.site_id`, because `sites` is in this same schema.
      add :site_id, references(:sites, type: :binary_id, on_delete: :restrict)

      add :body, :text, null: false

      # The ordering key. `:utc_datetime` is second-granular, so two
      # announcements posted in one second cannot be ordered by `inserted_at`.
      add :seq, :bigserial, null: false

      # No `updated_at`: an announcement is never edited after publication, and
      # the table says so.
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:announcements, [:seq])
    create index(:announcements, [:site_id])

    create constraint(:announcements, :body_length, check: "char_length(body) BETWEEN 1 AND 2000")

    # One row per member per announcement, written the first time they see it.
    # The composite primary key is what makes a second view a no-op rather than
    # a second row with a later timestamp.
    create table(:announcement_acknowledgements, primary_key: false) do
      add :announcement_id, references(:announcements, type: :binary_id, on_delete: :restrict),
        primary_key: true

      add :member_id,
          references(:members, type: :binary_id, on_delete: :restrict, prefix: "public"),
          primary_key: true

      # The recorded read time. No `updated_at`: the first read is the only one.
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:announcement_acknowledgements, [:member_id])
  end
end
