defmodule NightShift.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  # Groups are not membership: a member's two groups are derived from
  # `public.members.site_id` and `.team`, so nothing here records who belongs.
  def change do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :site_id, references(:sites, type: :binary_id, on_delete: :restrict), null: false
      add :team, :string

      timestamps(type: :utc_datetime)
    end

    # Postgres treats NULL as distinct, so the site group needs its own partial
    # index: `unique_index([:site_id, :team])` alone would admit two of them.
    create unique_index(:groups, [:site_id],
             where: "team IS NULL",
             name: :groups_site_group_unique
           )

    create unique_index(:groups, [:site_id, :team])

    create constraint(:groups, :team_is_known,
             check: "team IS NULL OR team IN ('kitchen', 'front_of_house', 'bar')"
           )

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, references(:groups, type: :binary_id, on_delete: :restrict), null: false

      add :member_id,
          references(:members, type: :binary_id, on_delete: :restrict, prefix: "public"),
          null: false

      add :body, :text, null: false

      # The unread cursor. A timestamp cannot serve: `:utc_datetime` is
      # second-granular, so two messages in one second would be indistinguishable.
      add :seq, :bigserial, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:group_id, :seq])
    create unique_index(:messages, [:seq])

    create constraint(:messages, :body_length, check: "char_length(body) BETWEEN 1 AND 2000")

    create table(:group_reads, primary_key: false) do
      add :group_id, references(:groups, type: :binary_id, on_delete: :restrict),
        primary_key: true

      add :member_id,
          references(:members, type: :binary_id, on_delete: :restrict, prefix: "public"),
          primary_key: true

      # No default: the row is always written with a seeded cursor, and a default
      # of 0 would make a missing seed read as "the whole history is unread".
      add :last_read_seq, :bigint, null: false

      timestamps(type: :utc_datetime)
    end

    execute(&backfill_groups/0, &delete_groups/0)
  end

  # One site group and one group per team, for every site this tenant already
  # has. Raw SQL is not prefixed the way Ecto's DDL is, hence `prefix()`.
  defp backfill_groups do
    repo().query!("""
    INSERT INTO "#{prefix()}"."groups" (id, site_id, team, inserted_at, updated_at)
    SELECT gen_random_uuid(), s.id, t.team, date_trunc('second', now()), date_trunc('second', now())
    FROM "#{prefix()}"."sites" AS s
    CROSS JOIN (VALUES (NULL::varchar), ('kitchen'), ('front_of_house'), ('bar')) AS t(team)
    """)
  end

  defp delete_groups do
    repo().query!(~s|DELETE FROM "#{prefix()}"."groups"|)
  end
end
