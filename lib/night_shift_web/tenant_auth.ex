defmodule NightShiftWeb.TenantAuth do
  @moduledoc """
  Resolves the tenant and the acting member, once, from the authenticated
  session.

  Nothing downstream re-derives either, and neither is ever read from a param, a
  path segment or a client event — there is no tenant in any route.

  Runs after `NightShiftWeb.UserAuth`'s `:ensure_authenticated`, so
  `:current_user` is already assigned.
  """

  use NightShiftWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]

  alias NightShift.Members
  alias NightShift.Tenancy

  @doc """
  `on_mount` hook assigning `:tenant` and `:current_member`.

  Halts to the no-access page when the user has no active member record, which
  covers both a user who never had one and a member deactivated since.

  A connected view also subscribes to its tenant's member topic, so a member
  deactivated while their page is open is sent to the no-access page there and
  then, rather than at their next request.

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

        if Phoenix.LiveView.connected?(socket) do
          Phoenix.PubSub.subscribe(NightShift.PubSub, Tenancy.topic(member.tenant, :members))
        end

        {:cont,
         Phoenix.LiveView.attach_hook(
           socket,
           :member_deactivated,
           :handle_info,
           &handle_member_event/2
         )}

      [] ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/no-access")}
    end
  end

  # Enforced here rather than in each LiveView, so no tenant view can forget it.
  defp handle_member_event({:member_deactivated, member_id}, socket) do
    if member_id == socket.assigns.current_member.id do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/no-access")}
    else
      {:halt, socket}
    end
  end

  defp handle_member_event(_message, socket), do: {:cont, socket}
end
