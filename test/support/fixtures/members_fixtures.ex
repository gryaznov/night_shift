defmodule NightShift.MembersFixtures do
  @moduledoc """
  Test helpers for sites and members.
  """

  import NightShift.AccountsFixtures, only: [user_fixture: 0]

  alias NightShift.Members

  def site_fixture(tenant, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    {:ok, site} =
      Members.create_site(
        tenant,
        Map.put_new_lazy(attrs, :name, fn -> "Site #{System.unique_integer([:positive])}" end)
      )

    site
  end

  def member_fixture(tenant, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    attrs =
      attrs
      |> Map.put_new_lazy(:user_id, fn -> user_fixture().id end)
      |> Map.put_new_lazy(:site_id, fn -> site_fixture(tenant).id end)
      |> Map.put_new(:team, :kitchen)
      |> Map.put_new(:role, :staff)

    {:ok, member} = Members.create_member(tenant, attrs)
    member
  end
end
