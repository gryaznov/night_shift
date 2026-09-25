defmodule NightShiftWeb.WorkspaceLive do
  @moduledoc """
  The tenant workspace landing page.

  `:tenant` and `:current_member` come from `NightShiftWeb.TenantAuth`; this
  view resolves neither and decides no permissions.
  """

  use NightShiftWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="px-4 py-8">
      <h1 data-test-id="workspace-tenant-name" class="text-xl font-semibold text-zinc-900">
        {@tenant.name}
      </h1>
    </div>
    """
  end
end
