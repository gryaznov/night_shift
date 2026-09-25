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

  alias NightShift.Accounts.User
  alias NightShift.Members.{Member, Site}
  alias NightShift.Tenants.Tenant

  @doc """
  Creates a site in `tenant`'s schema.
  """
  @spec create_site(Tenant.t(), map()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def create_site(%Tenant{}, attrs) when is_map(attrs), do: raise("not implemented")

  @doc """
  Every site of `tenant`.
  """
  @spec list_sites(Tenant.t()) :: [Site.t()]
  def list_sites(%Tenant{}), do: raise("not implemented")

  @doc """
  Creates a member of `tenant` for a user.

  Requires `:user_id`, `:site_id`, `:team` and `:role`; rejects attributes
  missing any of them, and a `:site_id` that is not a site of `tenant`.
  """
  @spec create_member(Tenant.t(), map()) :: {:ok, Member.t()} | {:error, Ecto.Changeset.t()}
  def create_member(%Tenant{}, attrs) when is_map(attrs), do: raise("not implemented")

  @doc """
  The user's active member record in `tenant`, or `nil`.

  This is how the acting member is resolved, once, from the authenticated
  session. A deactivated member resolves to `nil`.
  """
  @spec get_active_member(User.t(), Tenant.t()) :: Member.t() | nil
  def get_active_member(%User{}, %Tenant{}), do: raise("not implemented")

  @doc """
  The user's active member records, across every tenant they work for.
  """
  @spec list_active_members(User.t()) :: [Member.t()]
  def list_active_members(%User{}), do: raise("not implemented")

  @doc """
  Every member of `tenant`, active or not, as seen by `actor`.

  Returns `{:error, :forbidden}` when `actor` is not a member of `tenant`.
  """
  @spec list_members(Member.t(), Tenant.t()) :: {:ok, [Member.t()]} | {:error, :forbidden}
  def list_members(%Member{}, %Tenant{}), do: raise("not implemented")

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
  def deactivate_member(%Member{}, %Member{}), do: raise("not implemented")
end
