defmodule NightShift.Repo.Migrations.CreateTenantsAndMembers do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :schema, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:schema])

    # `members` lives in `public` so authorization is one indexed query instead
    # of a scan across every tenant schema. `site_id` points at a row in the
    # tenant's own `sites` table, so no foreign key can express it.
    create table(:members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :restrict), null: false

      add :site_id, :binary_id, null: false
      add :team, :string, null: false
      add :role, :string, null: false
      add :active, :boolean, null: false, default: true
      add :deactivated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:members, [:user_id, :tenant_id])
    create index(:members, [:tenant_id, :active])
    create index(:members, [:tenant_id, :site_id])

    create constraint(:members, :team_is_known,
             check: "team IN ('kitchen', 'front_of_house', 'bar')"
           )

    create constraint(:members, :role_is_known, check: "role IN ('manager', 'staff')")
  end
end
