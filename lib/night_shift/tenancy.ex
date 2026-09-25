defmodule NightShift.Tenancy do
  @moduledoc """
  The only place a query prefix or a PubSub topic is produced.

  Both functions take a `NightShift.Tenants.Tenant` struct and nothing else.
  That is deliberate: a prefix or a topic can then only come from a tenant
  record already loaded from the authenticated session, never from a param, a
  path segment or a client event, because those are strings and neither
  function accepts one.

  Every tenant-schema query passes `prefix: Tenancy.prefix(tenant)`, and every
  broadcast uses `Tenancy.topic(tenant, key)`, so no topic can cross tenants.
  """

  alias NightShift.Tenants.Tenant

  @typedoc "The subject of a topic within one tenant, for example `:members`."
  @type topic_key :: atom()

  @doc """
  The Postgres schema name to use as a query prefix for `tenant`.
  """
  @spec prefix(Tenant.t()) :: String.t()
  def prefix(%Tenant{schema: schema}), do: schema

  @doc """
  The PubSub topic for `key` within `tenant`.

  The tenant is part of every topic, so a subscriber in one tenant cannot
  receive another tenant's broadcasts.
  """
  @spec topic(Tenant.t(), topic_key()) :: String.t()
  def topic(%Tenant{schema: schema}, key) when is_atom(key), do: "tenant:#{schema}:#{key}"
end
