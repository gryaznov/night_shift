defmodule NightShiftWeb.NoAccessLiveTest do
  @moduledoc """
  `NightShiftWeb.WorkspaceLive` and `NightShiftWeb.NoAccessLive` do not exist
  yet. These tests are written against the contract given in plan 0001, step
  7, not against an implementation:

    * `/workspace` renders `NightShiftWeb.WorkspaceLive`, the tenant workspace
      landing page, and requires an authenticated user with an active member
      record in that tenant.
    * `/no-access` renders `NightShiftWeb.NoAccessLive`, shown to a signed-in
      user with no active membership.
    * The tenant and acting member are resolved once, in `on_mount`/a plug,
      from the authenticated session (invariant 3). There is no tenant
      chooser; every fixture user here holds exactly one membership.

  Do not run this file yet — see the report for the exact command once the
  web layer exists.
  """

  use NightShiftWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import NightShift.AccountsFixtures
  import NightShift.MembersFixtures
  import NightShift.TenantsFixtures

  alias NightShift.Members

  describe "criterion 1 (negative): no active membership means no access, no tenant data" do
    test "a signed-in user with no membership anywhere is redirected away from the workspace",
         %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/workspace")

      assert redirected_to(conn) == ~p"/no-access"
    end

    test "a signed-in user with no membership anywhere sees the no-access page and no tenant data",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      user = user_fixture()

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/no-access")

      assert html =~ ~s(data-test-id="no-access-message")
      refute html =~ tenant.name
    end

    test "a deactivated member is redirected away from the workspace and sees no data of their former tenant",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)

      staff_user = user_fixture()
      staff = member_fixture(tenant, user_id: staff_user.id, role: :staff)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      conn = log_in_user(conn, staff_user)

      assert redirected_to(get(conn, ~p"/workspace")) == ~p"/no-access"

      {:ok, _view, html} = live(conn, ~p"/no-access")

      assert html =~ ~s(data-test-id="no-access-message")
      refute html =~ tenant.name
    end
  end
end
