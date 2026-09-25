defmodule NightShift.Members do
  @moduledoc """
  Employment: who may act in a tenant, at which site, in which team, as what.

  Every function that decides something takes the acting member first, and no
  function reaches another tenant's data — `tenant_id` is always passed, never
  derived from a param and never defaulted.

  `create_site/2` and `create_member/2` take a tenant rather than an acting
  member because nothing in the product creates either: they exist for seeds.
  Giving managers a member-creation UI means adding functions that do take an
  actor, not adding an actor argument to these.
  """

  import Ecto.Query

  alias NightShift.Accounts.User
  alias NightShift.Chat
  alias NightShift.Members.{Member, Site}
  alias NightShift.Repo
  alias NightShift.Tenancy
  alias NightShift.Tenants.Tenant

  @doc """
  Creates a site in `tenant`'s schema, together with its groups.

  The site group and the three team groups are created in the same transaction,
  by `NightShift.Chat.create_groups_for_site/2`. A site without its groups would
  leave every member posted to it with fewer than the two groups criterion 1
  promises, and nothing else in the product creates a site, so this is the only
  place that guarantee can live.
  """
  @spec create_site(Tenant.t(), map()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def create_site(%Tenant{} = tenant, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      with {:ok, site} <-
             %Site{} |> Site.changeset(attrs) |> Repo.insert(prefix: Tenancy.prefix(tenant)),
           {:ok, _groups} <- Chat.create_groups_for_site(tenant, site) do
        site
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Every site of `tenant`.
  """
  @spec list_sites(Tenant.t()) :: [Site.t()]
  def list_sites(%Tenant{} = tenant) do
    Site
    |> order_by(asc: :name)
    |> Repo.all(prefix: Tenancy.prefix(tenant))
  end

  @doc """
  Creates a member of `tenant` for a user.

  Requires `:user_id`, `:site_id`, `:team` and `:role`; rejects attributes
  missing any of them, and a `:site_id` that is not a site of `tenant`.
  """
  @spec create_member(Tenant.t(), map()) :: {:ok, Member.t()} | {:error, Ecto.Changeset.t()}
  def create_member(%Tenant{} = tenant, attrs) when is_map(attrs) do
    %Member{}
    |> Member.create_changeset(attrs, tenant.id)
    |> validate_site_of_tenant(tenant)
    |> Repo.insert()
  end

  @doc """
  The user's active member record in `tenant`, or `nil`.

  The single-tenant lookup, used by seeds and tests. A session resolves its
  acting member through `list_active_members/1`, not this. A deactivated member
  resolves to `nil`.
  """
  @spec get_active_member(User.t(), Tenant.t()) :: Member.t() | nil
  def get_active_member(%User{} = user, %Tenant{} = tenant) do
    Member
    |> where(user_id: ^user.id, tenant_id: ^tenant.id, active: true)
    |> Repo.one()
  end

  @doc """
  The user's member record in `tenant`, active or not, or `nil`.

  Deliberately blind to `active`, so a caller asking whether the employment
  exists at all — seeds, which must not re-create a deactivated member — does not
  get `nil` for a deactivated one. Never use it to decide whether someone may
  act: that is `get_active_member/2` or `list_active_members/1`.
  """
  @spec get_member(User.t(), Tenant.t()) :: Member.t() | nil
  def get_member(%User{} = user, %Tenant{} = tenant) do
    Member
    |> where(user_id: ^user.id, tenant_id: ^tenant.id)
    |> Repo.one()
  end

  @doc """
  The user's active member records, across every tenant they work for, each with
  its tenant preloaded.

  This is how the acting member is resolved, once, from the authenticated
  session: it answers both which tenant the user acts in and as which member, in
  one query. It filters on the authenticated `user_id` rather than a passed
  `tenant_id` — the carve-out invariant 2 names, since the question it answers is
  which tenants the user may act in at all.
  """
  @spec list_active_members(User.t()) :: [Member.t()]
  def list_active_members(%User{} = user) do
    Member
    |> where(user_id: ^user.id, active: true)
    |> order_by(asc: :inserted_at)
    |> preload(:tenant)
    |> Repo.all()
  end

  @doc """
  Every member of `tenant`, active or not, as seen by `actor`.

  Returns `{:error, :forbidden}` when `actor` is not a member of `tenant`.
  """
  @spec list_members(Member.t(), Tenant.t()) :: {:ok, [Member.t()]} | {:error, :forbidden}
  def list_members(%Member{} = actor, %Tenant{} = tenant) do
    with {:ok, actor} <- still_active(actor),
         true <- actor.tenant_id == tenant.id do
      members =
        Member
        |> where(tenant_id: ^tenant.id)
        |> order_by(asc: :inserted_at)
        |> Repo.all()

      {:ok, members}
    else
      _ -> {:error, :forbidden}
    end
  end

  @doc """
  Moves `target` to another site or team within the same tenant.

  `actor` must be an active manager of `target`'s tenant. Changing a site or a
  team changes which two groups the member is in, because group membership is
  derived from this record and nothing else — no group is edited here.

  Refusals, none of which change anything:

    * `{:error, :forbidden}` — `actor` is not an active manager, or `target`
      belongs to another tenant.
    * `{:error, :already_inactive}` — `target` is deactivated; a member with no
      access is not moved, they are re-created.

  Only `:site_id` and `:team` can be changed. Role changes and reactivation are
  not this function's business, and `:tenant_id` and `:user_id` are never
  writable.
  """
  @spec update_assignment(Member.t(), Member.t(), map()) ::
          {:ok, Member.t()}
          | {:error, :forbidden | :already_inactive}
          | {:error, Ecto.Changeset.t()}
  def update_assignment(%Member{} = _actor, %Member{} = _target, attrs) when is_map(attrs) do
    raise "not implemented"
  end

  @doc """
  Deactivates `target`, ending their access to that tenant from that moment.

  `actor` may deactivate any member of their own tenant, themselves included.
  Refusals, none of which change anything:

    * `{:error, :forbidden}` — `actor` is not a manager, or `target` belongs to
      another tenant.
    * `{:error, :last_manager}` — `target` is the only active manager left.
    * `{:error, :already_inactive}` — `target` is already deactivated.

  Never deletes the record.

  The last-manager check and the update are one serialized unit: counting
  active managers and then writing would let two concurrent deactivations both
  pass the count and leave the tenant with none.
  """
  @spec deactivate_member(Member.t(), Member.t()) ::
          {:ok, Member.t()}
          | {:error, :forbidden | :last_manager | :already_inactive}
          | {:error, Ecto.Changeset.t()}
  def deactivate_member(%Member{} = actor, %Member{} = target) do
    with {:ok, actor} <- still_active(actor),
         true <- actor.role == :manager,
         true <- actor.tenant_id == target.tenant_id,
         {:ok, member} <- Repo.transaction(fn -> deactivate(target) end) do
      broadcast_deactivation(member)
      {:ok, member}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :forbidden}
    end
  end

  # Broadcast only after the transaction commits: a subscriber that reacted to an
  # uncommitted deactivation could re-resolve the member and still find it active.
  defp broadcast_deactivation(%Member{} = member) do
    tenant = Repo.get!(Tenant, member.tenant_id)

    Phoenix.PubSub.broadcast(
      NightShift.PubSub,
      Tenancy.topic(tenant, :members),
      {:member_deactivated, member.id}
    )
  end

  # Invariant 3 fixes *identity* — which tenant, which member — at the session
  # boundary and forbids re-deriving it. It does not fix *liveness*: a member
  # deactivated after the acting member was loaded must not still be able to act,
  # including from a session already open (invariant 4). Re-reading a member by
  # its own id is not deriving identity from an untrusted source.
  defp still_active(%Member{id: id}) do
    case Repo.get(Member, id) do
      %Member{active: true} = member -> {:ok, member}
      _ -> :error
    end
  end

  # One locking read covers both questions this has to answer — is the target
  # still active, and is it the tenant's last active manager — so a concurrent
  # deactivation cannot see a spare manager that this one is about to remove.
  # Ordering by id keeps two such transactions from deadlocking.
  defp deactivate(%Member{} = target) do
    rows =
      Member
      |> where([m], m.tenant_id == ^target.tenant_id)
      |> where([m], m.id == ^target.id or (m.active and m.role == :manager))
      |> order_by(asc: :id)
      |> lock("FOR UPDATE")
      |> Repo.all()

    current = Enum.find(rows, &(&1.id == target.id))
    active_managers = Enum.filter(rows, &(&1.active and &1.role == :manager))

    cond do
      is_nil(current) ->
        Repo.rollback(:forbidden)

      not current.active ->
        Repo.rollback(:already_inactive)

      current.role == :manager and length(active_managers) <= 1 ->
        Repo.rollback(:last_manager)

      true ->
        case Repo.update(Member.deactivation_changeset(current)) do
          {:ok, member} -> member
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  # `site_id` cannot be a foreign key: `sites` lives in the tenant schema and
  # `members` in `public`. This is the only thing keeping the two in step.
  defp validate_site_of_tenant(changeset, tenant) do
    case Ecto.Changeset.get_change(changeset, :site_id) do
      nil ->
        changeset

      site_id ->
        exists? =
          Site
          |> where(id: ^site_id)
          |> Repo.exists?(prefix: Tenancy.prefix(tenant))

        if exists?,
          do: changeset,
          else: Ecto.Changeset.add_error(changeset, :site_id, "is not a site of this tenant")
    end
  end
end
