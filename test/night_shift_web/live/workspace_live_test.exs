defmodule NightShiftWeb.WorkspaceLiveTest do
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

  describe "GET /workspace (criterion 1: active membership sees only that tenant's workspace)" do
    test "a user with an active membership sees their tenant's workspace and no other tenant's data",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      other_tenant = tenant_fixture(:two)
      user = user_fixture()
      member_fixture(tenant, user_id: user.id, role: :manager)

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/workspace")

      assert html =~ ~s(data-test-id="workspace-tenant-name")
      assert html =~ tenant.name
      refute html =~ other_tenant.name
    end
  end

  describe "criterion 5: deactivation ends an open session immediately" do
    test "an open LiveView session for the member is disconnected the moment they are deactivated",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)

      staff_user = user_fixture()
      staff = member_fixture(tenant, user_id: staff_user.id, role: :staff)

      {:ok, view, _html} =
        conn
        |> log_in_user(staff_user)
        |> live(~p"/workspace")

      ref = Process.monitor(view.pid)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      # "Disconnected" is tested at the OTP level (the view process is
      # terminated by the server) rather than via a Phoenix.LiveViewTest
      # helper, since the criterion does not specify redirect vs. termination
      # as the mechanism — see report for the ambiguity this assumption
      # resolves.
      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1000
    end

    test "the deactivated member's next request to the workspace lands on the no-access page",
         %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)

      staff_user = user_fixture()
      staff = member_fixture(tenant, user_id: staff_user.id, role: :staff)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      conn =
        conn
        |> log_in_user(staff_user)
        |> get(~p"/workspace")

      assert redirected_to(conn) == ~p"/no-access"
    end
  end
end
