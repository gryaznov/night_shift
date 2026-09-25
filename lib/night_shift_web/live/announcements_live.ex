defmodule NightShiftWeb.AnnouncementsLive do
  @moduledoc """
  Placeholder reserving the announcements route and its navigation entry. Plan
  0003 replaces it.
  """

  use NightShiftWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="px-4 py-8">
      <h1 class="text-xl font-semibold text-zinc-900">Announcements</h1>

      <p data-test-id="announcements-placeholder" class="mt-4 text-sm leading-6 text-zinc-600">
        Announcements needing your acknowledgement will appear here.
      </p>
    </div>
    """
  end
end
