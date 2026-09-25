defmodule NightShift.ChatTest do
  # Tenant fixtures come from the two schemas `test_helper.exs` provisions;
  # tests touching them run `async: false` per .claude/rules/testing.md.
  use NightShift.DataCase, async: false

  import NightShift.ChatFixtures
  import NightShift.MembersFixtures
  import NightShift.TenantsFixtures

  alias NightShift.Chat
  alias NightShift.Chat.Message
  alias NightShift.Members

  describe "list_groups/1 (criterion 1: exactly the site group and the site-and-team group, nothing else)" do
    test "returns exactly the actor's site group and site-and-team group, and no other group" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      {_other_site, other_groups} = site_with_groups_fixture(tenant)

      member = member_fixture(tenant, site_id: site.id, team: :kitchen)

      assert {:ok, result} = Chat.list_groups(member)

      expected_ids =
        MapSet.new([site_group(groups).id, team_group(groups, :kitchen).id])

      result_ids = result |> Enum.map(& &1.id) |> MapSet.new()

      assert result_ids == expected_ids

      # Explicitly not the other teams at the member's own site, and not
      # anything belonging to another site in the same tenant.
      refute team_group(groups, :front_of_house).id in result_ids
      refute team_group(groups, :bar).id in result_ids
      refute site_group(other_groups).id in result_ids
    end
  end

  describe "list_groups/1 and list_messages/2 together (criterion 2: a newly added member sees groups and messages with no further action)" do
    test "a new member sees their two groups and the existing messages in each immediately" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)

      founder = member_fixture(tenant, site_id: site.id, team: :kitchen)
      msg1 = message_fixture(founder, team_group, body: "first")
      msg2 = message_fixture(founder, team_group, body: "second")

      newcomer = member_fixture(tenant, site_id: site.id, team: :kitchen)

      assert {:ok, result_groups} = Chat.list_groups(newcomer)
      result_ids = Enum.map(result_groups, & &1.id)
      assert team_group.id in result_ids
      assert site_group(groups).id in result_ids

      assert {:ok, messages} = Chat.list_messages(newcomer, team_group)
      assert Enum.map(messages, & &1.id) == [msg1.id, msg2.id]
    end
  end

  describe "list_groups/1 reflects update_assignment/3 (criterion 3; ruling 6: re-reads, no ejection)" do
    test "after a manager moves a member, list_groups called with the pre-move struct returns the new groups, not the old" do
      tenant = tenant_fixture(:one)
      {old_site, old_groups} = site_with_groups_fixture(tenant)
      {new_site, new_groups} = site_with_groups_fixture(tenant)

      manager = member_fixture(tenant, site_id: old_site.id, role: :manager)
      moved = member_fixture(tenant, site_id: old_site.id, team: :kitchen)

      assert {:ok, _updated} =
               Members.update_assignment(manager, moved, %{site_id: new_site.id, team: :bar})

      # `moved` is the struct as loaded before the move: ruling 6 says the
      # session is not ejected, so the very next call re-reads and reflects
      # the new assignment.
      assert {:ok, result} = Chat.list_groups(moved)
      result_ids = result |> Enum.map(& &1.id) |> MapSet.new()

      assert result_ids ==
               MapSet.new([site_group(new_groups).id, team_group(new_groups, :bar).id])

      refute team_group(old_groups, :kitchen).id in result_ids
      refute site_group(old_groups).id in result_ids
    end

    test "the moved member can no longer read the old team's group" do
      tenant = tenant_fixture(:one)
      {old_site, old_groups} = site_with_groups_fixture(tenant)
      {new_site, _new_groups} = site_with_groups_fixture(tenant)

      manager = member_fixture(tenant, site_id: old_site.id, role: :manager)
      moved = member_fixture(tenant, site_id: old_site.id, team: :kitchen)
      old_team_group = team_group(old_groups, :kitchen)

      assert {:ok, _updated} =
               Members.update_assignment(manager, moved, %{site_id: new_site.id, team: :bar})

      assert {:error, :forbidden} = Chat.get_group(moved, old_team_group.id)
      assert {:error, :forbidden} = Chat.list_messages(moved, old_team_group)
    end
  end

  describe "list_messages/2 (ruling 8: newest 200 messages, oldest first, no way to page back further)" do
    test "returns at most the newest 200 messages, ordered oldest first" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)

      messages =
        for n <- 1..205 do
          message_fixture(member, team_group, body: "message #{n}")
        end

      assert {:ok, result} = Chat.list_messages(member, team_group)
      assert length(result) == 200

      # The newest 200 of 205 posted messages: the first 5 fall out, the rest
      # are returned oldest first (ruling 8).
      expected_ids = messages |> Enum.slice(5, 200) |> Enum.map(& &1.id)
      assert Enum.map(result, & &1.id) == expected_ids
    end
  end

  describe "post_message/3 validation (criterion 6, ruling 4: trimmed, then measured in graphemes, 1..2000)" do
    setup do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)
      %{member: member, group: team_group}
    end

    test "rejects an empty body", %{member: member, group: group} do
      assert {:error, changeset} = Chat.post_message(member, group, %{body: ""})
      assert "can't be blank — write a message" in errors_on(changeset).body
    end

    test "rejects a whitespace-only body (trimmed before the check)", %{
      member: member,
      group: group
    } do
      assert {:error, changeset} = Chat.post_message(member, group, %{body: "   \n\t  "})
      assert "can't be blank — write a message" in errors_on(changeset).body
    end

    test "accepts a 1-character body (lower boundary)", %{member: member, group: group} do
      assert {:ok, message} = Chat.post_message(member, group, %{body: "a"})
      assert message.body == "a"
    end

    test "accepts a body of exactly the maximum length (upper boundary)", %{
      member: member,
      group: group
    } do
      body = String.duplicate("a", Message.max_length())
      assert {:ok, message} = Chat.post_message(member, group, %{body: body})
      assert message.body == body
    end

    test "rejects a body one grapheme over the maximum length", %{member: member, group: group} do
      body = String.duplicate("a", Message.max_length() + 1)
      assert {:error, changeset} = Chat.post_message(member, group, %{body: body})

      assert "is too long — keep it under #{Message.max_length()} characters" in errors_on(
               changeset
             ).body
    end

    test "accepts a body whose content is exactly at the limit once surrounding whitespace is trimmed",
         %{member: member, group: group} do
      body = "  " <> String.duplicate("a", Message.max_length()) <> "  "
      assert {:ok, message} = Chat.post_message(member, group, %{body: body})
      assert message.body == String.duplicate("a", Message.max_length())
    end

    test "measures length in graphemes, not codepoints: a multi-codepoint grapheme cluster counts once",
         %{member: member, group: group} do
      # "e" + combining acute accent (U+0301) is one grapheme, two codepoints.
      combining_e = "e" <> <<0x0301::utf8>>
      body = String.duplicate(combining_e, Message.max_length())

      assert String.length(body) == Message.max_length()
      assert String.length(body) < byte_size(body)

      assert {:ok, message} = Chat.post_message(member, group, %{body: body})
      assert message.body == body
    end

    test "rejects a body one grapheme cluster over the maximum length even though byte length is far larger",
         %{member: member, group: group} do
      combining_e = "e" <> <<0x0301::utf8>>
      body = String.duplicate(combining_e, Message.max_length() + 1)

      assert {:error, changeset} = Chat.post_message(member, group, %{body: body})

      assert "is too long — keep it under #{Message.max_length()} characters" in errors_on(
               changeset
             ).body
    end
  end

  describe "authorization — reading a group (criterion 5: a member cannot read a group they do not belong to)" do
    test "get_group/2 refuses a group id belonging to another tenant" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)
      member_a = member_fixture(tenant_a)
      {_site_b, groups_b} = site_with_groups_fixture(tenant_b)

      assert {:error, :forbidden} = Chat.get_group(member_a, site_group(groups_b).id)
    end

    test "get_group/2 refuses another site's group in the same tenant" do
      tenant = tenant_fixture(:one)
      {site_a, _groups_a} = site_with_groups_fixture(tenant)
      {_site_b, groups_b} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site_a.id, team: :kitchen)

      assert {:error, :forbidden} = Chat.get_group(member, site_group(groups_b).id)
    end

    test "get_group/2 refuses another team's group at the member's own site" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)

      assert {:error, :forbidden} = Chat.get_group(member, team_group(groups, :bar).id)
    end

    test "get_group/2 refuses a nonexistent group id" do
      tenant = tenant_fixture(:one)
      member = member_fixture(tenant)

      assert {:error, :forbidden} = Chat.get_group(member, Ecto.UUID.generate())
    end

    test "list_messages/2 refuses another tenant's group" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)
      member_a = member_fixture(tenant_a)
      {_site_b, groups_b} = site_with_groups_fixture(tenant_b)

      assert {:error, :forbidden} = Chat.list_messages(member_a, site_group(groups_b))
    end

    test "list_messages/2 refuses another site's group in the same tenant" do
      tenant = tenant_fixture(:one)
      {site_a, _groups_a} = site_with_groups_fixture(tenant)
      {_site_b, groups_b} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site_a.id, team: :kitchen)

      assert {:error, :forbidden} = Chat.list_messages(member, site_group(groups_b))
    end

    test "list_messages/2 refuses another team's group at the member's own site" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)

      assert {:error, :forbidden} =
               Chat.list_messages(member, team_group(groups, :front_of_house))
    end

    test "a deactivated member can no longer read (get_group and list_messages both refuse)" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      {site, groups} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)
      team_group = team_group(groups, :kitchen)

      assert {:ok, _} = Members.deactivate_member(manager, member)

      assert {:error, :forbidden} = Chat.get_group(member, team_group.id)
      assert {:error, :forbidden} = Chat.list_messages(member, team_group)
    end
  end

  describe "authorization — posting a message (criterion 5: a member cannot post to a group they do not belong to)" do
    test "post_message/3 refuses another tenant's group" do
      tenant_a = tenant_fixture(:one)
      tenant_b = tenant_fixture(:two)
      member_a = member_fixture(tenant_a)
      {_site_b, groups_b} = site_with_groups_fixture(tenant_b)

      assert {:error, :forbidden} =
               Chat.post_message(member_a, site_group(groups_b), %{body: "hi"})
    end

    test "post_message/3 refuses another site's group in the same tenant" do
      tenant = tenant_fixture(:one)
      {site_a, _groups_a} = site_with_groups_fixture(tenant)
      {_site_b, groups_b} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site_a.id, team: :kitchen)

      assert {:error, :forbidden} =
               Chat.post_message(member, site_group(groups_b), %{body: "hi"})
    end

    test "post_message/3 refuses another team's group at the member's own site" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)

      assert {:error, :forbidden} =
               Chat.post_message(member, team_group(groups, :bar), %{body: "hi"})
    end

    test "a deactivated member can no longer post" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      {site, groups} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)
      team_group = team_group(groups, :kitchen)

      assert {:ok, _} = Members.deactivate_member(manager, member)

      assert {:error, :forbidden} = Chat.post_message(member, team_group, %{body: "hi"})
    end
  end

  describe "subscribe/2 authorization (criterion 5, criterion 4's precondition: a view cannot subscribe to a group it may not read)" do
    test "refuses a group the member does not belong to" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)

      assert {:error, :forbidden} = Chat.subscribe(member, team_group(groups, :bar))
    end

    test "refuses once the member is deactivated" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      {site, groups} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)
      team_group = team_group(groups, :kitchen)

      assert {:ok, _} = Members.deactivate_member(manager, member)

      assert {:error, :forbidden} = Chat.subscribe(member, team_group)
    end
  end

  describe "unread_count/2 and mark_read/2 (criterion 7: unread count per group, cleared on open)" do
    test "a new member's unread count is zero even though the group already has messages (ruling 3)" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)

      founder = member_fixture(tenant, site_id: site.id, team: :kitchen)
      message_fixture(founder, team_group, body: "history before the new hire")
      message_fixture(founder, team_group, body: "more history")

      newcomer = member_fixture(tenant, site_id: site.id, team: :kitchen)

      # First sight, per `list_groups/1`'s doc, seeds the cursor.
      assert {:ok, _groups} = Chat.list_groups(newcomer)
      assert {:ok, 0} = Chat.unread_count(newcomer, team_group)
    end

    test "a member's own messages never count as unread (ruling 5)" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)

      assert {:ok, _} = Chat.list_groups(member)

      message_fixture(member, team_group, body: "my own message")
      message_fixture(member, team_group, body: "my own second message")

      assert {:ok, 0} = Chat.unread_count(member, team_group)
    end

    test "unread count reflects other members' messages, and mark_read clears it to zero" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      team_group = team_group(groups, :kitchen)

      author = member_fixture(tenant, site_id: site.id, team: :kitchen)
      reader = member_fixture(tenant, site_id: site.id, team: :kitchen)

      # Reader's first sight, before the unread messages exist.
      assert {:ok, _} = Chat.list_groups(reader)

      message_fixture(author, team_group, body: "one")
      message_fixture(author, team_group, body: "two")
      message_fixture(author, team_group, body: "three")

      assert {:ok, 3} = Chat.unread_count(reader, team_group)

      assert :ok = Chat.mark_read(reader, team_group)

      assert {:ok, 0} = Chat.unread_count(reader, team_group)
    end

    test "unread_count/2 refuses a group the member does not belong to" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)

      assert {:error, :forbidden} = Chat.unread_count(member, team_group(groups, :bar))
    end

    test "mark_read/2 refuses a group the member does not belong to" do
      tenant = tenant_fixture(:one)
      {site, groups} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)

      assert {:error, :forbidden} = Chat.mark_read(member, team_group(groups, :bar))
    end

    test "unread_count/2 and mark_read/2 refuse a deactivated member" do
      tenant = tenant_fixture(:one)
      manager = member_fixture(tenant, role: :manager)
      {site, groups} = site_with_groups_fixture(tenant)
      member = member_fixture(tenant, site_id: site.id, team: :kitchen)
      team_group = team_group(groups, :kitchen)

      assert {:ok, _} = Members.deactivate_member(manager, member)

      assert {:error, :forbidden} = Chat.unread_count(member, team_group)
      assert {:error, :forbidden} = Chat.mark_read(member, team_group)
    end
  end
end
