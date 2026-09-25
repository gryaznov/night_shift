defmodule NightShiftWeb.TenantAuth do
  @moduledoc """
  Resolves the tenant and the acting member, once, from the authenticated
  session — `on_mount/4` for LiveViews, `require_active_member/2` for
  controller routes. 0001 routes nothing through the plug; it exists so a
  controller route added later cannot end up with no membership gate.

  Nothing downstream re-derives either, and neither is ever read from a param, a
  path segment or a client event — there is no tenant in any route.

  Runs after `NightShiftWeb.UserAuth`'s `:ensure_authenticated`, so
  `:current_user` is already assigned.
  """

  use NightShiftWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]

  alias NightShift.Announcements
  alias NightShift.Members
  alias NightShift.Tenancy

  @doc """
  `on_mount` hook assigning `:tenant`, `:current_member` and
  `:unread_announcements`.

  Halts to the no-access page when the user has no active member record, which
  covers both a user who never had one and a member deactivated since.

  A connected view also subscribes to its tenant's member topic, so a member
  deactivated while their page is open is sent to the no-access page there and
  then, rather than at their next request.

  It subscribes to the announcements topic for the same reason the member topic
  is handled here rather than in each LiveView: the unread counter is on every
  tenant page (criterion 6 of 0003), so a page added later cannot forget to keep
  it current. It does so through `NightShift.Announcements.subscribe/1`, which
  authorizes and builds the topic from the re-read member, so no topic is
  constructed here. The hook recomputes the count and then lets the message
  through, so the announcements page still receives it.

  0001 ships no tenant chooser and seeds give each user one membership; a user
  holding several acts in the first, which `## Out of scope` leaves undefined.
  """
  def on_mount(:require_active_member, _params, _session, socket) do
    case Members.list_active_members(socket.assigns.current_user) do
      [member | _rest] ->
        socket =
          socket
          |> assign(:current_member, member)
          |> assign(:tenant, member.tenant)
          |> assign_unread_announcements()

        if Phoenix.LiveView.connected?(socket) do
          Phoenix.PubSub.subscribe(NightShift.PubSub, Tenancy.topic(member.tenant, :members))
          Announcements.subscribe(member)
        end

        {:cont,
         Phoenix.LiveView.attach_hook(
           socket,
           :tenant_events,
           :handle_info,
           &handle_tenant_event/2
         )}

      [] ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/no-access")}
    end
  end

  @doc """
  Plug assigning `:tenant` and `:current_member`, the controller counterpart of
  the `on_mount` hook.

  Redirects to the no-access page and halts when the user has no active member
  record. It cannot disconnect anything mid-request, so a member deactivated
  after this plug ran is stopped by the context, which re-reads liveness where
  it acts.

  Runs after `NightShiftWeb.UserAuth`'s `:require_authenticated_user`.
  """
  def require_active_member(conn, _opts) do
    case Members.list_active_members(conn.assigns.current_user) do
      [member | _rest] ->
        conn
        |> Plug.Conn.assign(:current_member, member)
        |> Plug.Conn.assign(:tenant, member.tenant)

      [] ->
        conn
        |> Phoenix.Controller.redirect(to: ~p"/no-access")
        |> Plug.Conn.halt()
    end
  end

  # Enforced here rather than in each LiveView, so no tenant view can forget it.
  defp handle_tenant_event({:member_deactivated, member_id}, socket) do
    if member_id == socket.assigns.current_member.id do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/no-access")}
    else
      {:halt, socket}
    end
  end

  # `:cont`, not `:halt`: the announcements page needs this message too.
  defp handle_tenant_event({event, _id}, socket)
       when event in [:announcement_posted, :announcement_read] do
    {:cont, assign_unread_announcements(socket)}
  end

  defp handle_tenant_event(_message, socket), do: {:cont, socket}

  # A member deactivated between the mount and this call has no count to show;
  # the next thing they do is refused anyway, and the member topic is already
  # sending them to the no-access page.
  defp assign_unread_announcements(socket) do
    case Announcements.unread_count(socket.assigns.current_member) do
      {:ok, count} -> assign(socket, :unread_announcements, count)
      {:error, :forbidden} -> assign(socket, :unread_announcements, 0)
    end
  end
end
