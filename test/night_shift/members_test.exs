defmodule NightShift.MembersTest do
  # Tenant fixtures come from the two schemas `test_helper.exs` provisions
  # (`tenant_fixture/0,1`); tests touching them run `async: false` per
  # .claude/rules/testing.md.
  use NightShift.DataCase, async: false

  import NightShift.AccountsFixtures
  import NightShift.MembersFixtures
  import NightShift.TenantsFixtures

  alias NightShift.Members
  alias NightShift.Members.Member

  describe "create_member/2 (criterion 3: exactly one site, one team, one role)" do
    test "creates a member given a user, a site of the tenant, a team and a role" do
      tenant = tenant_fixture(:one)
      user = user_fixture()
      site = site_fixture(tenant)

      assert {:ok, member} =
               Members.create_member(tenant, %{
                 user_id: user.id,
                 site_id: site.id,
                 team: :bar,
                 role: :manager
               })

      assert member.site_id == site.id
      assert member.team == :bar
      assert member.role == :manager
      assert member.active == true
    end

    test "rejects attrs with no user_id" do
      tenant = tenant_fixture(:one)
      site = site_fixture(tenant)

      assert {:error, changeset} =
               Members.create_member(tenant, %{site_id: site.id, team: :kitchen, role: :staff})

      assert %{user_id: _} = errors_on(changeset)
    end

    test "rejects attrs with no site_id" do
      tenant = tenant_fixture(:one)
      user = user_fixture()

      assert {:error, changeset} =
               Members.create_member(tenant, %{user_id: user.id, team: :kitchen, role: :staff})

      assert %{site_id: _} = errors_on(changeset)
    end

    test "rejects attrs with no team" do
      tenant = tenant_fixture(:one)
      user = user_fixture()
      site = site_fixture(tenant)

      assert {:error, changeset} =
               Members.create_member(tenant, %{user_id: user.id, site_id: site.id, role: :staff})

      assert %{team: _} = errors_on(changeset)
    end

    test "rejects attrs with no role" do
      tenant = tenant_fixture(:one)
      user = user_fixture()
      site = site_fixture(tenant)

      assert {:error, changeset} =
               Members.create_member(tenant, %{
                 user_id: user.id,
                 site_id: site.id,
                 team: :kitchen
               })

      assert %{role: _} = errors_on(changeset)
    end

    test "rejects a site_id that belongs to another tenant" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)
      user = user_fixture()
      site_b = site_fixture(tenant_b)

      assert {:error, changeset} =
               Members.create_member(tenant_a, %{
                 user_id: user.id,
                 site_id: site_b.id,
                 team: :kitchen,
                 role: :staff
               })

      assert %{site_id: _} = errors_on(changeset)
    end
  end

  describe "get_active_member/2 (criterion 1, context side: only an active membership resolves)" do
    test "returns the member for a user with an active membership in that tenant" do
      tenant = tenant_fixture(:one)
      user = user_fixture()
      member = member_fixture(tenant, user_id: user.id)

      assert %Member{id: id} = Members.get_active_member(user, tenant)
      assert id == member.id
    end

    test "returns nil for a user with no membership in that tenant" do
      tenant = tenant_fixture(:one)
      user = user_fixture()

      refute Members.get_active_member(user, tenant)
    end

    test "returns nil for a user whose only membership is in another tenant" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)
      user = user_fixture()
      member_fixture(tenant_a, user_id: user.id)

      refute Members.get_active_member(user, tenant_b)
    end

    test "returns nil once the member has been deactivated" do
      tenant = tenant_fixture(:one)
      manager_user = user_fixture()
      manager = member_fixture(tenant, user_id: manager_user.id, role: :manager)

      staff_user = user_fixture()
      staff = member_fixture(tenant, user_id: staff_user.id, role: :staff)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      refute Members.get_active_member(staff_user, tenant)
    end
  end

  describe "tenant isolation across list_sites/1 and list_members/2 (criterion 2)" do
    test "list_sites/1 for a tenant never includes a site created in another tenant" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)

      site_a = site_fixture(tenant_a)
      site_b = site_fixture(tenant_b)

      ids = tenant_a |> Members.list_sites() |> Enum.map(& &1.id)

      assert site_a.id in ids
      refute site_b.id in ids
    end

    test "list_members/2 for a tenant never includes a member of another tenant, as seen by a valid actor" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)

      actor = member_fixture(tenant_a, role: :manager)
      member_a = member_fixture(tenant_a)
      member_b = member_fixture(tenant_b)

      assert {:ok, members} = Members.list_members(actor, tenant_a)
      ids = Enum.map(members, & &1.id)

      assert actor.id in ids
      assert member_a.id in ids
      refute member_b.id in ids
    end

    test "list_members/2 refuses tenant A's member reading tenant B's members (cross-tenant read)" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)

      actor = member_fixture(tenant_a, role: :manager)
      member_fixture(tenant_b)

      assert {:error, :forbidden} = Members.list_members(actor, tenant_b)
    end
  end

  describe "deactivate_member/2 (criteria 2 and 4: manager only, own tenant only, never deletes)" do
    test "a manager deactivates a staff member of their own tenant" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)

      assert {:ok, deactivated} = Members.deactivate_member(manager, staff)
      assert deactivated.active == false
      assert deactivated.deactivated_at

      assert %Member{active: false} = Repo.get!(Member, staff.id)
    end

    test "a manager cannot deactivate a member of another tenant (cross-tenant write)" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)

      manager_a = member_fixture(tenant_a, role: :manager)
      staff_b = member_fixture(tenant_b, role: :staff)

      assert {:error, :forbidden} = Members.deactivate_member(manager_a, staff_b)
      assert %Member{active: true} = Repo.get!(Member, staff_b.id)
    end

    test "a staff member can never deactivate another member of their own tenant" do
      tenant = tenant_fixture(:one)
      staff_actor = member_fixture(tenant, role: :staff)
      other_staff = member_fixture(tenant, role: :staff)

      assert {:error, :forbidden} = Members.deactivate_member(staff_actor, other_staff)
      assert %Member{active: true} = Repo.get!(Member, other_staff.id)
    end

    test "a staff member can never deactivate themselves" do
      tenant = tenant_fixture(:one)
      staff_actor = member_fixture(tenant, role: :staff)

      assert {:error, :forbidden} = Members.deactivate_member(staff_actor, staff_actor)
      assert %Member{active: true} = Repo.get!(Member, staff_actor.id)
    end
  end
end
