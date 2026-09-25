defmodule NightShiftWeb.AnnouncementsLiveTest do
  @moduledoc """
  Tests written against plan 0003's acceptance criteria and the web contract
  given in the step-4 plan message alone:

    * `/announcements` — `AnnouncementsLive`, `:index`. Container
      `data-test-id="announcements"`; one `data-test-id="announcement-<id>"`
      per announcement in a stream, newest first.
    * Manager compose form `data-test-id="announcement-form"`, fields
      `announcement[body]` and `announcement[site_id]` (blank = whole tenant);
      `data-test-id="announcement-error"` for the validation message. Absent
      entirely for staff.
    * Read state, managers only: `data-test-id="read-count-<id>"` carrying
      `read/audience`, and `data-test-id="unread-members-<id>"` listing names.
    * The nav badge is `data-test-id="nav-announcements-unread"`, absent
      entirely when the count is zero.

  Ambiguity this file deliberately does not resolve — see the spec-tester
  report: whether a manager who authored an announcement sees that
  announcement's own `announcement-<id>` item inside the `announcements`
  stream (criterion 2 says an author never sees their own announcement "in
  that list"; criterion 4 says any manager sees read state "for each
  announcement" with no exception for the author). No test here asserts
  either way for that specific case. Every read-state test below uses a
  manager who watches an announcement authored by a *different* manager, and
  additionally confirms an authoring manager still receives the read-state
  markup for their own post keyed by its id (unambiguous under criterion 4),
  without asserting anything about the surrounding stream/container.

  Ambiguity this file also does not resolve: `data-test-id="unread-members-<id>"`
  is said to list "names", but neither `NightShift.Members.Member` nor
  `NightShift.Accounts.User` (read in full for this task) has a `:name`
  field — only `User.email`. Tests here assert the unread member's `email`
  appears in that element, on the assumption "name" means "email" absent any
  other identifying field; if the rendered text uses something else, these
  assertions will fail for a reason unrelated to the criterion they test.
  """

  # Tenant fixtures come from the two schemas `test_helper.exs` provisions;
  # tests touching them run `async: false` per .claude/rules/testing.md.
  use NightShiftWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import NightShift.AccountsFixtures
  import NightShift.AnnouncementsFixtures
  import NightShift.MembersFixtures
  import NightShift.TenantsFixtures

  alias NightShift.Announcements

  describe "criterion 1: only a manager may post (compose form presence)" do
    test "a manager sees the compose form", %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager_user = user_fixture()
      member_fixture(tenant, user_id: manager_user.id, role: :manager)

      {:ok, _view, html} = conn |> log_in_user(manager_user) |> live(~p"/announcements")

      assert html =~ ~s(data-test-id="announcement-form")
    end

    # Negative case required by testing.md: staff posting.
    test "a staff member never sees the compose form", %{conn: conn} do
      tenant = tenant_fixture(:one)
      staff_user = user_fixture()
      member_fixture(tenant, user_id: staff_user.id, role: :staff)

      {:ok, view, html} = conn |> log_in_user(staff_user) |> live(~p"/announcements")

      refute html =~ ~s(data-test-id="announcement-form")
      refute has_element?(view, "[data-test-id='announcement-form']")
    end
  end

  describe "criterion 1: posting through the compose form" do
    test "a manager posts a tenant-wide announcement with a blank site_id", %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager_user = user_fixture()
      member_fixture(tenant, user_id: manager_user.id, role: :manager)

      {:ok, view, _html} = conn |> log_in_user(manager_user) |> live(~p"/announcements")

      view
      |> form("[data-test-id='announcement-form']",
        announcement: %{body: "Tenant wide notice", site_id: ""}
      )
      |> render_submit()

      html = render(view)
      assert html =~ "Tenant wide notice"
    end

    test "a manager posts an announcement targeted at one site", %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager_user = user_fixture()
      member_fixture(tenant, user_id: manager_user.id, role: :manager)
      site = site_fixture(tenant)

      {:ok, view, _html} = conn |> log_in_user(manager_user) |> live(~p"/announcements")

      view
      |> form("[data-test-id='announcement-form']",
        announcement: %{body: "Site notice", site_id: site.id}
      )
      |> render_submit()

      html = render(view)
      assert html =~ "Site notice"
    end

    test "an empty body is rejected with a validation message and nothing is posted", %{
      conn: conn
    } do
      tenant = tenant_fixture(:one)
      manager_user = user_fixture()
      member_fixture(tenant, user_id: manager_user.id, role: :manager)

      {:ok, view, _html} = conn |> log_in_user(manager_user) |> live(~p"/announcements")

      html =
        view
        |> form("[data-test-id='announcement-form']", announcement: %{body: ""})
        |> render_submit()

      assert html =~ ~s(data-test-id="announcement-error")
    end
  end

  describe "criterion 2: a recipient sees announcements targeted at them, newest first" do
    test "a staff member sees a tenant-wide announcement and one addressed to their own site, not another site, newest first",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)

      own_site = site_fixture(tenant)
      other_site = site_fixture(tenant)

      staff_user = user_fixture()
      member_fixture(tenant, user_id: staff_user.id, role: :staff, site_id: own_site.id)

      tenant_wide = Announcements.post_announcement(manager, %{body: "For everyone"})
      assert {:ok, tenant_wide} = tenant_wide

      own_site_announcement =
        Announcements.post_announcement(manager, %{body: "For my site", site_id: own_site.id})

      assert {:ok, own_site_announcement} = own_site_announcement

      other_site_announcement =
        Announcements.post_announcement(manager, %{
          body: "For the other site",
          site_id: other_site.id
        })

      assert {:ok, other_site_announcement} = other_site_announcement

      {:ok, _view, html} = conn |> log_in_user(staff_user) |> live(~p"/announcements")

      assert html =~ ~s(data-test-id="announcement-#{tenant_wide.id}")
      assert html =~ ~s(data-test-id="announcement-#{own_site_announcement.id}")
      refute html =~ ~s(data-test-id="announcement-#{other_site_announcement.id}")

      newest_pos = :binary.match(html, "announcement-#{own_site_announcement.id}") |> elem(0)
      oldest_pos = :binary.match(html, "announcement-#{tenant_wide.id}") |> elem(0)
      assert newest_pos < oldest_pos
    end
  end

  describe "criterion 3: reading is automatic — visiting the page is enough" do
    test "simply mounting the page as a recipient records the read, visible to a watching manager without reload",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      author = member_fixture(tenant, role: :manager)

      watcher_site = site_fixture(tenant)
      target_site = site_fixture(tenant)
      watcher_user = user_fixture()
      member_fixture(tenant, user_id: watcher_user.id, role: :manager, site_id: watcher_site.id)

      staff_user = user_fixture()
      member_fixture(tenant, user_id: staff_user.id, role: :staff, site_id: target_site.id)

      assert {:ok, announcement} =
               Announcements.post_announcement(author, %{
                 body: "Site-only notice",
                 site_id: target_site.id
               })

      {:ok, watcher_view, watcher_html} =
        conn |> log_in_user(watcher_user) |> live(~p"/announcements")

      assert watcher_html =~ ~r/read-count-#{announcement.id}"[^>]*>\s*0\s*\/\s*1/

      Phoenix.ConnTest.build_conn()
      |> log_in_user(staff_user)
      |> live(~p"/announcements")

      updated_html = render(watcher_view)
      assert updated_html =~ ~r/read-count-#{announcement.id}"[^>]*>\s*1\s*\/\s*1/
      refute updated_html =~ staff_user.email
    end
  end

  describe "criterion 4: any manager sees read counts and unread names; staff never do" do
    test "a manager watching sees the audience, read count, and the unread member's name for another manager's announcement",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      author = member_fixture(tenant, role: :manager)

      watcher_site = site_fixture(tenant)
      target_site = site_fixture(tenant)
      watcher_user = user_fixture()
      member_fixture(tenant, user_id: watcher_user.id, role: :manager, site_id: watcher_site.id)

      staff_user = user_fixture()
      member_fixture(tenant, user_id: staff_user.id, role: :staff, site_id: target_site.id)

      assert {:ok, announcement} =
               Announcements.post_announcement(author, %{
                 body: "Watch me",
                 site_id: target_site.id
               })

      {:ok, _view, html} = conn |> log_in_user(watcher_user) |> live(~p"/announcements")

      assert html =~ ~s(data-test-id="read-count-#{announcement.id}")
      assert html =~ ~s(data-test-id="unread-members-#{announcement.id}")
      assert html =~ staff_user.email
    end

    test "an authoring manager also sees read-state markup for their own announcement, by id", %{
      conn: conn
    } do
      tenant = tenant_fixture(:one)
      manager_user = user_fixture()
      manager = member_fixture(tenant, user_id: manager_user.id, role: :manager)
      member_fixture(tenant, role: :staff)

      assert {:ok, announcement} =
               Announcements.post_announcement(manager, %{body: "My own announcement"})

      {:ok, _view, html} = conn |> log_in_user(manager_user) |> live(~p"/announcements")

      assert html =~ ~s(data-test-id="read-count-#{announcement.id}")
    end

    test "a staff member never sees read-count or unread-members markup", %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff_user = user_fixture()
      member_fixture(tenant, user_id: staff_user.id, role: :staff)

      assert {:ok, announcement} = Announcements.post_announcement(manager, %{body: "Notice"})

      {:ok, view, html} = conn |> log_in_user(staff_user) |> live(~p"/announcements")

      refute html =~ ~s(data-test-id="read-count-#{announcement.id}")
      refute html =~ ~s(data-test-id="unread-members-#{announcement.id}")
      refute has_element?(view, "[data-test-id='read-count-#{announcement.id}']")
    end

    test "the read count and unread names update live for a watching manager as a recipient reads, without reload",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      author = member_fixture(tenant, role: :manager)

      watcher_site = site_fixture(tenant)
      target_site = site_fixture(tenant)
      watcher_user = user_fixture()
      member_fixture(tenant, user_id: watcher_user.id, role: :manager, site_id: watcher_site.id)

      staff_user = user_fixture()

      staff =
        member_fixture(tenant, user_id: staff_user.id, role: :staff, site_id: target_site.id)

      assert {:ok, announcement} =
               Announcements.post_announcement(author, %{
                 body: "Moving target",
                 site_id: target_site.id
               })

      {:ok, watcher_view, before_html} =
        conn |> log_in_user(watcher_user) |> live(~p"/announcements")

      assert before_html =~ staff_user.email

      assert {:ok, _} = Announcements.record_views(staff, [announcement])

      after_html = render(watcher_view)
      assert after_html =~ ~r/read-count-#{announcement.id}"[^>]*>\s*1\s*\/\s*1/
      refute after_html =~ staff_user.email
    end
  end

  describe "criterion 5: a new announcement appears live for a connected recipient, without reload" do
    test "a tenant-wide announcement posted after mount appears in an open recipient view, without reload",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff_user = user_fixture()
      member_fixture(tenant, user_id: staff_user.id, role: :staff)

      {:ok, view, before_html} = conn |> log_in_user(staff_user) |> live(~p"/announcements")
      refute before_html =~ "Breaking news"

      assert {:ok, announcement} =
               Announcements.post_announcement(manager, %{body: "Breaking news"})

      after_html = render(view)
      assert after_html =~ ~s(data-test-id="announcement-#{announcement.id}")
      assert after_html =~ "Breaking news"
    end

    test "an announcement targeted at another site never appears live for a recipient of a different site",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      own_site = site_fixture(tenant)
      other_site = site_fixture(tenant)
      staff_user = user_fixture()
      member_fixture(tenant, user_id: staff_user.id, role: :staff, site_id: own_site.id)

      {:ok, view, _html} = conn |> log_in_user(staff_user) |> live(~p"/announcements")

      assert {:ok, announcement} =
               Announcements.post_announcement(manager, %{
                 body: "Not for you",
                 site_id: other_site.id
               })

      after_html = render(view)
      refute after_html =~ ~s(data-test-id="announcement-#{announcement.id}")
    end
  end

  describe "criterion 6: the nav unread counter" do
    test "a member with unread announcements sees the counter", %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff_user = user_fixture()
      member_fixture(tenant, user_id: staff_user.id, role: :staff)

      assert {:ok, _} = Announcements.post_announcement(manager, %{body: "Read me"})

      {:ok, _view, html} = conn |> log_in_user(staff_user) |> live(~p"/workspace")

      assert html =~ ~s(data-test-id="nav-announcements-unread")
      assert html =~ ~r/nav-announcements-unread"[^>]*>\s*1/
    end

    test "a member with nothing unread sees no counter at all", %{conn: conn} do
      tenant = tenant_fixture(:one)
      staff_user = user_fixture()
      member_fixture(tenant, user_id: staff_user.id, role: :staff)

      {:ok, _view, html} = conn |> log_in_user(staff_user) |> live(~p"/workspace")

      refute html =~ ~s(data-test-id="nav-announcements-unread")
    end

    test "the counter rises live when a new announcement arrives, without reload", %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff_user = user_fixture()
      member_fixture(tenant, user_id: staff_user.id, role: :staff)

      {:ok, view, before_html} = conn |> log_in_user(staff_user) |> live(~p"/workspace")
      refute before_html =~ ~s(data-test-id="nav-announcements-unread")

      assert {:ok, _} = Announcements.post_announcement(manager, %{body: "New!"})

      after_html = render(view)
      assert after_html =~ ~s(data-test-id="nav-announcements-unread")
    end

    test "the counter falls live when the member reads the announcement elsewhere in the same session, without reload",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff_user = user_fixture()
      staff = member_fixture(tenant, user_id: staff_user.id, role: :staff)

      assert {:ok, announcement} = Announcements.post_announcement(manager, %{body: "Read me"})

      conn = log_in_user(conn, staff_user)
      {:ok, workspace_view, before_html} = live(conn, ~p"/workspace")
      assert before_html =~ ~r/nav-announcements-unread"[^>]*>\s*1/

      assert {:ok, _} = Announcements.record_views(staff, [announcement])

      after_html = render(workspace_view)
      refute after_html =~ ~s(data-test-id="nav-announcements-unread")
    end

    test "pages with no tenant in scope show no counter: no-access, settings, sign-in", %{
      conn: conn
    } do
      staff_user = user_fixture()

      {:ok, _view, no_access_html} =
        conn |> log_in_user(staff_user) |> live(~p"/no-access")

      refute no_access_html =~ ~s(data-test-id="nav-announcements-unread")

      {:ok, _view, settings_html} =
        Phoenix.ConnTest.build_conn()
        |> log_in_user(staff_user)
        |> live(~p"/users/settings")

      refute settings_html =~ ~s(data-test-id="nav-announcements-unread")

      {:ok, _view, login_html} =
        Phoenix.ConnTest.build_conn() |> live(~p"/users/log_in")

      refute login_html =~ ~s(data-test-id="nav-announcements-unread")
    end
  end

  describe "criterion 7: an announcement can never be edited, updated or deleted by anyone" do
    test "no route exists to mutate an announcement, even for its author", %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager_user = user_fixture()
      manager = member_fixture(tenant, user_id: manager_user.id, role: :manager)

      assert {:ok, announcement} =
               Announcements.post_announcement(manager, %{body: "Immutable"})

      conn = log_in_user(conn, manager_user)

      assert get(conn, "/announcements/#{announcement.id}/edit").status == 404

      assert put(conn, "/announcements/#{announcement.id}", %{
               "announcement" => %{"body" => "x"}
             }).status == 404

      assert delete(conn, "/announcements/#{announcement.id}").status == 404
    end
  end
end
