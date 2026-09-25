# Seeds two businesses, each with two sites, one manager and six staff covering
# every team at both sites.
#
#     mix run priv/repo/seeds.exs
#
# Safe to re-run: every record is found or created, so this does not duplicate
# users, sites or members. Sign-in credentials are printed at the end.

alias NightShift.Accounts
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
    {manager, _} =
      find_or_create_member.(
        tenant,
        "manager@#{tenant_slug}.test",
        %{site_id: first_site.id, team: :front_of_house, role: :manager}
      )

    staff =
      for site <- sites, team <- Members.Member.teams() do
        email = "#{slug.(to_string(team))}.#{slug.(site.name)}@#{tenant_slug}.test"

        {user, _member} =
          find_or_create_member.(tenant, email, %{site_id: site.id, team: team, role: :staff})

        {user.email, site.name, team, :staff}
      end

    {business.name, [{manager.email, first_site.name, :front_of_house, :manager} | staff]}
  end

IO.puts("\nSign-in credentials — password for every account: #{password}\n")

for {business, people} <- credentials do
  IO.puts(business)

  for {email, site, team, role} <- people do
    IO.puts("  #{String.pad_trailing(email, 40)} #{role} · #{site} · #{team}")
  end

  IO.puts("")
end
