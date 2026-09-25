defmodule NightShiftWeb.ChatLiveTest do
  @moduledoc """
  `NightShiftWeb.ChatLive` does not exist yet. These tests are written against
  the web contract given for plan 0002, step 4, not against an implementation:

    * `/chat` renders `NightShiftWeb.ChatLive`, live action `:index`.
    * Container `data-test-id="chat-groups"`; per group a link
      `data-test-id="group-<group_id>"` whose text is the display name, and
      `data-test-id="group-unread-<group_id>"` carrying the count — absent
      entirely when the count is zero (ruling 7).
    * The route lives in the existing `:require_active_member` live_session,
      whose generic behaviour (unauthenticated, no membership, deactivated
      mid-session) is already covered by `NightShiftWeb.WorkspaceLiveTest` and
      is not re-tested here.

  Do not run this file until the web layer exists — see the report for the
  exact command.
  """

  use NightShiftWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import NightShift.AccountsFixtures
  import NightShift.ChatFixtures
  import NightShift.MembersFixtures
  import NightShift.TenantsFixtures

  alias NightShift.Chat
  alias NightShift.Chat.Group
  alias NightShift.Members

  describe "GET /chat (criterion 1: exactly two groups, and no others)" do
    test "lists the member's site group and site-and-team group, and no other group", %{
      conn: conn
    } do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      {_other_site, other_groups} = site_with_groups_fixture(tenant)

      user = user_fixture()
      member_fixture(tenant, user_id: user.id, site_id: site.id, team: :kitchen)

      site_group = site_group(groups)
      team_group = team_group(groups, :kitchen)

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/chat")

      assert html =~ ~s(data-test-id="chat-groups")

      assert html =~ ~s(data-test-id="group-#{site_group.id}")
      assert html =~ Group.display_name(%{site_group | site: site})

      assert html =~ ~s(data-test-id="group-#{team_group.id}")
      assert html =~ Group.display_name(%{team_group | site: site})

      refute html =~ ~s(data-test-id="group-#{team_group(groups, :front_of_house).id}")
      refute html =~ ~s(data-test-id="group-#{team_group(groups, :bar).id}")
      refute html =~ ~s(data-test-id="group-#{site_group(other_groups).id}")
    end
  end

  describe "GET /chat reflects Members.update_assignment/3 (criterion 3: no LiveView test beyond its effect on the group list)" do
    test "after a manager moves the member, /chat shows the new groups and not the old ones", %{
      conn: conn
    } do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      {old_site, old_groups} = site_with_groups_fixture(tenant)
      {new_site, new_groups} = site_with_groups_fixture(tenant)

      user = user_fixture()
      member = member_fixture(tenant, user_id: user.id, site_id: old_site.id, team: :kitchen)

      assert {:ok, _} =
               Members.update_assignment(manager, member, %{site_id: new_site.id, team: :bar})

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/chat")

      assert html =~ ~s(data-test-id="group-#{site_group(new_groups).id}")
      assert html =~ ~s(data-test-id="group-#{team_group(new_groups, :bar).id}")

      refute html =~ ~s(data-test-id="group-#{site_group(old_groups).id}")
      refute html =~ ~s(data-test-id="group-#{team_group(old_groups, :kitchen).id}")
    end
  end

  describe "criterion 7 / ruling 3 / ruling 7: unread counts" do
    test "a brand-new member's groups show no unread badge, even though the group already has history",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)

      founder = member_fixture(tenant, site_id: site.id, team: :kitchen)
      message_fixture(founder, team_group, body: "history before the newcomer")

      user = user_fixture()
      member_fixture(tenant, user_id: user.id, site_id: site.id, team: :kitchen)

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/chat")

      assert html =~ ~s(data-test-id="group-#{team_group.id}")
      refute html =~ ~s(data-test-id="group-unread-#{team_group.id}")
    end

    test "a returning member sees an unread badge with the count of messages posted since their last visit",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)

      user = user_fixture()
      member = member_fixture(tenant, user_id: user.id, site_id: site.id, team: :kitchen)

      # First sight seeds the cursor (ruling 3) before any unread message
      # exists.
      assert {:ok, _} = Chat.list_groups(member)

      other = member_fixture(tenant, site_id: site.id, team: :kitchen)
      message_fixture(other, team_group, body: "one")
      message_fixture(other, team_group, body: "two")

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/chat")

      assert html =~ ~s(data-test-id="group-unread-#{team_group.id}")

      unread_badge =
        html
        |> Floki.parse_fragment!()
        |> Floki.find(~s([data-test-id="group-unread-#{team_group.id}"]))
        |> Floki.text()

      assert unread_badge =~ "2"
    end
  end
end
