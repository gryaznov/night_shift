defmodule NightShiftWeb.GroupLiveTest do
  @moduledoc """
  `NightShiftWeb.GroupLive` does not exist yet. These tests are written against
  the web contract given for plan 0002, step 4, not against an implementation:

    * `/chat/:id` renders `NightShiftWeb.GroupLive`, live action `:show`.
    * `data-test-id="group-title"`; one `data-test-id="message-<message_id>"`
      per message inside a stream, oldest first, at most the newest 200;
      `data-test-id="message-form"` with field `message[body]`;
      `data-test-id="message-error"` for the criterion 6 message.
    * A group id that is not one of the member's two — another site, another
      team, another tenant, or nonexistent — redirects to `/chat` with a
      flash, the same response for all four.
    * The route lives in the existing `:require_active_member` live_session.

  Deactivated-member reading and posting are covered at the context layer
  (`NightShift.ChatTest`), where authorization is decided (invariant 5); the
  session-kill mechanism for an already-open view is the shared, generic
  `:require_active_member` behaviour already covered by
  `NightShiftWeb.WorkspaceLiveTest` and is not re-tested here.

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
  alias NightShift.Chat.{Group, Message}
  alias NightShift.Members

  describe "GET /chat/:id (criterion 2, ruling 8: newest messages, oldest first)" do
    test "renders the group's title and its messages inside the stream, oldest first", %{
      conn: conn
    } do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)

      user = user_fixture()
      member = member_fixture(tenant, user_id: user.id, site_id: site.id, team: :kitchen)

      msg1 = message_fixture(member, team_group, body: "first message")
      msg2 = message_fixture(member, team_group, body: "second message")
      msg3 = message_fixture(member, team_group, body: "third message")

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/chat/#{team_group.id}")

      assert html =~ ~s(data-test-id="group-title")
      assert html =~ Group.display_name(%{team_group | site: site})

      for msg <- [msg1, msg2, msg3] do
        assert html =~ ~s(data-test-id="message-#{msg.id}")
        assert html =~ msg.body
      end

      # Oldest first: msg1's marker appears before msg2's, which appears
      # before msg3's.
      idx1 = :binary.match(html, ~s(data-test-id="message-#{msg1.id}")) |> elem(0)
      idx2 = :binary.match(html, ~s(data-test-id="message-#{msg2.id}")) |> elem(0)
      idx3 = :binary.match(html, ~s(data-test-id="message-#{msg3.id}")) |> elem(0)

      assert idx1 < idx2
      assert idx2 < idx3
    end

    test "caps history at the newest 200 messages when more exist", %{conn: conn} do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)

      user = user_fixture()
      member = member_fixture(tenant, user_id: user.id, site_id: site.id, team: :kitchen)

      messages = for n <- 1..205, do: message_fixture(member, team_group, body: "message #{n}")

      oldest_dropped = Enum.at(messages, 4)
      newest_kept_start = Enum.at(messages, 5)
      newest = Enum.at(messages, 204)

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/chat/#{team_group.id}")

      refute html =~ ~s(data-test-id="message-#{oldest_dropped.id}")
      assert html =~ ~s(data-test-id="message-#{newest_kept_start.id}")
      assert html =~ ~s(data-test-id="message-#{newest.id}")
    end
  end

  describe "criterion 5 / web contract: a group id that is not one of the member's two redirects to /chat with a flash" do
    setup %{conn: conn} do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      user = user_fixture()
      member_fixture(tenant, user_id: user.id, site_id: site.id, team: :kitchen)

      %{conn: log_in_user(conn, user), tenant: tenant, site: site, groups: groups}
    end

    test "another tenant's group id redirects to /chat with a flash", %{conn: conn} do
      other_tenant = tenant_fixture(:two)
      {_other_site, other_groups} = site_with_groups_fixture(other_tenant)

      conn = get(conn, ~p"/chat/#{site_group(other_groups).id}")

      assert redirected_to(conn) == ~p"/chat"
      assert conn.assigns.flash != %{}
    end

    test "another site's group id (same tenant) redirects to /chat with a flash", %{
      conn: conn,
      tenant: tenant
    } do
      {_other_site, other_groups} = site_with_groups_fixture(tenant)

      conn = get(conn, ~p"/chat/#{site_group(other_groups).id}")

      assert redirected_to(conn) == ~p"/chat"
      assert conn.assigns.flash != %{}
    end

    test "another team's group id at the member's own site redirects to /chat with a flash", %{
      conn: conn,
      groups: groups
    } do
      conn = get(conn, ~p"/chat/#{team_group(groups, :bar).id}")

      assert redirected_to(conn) == ~p"/chat"
      assert conn.assigns.flash != %{}
    end

    test "a nonexistent group id redirects to /chat with a flash", %{conn: conn} do
      conn = get(conn, ~p"/chat/#{Ecto.UUID.generate()}")

      assert redirected_to(conn) == ~p"/chat"
      assert conn.assigns.flash != %{}
    end

    test "the response is indistinguishable between another tenant's real group and a nonexistent id",
         %{conn: conn} do
      other_tenant = tenant_fixture(:two)
      {_other_site, other_groups} = site_with_groups_fixture(other_tenant)

      real_but_foreign = get(conn, ~p"/chat/#{site_group(other_groups).id}")
      nonexistent = get(conn, ~p"/chat/#{Ecto.UUID.generate()}")

      assert redirected_to(real_but_foreign) == redirected_to(nonexistent)
      assert real_but_foreign.assigns.flash == nonexistent.assigns.flash
    end
  end

  describe "criterion 6: message validation errors are visible and human-readable" do
    setup %{conn: conn} do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)
      user = user_fixture()
      member = member_fixture(tenant, user_id: user.id, site_id: site.id, team: :kitchen)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/chat/#{team_group.id}")

      %{view: view, member: member, team_group: team_group}
    end

    test "an empty message is rejected with a visible, human-readable error", %{view: view} do
      html =
        view
        |> form("[data-test-id=message-form]", message: %{body: ""})
        |> render_submit()

      assert html =~ ~s(data-test-id="message-error")
      assert html =~ "write a message"
    end

    test "a whitespace-only message is rejected (trimmed before the check, ruling 4)", %{
      view: view
    } do
      html =
        view
        |> form("[data-test-id=message-form]", message: %{body: "   \n\t  "})
        |> render_submit()

      assert html =~ ~s(data-test-id="message-error")
      assert html =~ "write a message"
    end

    test "a message over the maximum length is rejected with a visible, human-readable error", %{
      view: view
    } do
      body = String.duplicate("a", Message.max_length() + 1)

      html =
        view
        |> form("[data-test-id=message-form]", message: %{body: body})
        |> render_submit()

      assert html =~ ~s(data-test-id="message-error")
      assert html =~ "too long"
    end

    test "a 1-character message is accepted and no error is shown", %{
      view: view,
      member: member,
      team_group: team_group
    } do
      html =
        view
        |> form("[data-test-id=message-form]", message: %{body: "z"})
        |> render_submit()

      refute html =~ ~s(data-test-id="message-error")
      assert {:ok, [message]} = Chat.list_messages(member, team_group)
      assert message.body == "z"
    end

    test "a message at exactly the maximum length is accepted", %{
      view: view,
      member: member,
      team_group: team_group
    } do
      body = String.duplicate("a", Message.max_length())

      html =
        view
        |> form("[data-test-id=message-form]", message: %{body: body})
        |> render_submit()

      refute html =~ ~s(data-test-id="message-error")
      assert {:ok, [message]} = Chat.list_messages(member, team_group)
      assert message.body == body
    end
  end

  describe "criterion 4: a posted message appears for every other member viewing the group, without reloading" do
    test "a message posted in one connected session appears in another member's already-open session",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)

      user_a = user_fixture()
      member_a = member_fixture(tenant, user_id: user_a.id, site_id: site.id, team: :kitchen)

      user_b = user_fixture()
      member_fixture(tenant, user_id: user_b.id, site_id: site.id, team: :kitchen)

      {:ok, view_a, _html} =
        conn
        |> log_in_user(user_a)
        |> live(~p"/chat/#{team_group.id}")

      {:ok, view_b, _html} =
        Phoenix.ConnTest.build_conn()
        |> log_in_user(user_b)
        |> live(~p"/chat/#{team_group.id}")

      view_a
      |> form("[data-test-id=message-form]", message: %{body: "hello from A"})
      |> render_submit()

      assert {:ok, [posted]} = Chat.list_messages(member_a, team_group)
      assert posted.body == "hello from A"

      assert render(view_b) =~ ~s(data-test-id="message-#{posted.id}")
      assert render(view_b) =~ "hello from A"
    end
  end

  describe "criterion 7: opening a group clears its unread count for that member" do
    test "mounting the group's LiveView marks it read", %{conn: conn} do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)

      user = user_fixture()
      reader = member_fixture(tenant, user_id: user.id, site_id: site.id, team: :kitchen)

      # First sight seeds the cursor (ruling 3) before the unread messages
      # below exist.
      assert {:ok, _} = Chat.list_groups(reader)

      author = member_fixture(tenant, site_id: site.id, team: :kitchen)
      message_fixture(author, team_group, body: "one")
      message_fixture(author, team_group, body: "two")

      assert {:ok, 2} = Chat.unread_count(reader, team_group)

      {:ok, _view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/chat/#{team_group.id}")

      assert {:ok, 0} = Chat.unread_count(reader, team_group)
    end
  end

  describe "ruling 6: a moved member's already-open session is not ejected, but posting from it fails" do
    test "posting from a stale, already-open view fails after the member is moved elsewhere", %{
      conn: conn
    } do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      {old_site, old_groups} = site_with_groups_fixture(tenant)
      {new_site, _new_groups} = site_with_groups_fixture(tenant)
      old_team_group = team_group(old_groups, :kitchen)

      user = user_fixture()
      member = member_fixture(tenant, user_id: user.id, site_id: old_site.id, team: :kitchen)
      # Stays behind at the old site and team, to witness whether a message
      # actually landed in the old group.
      witness = member_fixture(tenant, site_id: old_site.id, team: :kitchen)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/chat/#{old_team_group.id}")

      assert {:ok, _} =
               Members.update_assignment(manager, member, %{site_id: new_site.id, team: :bar})

      # Ruling 6: no assignment-change broadcast, so the view is not ejected —
      # but the next post re-reads the member and is refused.
      assert Process.alive?(view.pid)

      html =
        view
        |> form("[data-test-id=message-form]", message: %{body: "posting from the old group"})
        |> render_submit()

      refute html =~ "posting from the old group"
      assert {:ok, []} = Chat.list_messages(witness, old_team_group)
    end
  end

  describe "criterion 5: a moved member's open view stops reading the group they left" do
    test "a message posted after the move does not reach the moved member's view", %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      {old_site, old_groups} = site_with_groups_fixture(tenant)
      {new_site, _new_groups} = site_with_groups_fixture(tenant)
      old_team_group = team_group(old_groups, :kitchen)

      user = user_fixture()
      member = member_fixture(tenant, user_id: user.id, site_id: old_site.id, team: :kitchen)
      witness = member_fixture(tenant, site_id: old_site.id, team: :kitchen)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/chat/#{old_team_group.id}")

      assert {:ok, _} =
               Members.update_assignment(manager, member, %{site_id: new_site.id, team: :bar})

      # The subscription outlives the membership: the broadcast still arrives at
      # the moved member's view, which must not render it.
      assert {:ok, _message} =
               Chat.post_message(witness, old_team_group, %{body: "after the move"})

      assert_redirect(view, ~p"/chat")
    end
  end
end
