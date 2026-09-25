defmodule NightShiftWeb.ChatLive do
  @moduledoc """
  The member's groups: their site's group and their site-and-team group, with an
  unread count on each.

  Nobody manages that list. `NightShift.Chat.list_groups/1` derives it from the
  member record on every mount, which is why a member moved to another site sees
  the new groups here with no further action.

  `:tenant` and `:current_member` come from `NightShiftWeb.TenantAuth`; this view
  resolves neither and decides no permissions.
  """

  use NightShiftWeb, :live_view

  alias NightShift.Chat
  alias NightShift.Chat.Group

  @impl true
  def mount(_params, _session, socket) do
    case Chat.list_groups(socket.assigns.current_member) do
      {:ok, groups} ->
        if connected?(socket),
          do: Enum.each(groups, &Chat.subscribe(socket.assigns.current_member, &1))

        {:ok, assign(socket, :groups, groups)}

      {:error, :forbidden} ->
        {:ok, redirect(socket, to: ~p"/no-access")}
    end
  end

  # A message posted in either group changes its unread count. The counts are
  # re-derived rather than incremented: `Chat` decides what counts as unread,
  # not this view.
  @impl true
  def handle_info({:message_posted, _message}, socket) do
    case Chat.list_groups(socket.assigns.current_member) do
      {:ok, groups} -> {:noreply, assign(socket, :groups, groups)}
      {:error, :forbidden} -> {:noreply, redirect(socket, to: ~p"/no-access")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-6">
      <h1 class="text-xl font-semibold text-zinc-900">Chat</h1>

      <ul data-test-id="chat-groups" class="mt-4 divide-y divide-zinc-100">
        <li :for={group <- @groups} class="py-1">
          <.link
            navigate={~p"/chat/#{group.id}"}
            data-test-id={"group-#{group.id}"}
            class="flex items-center justify-between gap-3 rounded-lg px-3 py-3 hover:bg-zinc-50"
          >
            <span class="text-base font-medium text-zinc-900">{Group.display_name(group)}</span>

            <span
              :if={group.unread_count > 0}
              data-test-id={"group-unread-#{group.id}"}
              class="min-w-6 rounded-full bg-zinc-900 px-2 py-0.5 text-center text-xs font-semibold text-white"
            >
              {group.unread_count}
            </span>
          </.link>
        </li>
      </ul>
    </div>
    """
  end
end
