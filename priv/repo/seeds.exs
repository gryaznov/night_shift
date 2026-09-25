# Seeds two businesses, each with two sites, one manager and six staff covering
# every team at both sites, and a few messages in every group.
#
#     mix run priv/repo/seeds.exs
#
# Safe to re-run: every record is found or created, so this does not duplicate
# users, sites or members. Sign-in credentials are printed at the end.

alias NightShift.Accounts
alias NightShift.Chat
alias NightShift.Members
alias NightShift.Tenants

password = "nightshift123!"

businesses = [
  %{name: "North Coast Hotels", schema: "north_coast", sites: ["Seafront", "Old Town"]},
  %{name: "Harbour Taverns", schema: "harbour", sites: ["Quayside", "Market Street"]}
]

slug = fn value ->
  value |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
end

find_or_create_user = fn email ->
  case Accounts.get_user_by_email(email) do
    nil ->
      {:ok, user} = Accounts.register_user(%{email: email, password: password})
      user

    user ->
      user
  end
end

seed_messages = fn group, member ->
  where = if group.team, do: "#{member.team} at #{group.site.name}", else: group.site.name

  [
    "Morning all — handover notes for #{where} are on the board.",
    "Reminder: deliveries land at 10:30 today, someone needs to sign for them."
  ]
end

find_or_create_member = fn tenant, email, attrs ->
  user = find_or_create_user.(email)

  # Blind to `active` on purpose: a seeded member deactivated by hand must stay
  # deactivated, and re-creating one would hit the (user_id, tenant_id) index.
  case Members.get_member(user, tenant) do
    nil ->
      {:ok, member} = Members.create_member(tenant, Map.put(attrs, :user_id, user.id))
      {user, member}

    member ->
      {user, member}
  end
end

credentials =
  for business <- businesses do
    tenant =
      case Tenants.get_tenant_by_schema(business.schema) do
        nil ->
          {:ok, tenant} =
            Tenants.create_tenant(%{name: business.name, schema: business.schema})

          tenant

        tenant ->
          tenant
      end

    existing_sites = Members.list_sites(tenant)

    sites =
      for name <- business.sites do
        case Enum.find(existing_sites, &(&1.name == name)) do
          nil ->
            {:ok, site} = Members.create_site(tenant, %{name: name})
            site

          site ->
            site
        end
      end

    [first_site | _] = sites
    tenant_slug = slug.(business.schema)

    # One manager per tenant, as criterion 6 states. The second site therefore has
    # no manager of its own, and this tenant's only manager cannot be deactivated
    # through the product — criterion 4 refuses the last active manager.
    {manager_user, manager_member} =
      find_or_create_member.(
        tenant,
        "manager@#{tenant_slug}.test",
        %{site_id: first_site.id, team: :front_of_house, role: :manager}
      )

    staff_members =
      for site <- sites, team <- Members.Member.teams() do
        email = "#{slug.(to_string(team))}.#{slug.(site.name)}@#{tenant_slug}.test"

        {user, member} =
          find_or_create_member.(tenant, email, %{site_id: site.id, team: team, role: :staff})

        {{site.id, team}, {user, member}}
      end

    staff =
      for {{_site_id, team}, {user, member}} <- staff_members do
        site = Enum.find(sites, &(&1.id == member.site_id))
        {user.email, site.name, team, :staff}
      end

    # A few messages per group, so a seeded sign-in lands on something to read.
    by_site_team = Map.new(staff_members, fn {key, {_user, member}} -> {key, member} end)
    all_members = [manager_member | Map.values(by_site_team)]

    # Every member's first sight of their groups happens here, before a single
    # message exists. Ruling 3 seeds a member's read cursor to the newest message
    # the first time they see a group, so posting first would leave every count at
    # zero and no unread badge would ever appear in a seeded database.
    for member <- all_members do
      {:ok, _groups} = Chat.list_groups(member)
    end

    for site <- sites do
      site_members =
        for team <- Members.Member.teams(), do: Map.fetch!(by_site_team, {site.id, team})

      for member <- site_members do
        {:ok, groups} = Chat.list_groups(member)

        for group <- groups do
          # Idempotent: a group that already carries its seeded messages is left
          # exactly as it is, including anything written by hand since.
          case Chat.list_messages(member, group) do
            {:ok, []} ->
              for body <- seed_messages.(group, member) do
                {:ok, _message} = Chat.post_message(member, group, %{body: body})
              end

            {:ok, _existing} ->
              :ok
          end
        end
      end
    end

    {business.name, [{manager_user.email, first_site.name, :front_of_house, :manager} | staff]}
  end

IO.puts("\nSign-in credentials — password for every account: #{password}\n")

for {business, people} <- credentials do
  IO.puts(business)

  for {email, site, team, role} <- people do
    IO.puts("  #{String.pad_trailing(email, 40)} #{role} · #{site} · #{team}")
  end

  IO.puts("")
end
