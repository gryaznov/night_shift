defmodule NightShift.ChatFixtures do
  @moduledoc """
  Test helpers for groups and messages.

  Groups are never constructed by hand: `NightShift.Chat.create_groups_for_site/2`
  is the only thing that produces them (a site's site group and one group per
  team), matching the plan's premise that nobody manages group membership.
  """

  import NightShift.MembersFixtures, only: [site_fixture: 2]

  alias NightShift.Chat

  @doc """
  Creates a site and its groups (the site group, plus one group per team) in
  `tenant`. Returns `{site, groups}`.
  """
  def site_with_groups_fixture(tenant, attrs \\ %{}) do
    site = site_fixture(tenant, attrs)
    {:ok, groups} = Chat.create_groups_for_site(tenant, site)
    {site, groups}
  end

  @doc "The site group (`team: nil`) among `groups`."
  def site_group(groups), do: Enum.find(groups, &is_nil(&1.team))

  @doc "The team group for `team` among `groups`."
  def team_group(groups, team), do: Enum.find(groups, &(&1.team == team))

  @doc """
  Posts a message to `group` as `actor` via `NightShift.Chat.post_message/3`.
  Raises if the post is rejected, so callers that expect success can ignore the
  result shape; callers exercising validation call `Chat.post_message/3`
  directly instead.
  """
  def message_fixture(actor, group, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{body: "message #{System.unique_integer([:positive])}"})
    {:ok, message} = Chat.post_message(actor, group, attrs)
    message
  end
end
