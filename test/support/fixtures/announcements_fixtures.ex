defmodule NightShift.AnnouncementsFixtures do
  @moduledoc """
  Test helpers for announcements, via `NightShift.Announcements`.

  `author` must be an active manager — `Announcements.post_announcement/2`
  refuses anyone else, so an invalid fixture call fails loudly rather than
  silently handing back something that isn't an announcement.
  """

  alias NightShift.Announcements

  @doc """
  Publishes an announcement authored by `author`.

  Defaults to a tenant-wide announcement with a unique body. Pass
  `site_id: site.id` to target one site.
  """
  def announcement_fixture(author, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{body: "Announcement #{System.unique_integer([:positive])}"})

    {:ok, announcement} = Announcements.post_announcement(author, attrs)
    announcement
  end
end
