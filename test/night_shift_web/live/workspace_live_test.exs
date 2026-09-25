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
  alias NightShift.Tenancy

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

    # Invariant 6 and the `member_id` guard in `TenantAuth`: a deactivation ends
    # exactly one session. Without both, "disconnect the deactivated member"
    # still passes while every open session in the tenant — or in every tenant —
    # is torn down.
    test "another member's open session in the same tenant is untouched", %{conn: conn} do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)

      staff_user = user_fixture()
      staff = member_fixture(tenant, user_id: staff_user.id, role: :staff)

      bystander_user = user_fixture()
      member_fixture(tenant, user_id: bystander_user.id, role: :staff)

      {:ok, staff_view, _html} =
        conn |> log_in_user(staff_user) |> live(~p"/workspace")

      {:ok, bystander_view, _html} =
        Phoenix.ConnTest.build_conn() |> log_in_user(bystander_user) |> live(~p"/workspace")

      staff_ref = Process.monitor(staff_view.pid)
      bystander_ref = Process.monitor(bystander_view.pid)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      assert_receive {:DOWN, ^staff_ref, :process, _pid, _reason}, 1000
      refute_receive {:DOWN, ^bystander_ref, :process, _pid, _reason}, 300
      assert render(bystander_view) =~ tenant.name
    end

    test "a member of another tenant is untouched by this tenant's deactivation", %{conn: conn} do
      tenant = tenant_fixture(:one)
      other_tenant = tenant_fixture(:two)

      manager = member_fixture(tenant, role: :manager)

      staff_user = user_fixture()
      staff = member_fixture(tenant, user_id: staff_user.id, role: :staff)

      other_user = user_fixture()
      member_fixture(other_tenant, user_id: other_user.id, role: :staff)

      {:ok, staff_view, _html} =
        conn |> log_in_user(staff_user) |> live(~p"/workspace")

      {:ok, other_view, _html} =
        Phoenix.ConnTest.build_conn() |> log_in_user(other_user) |> live(~p"/workspace")

      staff_ref = Process.monitor(staff_view.pid)
      other_ref = Process.monitor(other_view.pid)

      # The view staying up is not enough on its own: the `member_id` guard in
      # `TenantAuth` would keep it up even on a shared topic. Invariant 6 is that
      # the broadcast never reaches the other tenant at all.
      Phoenix.PubSub.subscribe(NightShift.PubSub, Tenancy.topic(other_tenant, :members))
      Phoenix.PubSub.subscribe(NightShift.PubSub, Tenancy.topic(tenant, :members))

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      assert_receive {:member_deactivated, staff_id}, 1000
      assert staff_id == staff.id
      refute_received {:member_deactivated, _other}

      assert_receive {:DOWN, ^staff_ref, :process, _pid, _reason}, 1000
      refute_receive {:DOWN, ^other_ref, :process, _pid, _reason}, 300
      assert render(other_view) =~ other_tenant.name
    end
  end
end
