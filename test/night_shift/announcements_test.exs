defmodule NightShift.AnnouncementsTest do
  # Tenant fixtures come from the two schemas `test_helper.exs` provisions
  # (`tenant_fixture/0,1`); tests touching them run `async: false` per
  # .claude/rules/testing.md.
  use NightShift.DataCase, async: false

  import NightShift.AnnouncementsFixtures
  import NightShift.MembersFixtures
  import NightShift.TenantsFixtures

  alias NightShift.Announcements
  alias NightShift.Members

  describe "post_announcement/2 (criterion 1: a manager posts, tenant-wide or to one site)" do
    test "a manager posts a tenant-wide announcement (no site_id)" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)

      assert {:ok, announcement} =
               Announcements.post_announcement(manager, %{body: "All hands meeting at 5pm"})

      assert announcement.body == "All hands meeting at 5pm"
      assert announcement.site_id == nil
      assert announcement.author_member_id == manager.id
    end

    test "a manager posts an announcement to one site of their tenant" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      site = site_fixture(tenant)

      assert {:ok, announcement} =
               Announcements.post_announcement(manager, %{
                 body: "Site meeting at 5pm",
                 site_id: site.id
               })

      assert announcement.site_id == site.id
    end

    test "rejects a body of nothing but whitespace" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)

      assert {:error, changeset} = Announcements.post_announcement(manager, %{body: "   "})
      assert %{body: _} = errors_on(changeset)
    end

    # Negative case required by testing.md: staff posting.
    test "a staff member cannot post an announcement (negative, criterion 1)" do
      tenant = tenant_fixture(:one)
      staff = member_fixture(tenant, role: :staff)

      assert {:error, :forbidden} =
               Announcements.post_announcement(staff, %{body: "I am not a manager"})
    end

    # Negative case required by testing.md: a deactivated member posting.
    test "a deactivated manager cannot post an announcement, even mid-session (negative, invariant 4)" do
      tenant = tenant_fixture(:one)
      other_manager = member_fixture(tenant, role: :manager)
      manager = member_fixture(tenant, role: :manager)

      assert {:ok, _} = Members.deactivate_member(other_manager, manager)

      assert {:error, :forbidden} =
               Announcements.post_announcement(manager, %{body: "I was deactivated"})
    end

    # Negative case required by testing.md: another tenant's site_id as a target.
    test "a site_id belonging to another tenant is rejected as a changeset error, not found (negative, criterion 1)" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)
      manager = member_fixture(tenant_a, role: :manager)
      site_b = site_fixture(tenant_b)

      assert {:error, changeset} =
               Announcements.post_announcement(manager, %{
                 body: "Wrong tenant's site",
                 site_id: site_b.id
               })

      assert %{site_id: _} = errors_on(changeset)
    end
  end

  describe "list_for_member/1 (criterion 2: a member sees announcements targeted at them, newest first, never their own)" do
    test "a member sees a tenant-wide announcement" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)
      announcement = announcement_fixture(manager)

      assert {:ok, list} = Announcements.list_for_member(staff)
      assert Enum.any?(list, &(&1.id == announcement.id))
    end

    test "a member sees an announcement targeted at their own site" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      site = site_fixture(tenant)
      staff = member_fixture(tenant, role: :staff, site_id: site.id)
      announcement = announcement_fixture(manager, site_id: site.id)

      assert {:ok, list} = Announcements.list_for_member(staff)
      assert Enum.any?(list, &(&1.id == announcement.id))
    end

    test "a member does not see an announcement targeted at another site" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      site_a = site_fixture(tenant)
      site_b = site_fixture(tenant)
      staff = member_fixture(tenant, role: :staff, site_id: site_a.id)
      announcement = announcement_fixture(manager, site_id: site_b.id)

      assert {:ok, list} = Announcements.list_for_member(staff)
      refute Enum.any?(list, &(&1.id == announcement.id))
    end

    test "announcements come back newest first" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)

      first = announcement_fixture(manager, body: "first")
      second = announcement_fixture(manager, body: "second")
      third = announcement_fixture(manager, body: "third")

      assert {:ok, list} = Announcements.list_for_member(staff)
      ids = list |> Enum.map(& &1.id) |> Enum.filter(&(&1 in [first.id, second.id, third.id]))

      assert ids == [third.id, second.id, first.id]
    end

    test "the author does not see their own announcement in their list" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      announcement = announcement_fixture(manager)

      assert {:ok, list} = Announcements.list_for_member(manager)
      refute Enum.any?(list, &(&1.id == announcement.id))
    end

    # Negative case required by testing.md: a deactivated member reading.
    test "a deactivated member cannot list announcements (negative, invariant 4)" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      assert {:error, :forbidden} = Announcements.list_for_member(staff)
    end
  end

  describe "get_for_member/2 (criterion 2 support; isolation of ids)" do
    test "a member fetches an announcement addressed to them by id" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)
      announcement = announcement_fixture(manager)

      assert {:ok, fetched} = Announcements.get_for_member(staff, announcement.id)
      assert fetched.id == announcement.id
    end

    test "returns forbidden for an announcement addressed to another site" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      site_a = site_fixture(tenant)
      site_b = site_fixture(tenant)
      staff = member_fixture(tenant, role: :staff, site_id: site_a.id)
      announcement = announcement_fixture(manager, site_id: site_b.id)

      assert {:error, :forbidden} = Announcements.get_for_member(staff, announcement.id)
    end

    # Negative case required by testing.md: another tenant's announcement id.
    test "returns forbidden for an announcement id belonging to another tenant (negative, criterion 2)" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)
      manager_a = member_fixture(tenant_a, role: :manager)
      manager_b = member_fixture(tenant_b, role: :manager)
      staff_a = member_fixture(tenant_a, role: :staff)

      announcement_b = announcement_fixture(manager_b)

      assert {:error, :forbidden} = Announcements.get_for_member(staff_a, announcement_b.id)
      # And the reverse direction, for good measure.
      announcement_a = announcement_fixture(manager_a)
      staff_b = member_fixture(tenant_b, role: :staff)
      assert {:error, :forbidden} = Announcements.get_for_member(staff_b, announcement_a.id)
    end

    # Negative case required by testing.md: a deactivated member reading.
    test "a deactivated member cannot fetch an announcement by id (negative, invariant 4)" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)
      announcement = announcement_fixture(manager)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      assert {:error, :forbidden} = Announcements.get_for_member(staff, announcement.id)
    end
  end

  describe "record_views/2 (criterion 3: read once, first time recorded, never changes)" do
    test "recording a view sets read_at on the very first call" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)
      announcement = announcement_fixture(manager)

      assert {:ok, [ack]} = Announcements.record_views(staff, [announcement])
      assert ack.announcement_id == announcement.id
      assert ack.member_id == staff.id
      assert ack.inserted_at

      assert {:ok, [read]} = Announcements.list_for_member(staff)
      assert read.read_at
    end

    test "a second recording of the same announcement is a no-op and the read time never changes" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)
      announcement = announcement_fixture(manager)

      assert {:ok, [_ack]} = Announcements.record_views(staff, [announcement])
      assert {:ok, [first]} = Announcements.list_for_member(staff)
      first_read_at = first.read_at

      # A second sighting writes nothing new.
      assert {:ok, []} = Announcements.record_views(staff, [announcement])

      assert {:ok, [second]} = Announcements.list_for_member(staff)
      assert second.read_at == first_read_at
    end

    test "an announcement not addressed to the actor is ignored rather than acknowledged" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      site_a = site_fixture(tenant)
      site_b = site_fixture(tenant)
      staff = member_fixture(tenant, role: :staff, site_id: site_a.id)
      other_site_announcement = announcement_fixture(manager, site_id: site_b.id)

      assert {:ok, []} = Announcements.record_views(staff, [other_site_announcement])
    end

    # Negative case required by testing.md: a deactivated member reading.
    test "a deactivated member cannot record a view (negative, invariant 4)" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)
      announcement = announcement_fixture(manager)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      assert {:error, :forbidden} = Announcements.record_views(staff, [announcement])
    end
  end

  describe "unread_count/1 (criterion 6 support: an integer that falls on reading, excludes own posts)" do
    test "counts announcements not yet read" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)

      announcement_fixture(manager)
      announcement_fixture(manager)

      assert {:ok, count} = Announcements.unread_count(staff)
      assert count >= 2
    end

    test "falls after the announcement is recorded as read" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)
      announcement = announcement_fixture(manager)

      assert {:ok, before_count} = Announcements.unread_count(staff)
      assert {:ok, [_ack]} = Announcements.record_views(staff, [announcement])
      assert {:ok, after_count} = Announcements.unread_count(staff)

      assert after_count == before_count - 1
    end

    test "never counts the member's own announcements" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)

      assert {:ok, before_count} = Announcements.unread_count(manager)
      announcement_fixture(manager)
      assert {:ok, after_count} = Announcements.unread_count(manager)

      assert after_count == before_count
    end

    # Negative case required by testing.md: a deactivated member reading.
    test "a deactivated member cannot get an unread count (negative, invariant 4)" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      assert {:error, :forbidden} = Announcements.unread_count(staff)
    end
  end

  describe "list_with_read_state/1 (criterion 4: any manager sees audience, read count, unread members)" do
    test "a fresh announcement shows the full audience unread and a read count of zero" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff_1 = member_fixture(tenant, role: :staff)
      staff_2 = member_fixture(tenant, role: :staff)
      announcement = announcement_fixture(manager)

      assert {:ok, states} = Announcements.list_with_read_state(manager)
      state = Enum.find(states, &(&1.announcement.id == announcement.id))

      assert state.read == 0
      # audience is every active member of the tenant minus the author.
      assert state.audience >= 2
      unread_ids = Enum.map(state.unread, & &1.id)
      assert staff_1.id in unread_ids
      assert staff_2.id in unread_ids
    end

    test "the author is never counted in their own announcement's audience" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      announcement = announcement_fixture(manager)

      assert {:ok, states} = Announcements.list_with_read_state(manager)
      state = Enum.find(states, &(&1.announcement.id == announcement.id))

      unread_ids = Enum.map(state.unread, & &1.id)
      refute manager.id in unread_ids
    end

    test "the read count and unread list move as members read" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)
      announcement = announcement_fixture(manager)

      assert {:ok, [_ack]} = Announcements.record_views(staff, [announcement])

      assert {:ok, states} = Announcements.list_with_read_state(manager)
      state = Enum.find(states, &(&1.announcement.id == announcement.id))

      assert state.read == 1
      refute staff.id in Enum.map(state.unread, & &1.id)
    end

    test "a member deactivated after posting drops out of the audience" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)
      announcement = announcement_fixture(manager)

      assert {:ok, before_states} = Announcements.list_with_read_state(manager)
      before_state = Enum.find(before_states, &(&1.announcement.id == announcement.id))
      assert staff.id in Enum.map(before_state.unread, & &1.id)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      assert {:ok, after_states} = Announcements.list_with_read_state(manager)
      after_state = Enum.find(after_states, &(&1.announcement.id == announcement.id))

      refute staff.id in Enum.map(after_state.unread, & &1.id)
      assert after_state.audience == before_state.audience - 1
    end

    test "a member added after posting is counted as not yet read" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      announcement = announcement_fixture(manager)

      assert {:ok, before_states} = Announcements.list_with_read_state(manager)
      before_state = Enum.find(before_states, &(&1.announcement.id == announcement.id))

      late_staff = member_fixture(tenant, role: :staff)

      assert {:ok, after_states} = Announcements.list_with_read_state(manager)
      after_state = Enum.find(after_states, &(&1.announcement.id == announcement.id))

      assert after_state.audience == before_state.audience + 1
      assert late_staff.id in Enum.map(after_state.unread, & &1.id)
    end

    test "the audience of a site announcement is only that site's active members" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      site_a = site_fixture(tenant)
      site_b = site_fixture(tenant)
      in_site = member_fixture(tenant, role: :staff, site_id: site_a.id)
      other_site = member_fixture(tenant, role: :staff, site_id: site_b.id)

      announcement = announcement_fixture(manager, site_id: site_a.id)

      assert {:ok, states} = Announcements.list_with_read_state(manager)
      state = Enum.find(states, &(&1.announcement.id == announcement.id))

      unread_ids = Enum.map(state.unread, & &1.id)
      assert in_site.id in unread_ids
      refute other_site.id in unread_ids
    end

    # Negative case required by testing.md: staff posting/acting — here, reading the audit list.
    test "a staff member cannot see any manager's audit list (negative, criterion 4: 'any manager')" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)
      announcement_fixture(manager)

      assert {:error, :forbidden} = Announcements.list_with_read_state(staff)
    end

    # Negative case required by testing.md: a deactivated member reading.
    test "a deactivated manager cannot see the audit list, even mid-session (negative, invariant 4)" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      other_manager = member_fixture(tenant, role: :manager)
      announcement_fixture(manager)

      assert {:ok, _} = Members.deactivate_member(other_manager, manager)

      assert {:error, :forbidden} = Announcements.list_with_read_state(manager)
    end

    # Negative case required by testing.md: another tenant's member.
    test "a member of another tenant is never counted in the audience or unread list (negative, isolation)" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)
      manager_a = member_fixture(tenant_a, role: :manager)
      member_fixture(tenant_b, role: :staff)

      announcement = announcement_fixture(manager_a)

      assert {:ok, states} = Announcements.list_with_read_state(manager_a)
      state = Enum.find(states, &(&1.announcement.id == announcement.id))

      # Every member counted belongs to tenant_a: nothing here names a member
      # created only in tenant_b, and the audience total is exactly tenant_a's
      # own active member count minus the author.
      assert {:ok, tenant_a_members} = Members.list_members(manager_a, tenant_a)
      active_non_author = Enum.count(tenant_a_members, &(&1.active and &1.id != manager_a.id))

      assert state.audience == active_non_author
    end
  end

  describe "subscribe/1 (support for criteria 5 and 6)" do
    test "an active member can subscribe" do
      tenant = tenant_fixture(:one)
      staff = member_fixture(tenant, role: :staff)

      assert :ok = Announcements.subscribe(staff)
    end

    # Negative case required by testing.md: a deactivated member (here, subscribing).
    test "a deactivated member cannot subscribe (negative, invariant 4)" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      staff = member_fixture(tenant, role: :staff)

      assert {:ok, _} = Members.deactivate_member(manager, staff)

      assert {:error, :forbidden} = Announcements.subscribe(staff)
    end
  end

  describe "criterion 7: an announcement is never edited after publication" do
    test "posting again with an identical body creates a second, independent announcement" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)

      assert {:ok, first} = Announcements.post_announcement(manager, %{body: "Same body"})
      assert {:ok, second} = Announcements.post_announcement(manager, %{body: "Same body"})

      refute first.id == second.id

      staff = member_fixture(tenant, role: :staff)
      assert {:ok, list} = Announcements.list_for_member(staff)
      ids = Enum.map(list, & &1.id)

      assert first.id in ids
      assert second.id in ids
    end
  end
end
