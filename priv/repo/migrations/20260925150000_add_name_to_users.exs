defmodule NightShift.Repo.Migrations.AddNameToUsers do
  use Ecto.Migration

  # Criterion 4 of plan 0003 asks a manager to see the names of the people who
  # have not read an announcement, and a user had only an email address.
  def up do
    alter table(:users) do
      add :name, :string
    end

    # Existing rows predate the column, so the local part of the address is the
    # only name available. Seeded users are re-seeded with better ones.
    execute("UPDATE users SET name = split_part(email, '@', 1) WHERE name IS NULL")

    alter table(:users) do
      modify :name, :string, null: false
    end
  end

  def down do
    alter table(:users) do
      remove :name
    end
  end
end
