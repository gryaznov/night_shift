defmodule NightShiftWeb.ChatLive do
  @moduledoc """
  Placeholder reserving the chat route and its navigation entry. Plan 0002
  replaces it.
  """

  use NightShiftWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="px-4 py-8">
      <h1 class="text-xl font-semibold text-zinc-900">Chat</h1>

      <p data-test-id="chat-placeholder" class="mt-4 text-sm leading-6 text-zinc-600">
        Your site and team groups will appear here.
      </p>
    </div>
    """
  end
end
