defmodule NightShiftWeb.NoAccessLive do
  @moduledoc """
  Shown to a signed-in user with no active member record in any tenant.

  Renders nothing about any tenant: a deactivated member must not learn anything
  further about the business they worked for.
  """

  use NightShiftWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm px-4 py-16 text-center">
      <h1 class="text-xl font-semibold text-zinc-900">No access</h1>

      <p data-test-id="no-access-message" class="mt-4 text-sm leading-6 text-zinc-600">
        Your account has no active access. If you think this is wrong, ask your manager.
      </p>

      <.link
        href={~p"/users/log_out"}
        method="delete"
        data-test-id="no-access-log-out"
        class="mt-8 inline-block text-sm font-semibold text-zinc-700 hover:text-zinc-900"
      >
        Log out
      </.link>
    </div>
    """
  end
end
