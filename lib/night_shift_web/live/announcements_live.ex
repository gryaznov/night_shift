defmodule NightShiftWeb.AnnouncementsLive do
  @moduledoc """
  The announcements page: what is addressed to this member, and — for a manager
  — who has read what.

  `:tenant` and `:current_member` come from `NightShiftWeb.TenantAuth`. Every
  decision is the context's: this view never asks who may post or who may read
  an announcement, and an announcement arriving on the topic is re-fetched
  through `NightShift.Announcements.get_for_member/2` rather than trusted from
  the broadcast.

  Reading is implicit. Announcements are recorded as read when they are put on
  screen — at mount, and again as each one arrives — so an open page stays at
  zero unread. `record_views/2` is idempotent, so the repeat costs a query and
  writes nothing.

  Whether the compose form is rendered follows `role`, which is presentation,
  not permission: a staff member who posts anyway is refused by
  `post_announcement/2`.
  """

  use NightShiftWeb, :live_view

  alias NightShift.Announcements
  alias NightShift.Members

  @impl true
  def mount(_params, _session, socket) do
    member = socket.assigns.current_member

    case Announcements.list_for_member(member) do
      {:ok, announcements} ->
        Announcements.record_views(member, announcements)

        {:ok,
         socket
         |> assign(:manager?, member.role == :manager)
         |> assign(:sites, Members.list_sites(socket.assigns.tenant))
         |> assign(:form, blank_form())
         |> assign(:error, nil)
         |> assign_read_state()
         |> stream(:announcements, announcements)}

      {:error, :forbidden} ->
        {:ok, redirect(socket, to: ~p"/no-access")}
    end
  end

  @impl true
  def handle_event("post", %{"announcement" => params}, socket) do
    case Announcements.post_announcement(socket.assigns.current_member, params) do
      {:ok, _announcement} ->
        # The author is not in their own audience, so nothing arrives in the
        # stream. Refresh the read state here rather than waiting for the
        # broadcast to come back, or a manager's own announcement is missing
        # from the page for as long as the round trip takes.
        {:noreply,
         socket
         |> assign(:form, blank_form())
         |> assign(:error, nil)
         |> assign_read_state()}

      {:error, :forbidden} ->
        {:noreply, redirect(socket, to: ~p"/no-access")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(params, as: :announcement))
         |> assign(:error, error_message(changeset))}
    end
  end

  @impl true
  def handle_info({:announcement_posted, id}, socket) do
    member = socket.assigns.current_member

    socket =
      case Announcements.get_for_member(member, id) do
        {:ok, announcement} ->
          # It is on screen from here, so it has been read.
          Announcements.record_views(member, [announcement])
          stream_insert(socket, :announcements, announcement, at: 0)

        {:error, :forbidden} ->
          socket
      end

    {:noreply, assign_read_state(socket)}
  end

  def handle_info({:announcement_read, _id}, socket) do
    {:noreply, assign_read_state(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-8">
      <h1 class="text-xl font-semibold text-zinc-900">Announcements</h1>

      <.simple_form
        :if={@manager?}
        for={@form}
        id="announcement-form"
        data-test-id="announcement-form"
        phx-submit="post"
      >
        <.input field={@form[:body]} type="textarea" label="Announcement" />
        <.input
          field={@form[:site_id]}
          type="select"
          label="Send to"
          options={[{"Everyone", ""} | Enum.map(@sites, &{&1.name, &1.id})]}
        />
        <:actions>
          <.button phx-disable-with="Publishing...">Publish</.button>
        </:actions>
      </.simple_form>

      <p
        :if={@error}
        data-test-id="announcement-error"
        class="mt-2 text-sm font-medium leading-6 text-rose-600"
      >
        {@error}
      </p>

      <div id="announcements" data-test-id="announcements" phx-update="stream" class="mt-8 space-y-4">
        <article
          :for={{dom_id, announcement} <- @streams.announcements}
          id={dom_id}
          data-test-id={"announcement-#{announcement.id}"}
          class="rounded-xl border border-zinc-200 bg-white p-4"
        >
          <p class="whitespace-pre-line text-sm leading-6 text-zinc-900">{announcement.body}</p>
          <p class="mt-2 text-xs leading-5 text-zinc-500">
            {announcement.author_name}
            <span :if={announcement.site_id}>· your site</span>
          </p>
        </article>
      </div>

      <section :if={@manager?} data-test-id="read-state" class="mt-10">
        <h2 class="text-sm font-semibold text-zinc-900">Who has read what</h2>

        <div :for={state <- @read_state} class="mt-4 rounded-xl border border-zinc-200 bg-white p-4">
          <p class="truncate text-sm leading-6 text-zinc-900">{state.announcement.body}</p>

          <p class="mt-1 text-xs leading-5 text-zinc-500">
            <span data-test-id={"read-count-#{state.announcement.id}"}>
              {state.read}/{state.audience}
            </span>
            read
          </p>

          <ul
            :if={state.unread != []}
            data-test-id={"unread-members-#{state.announcement.id}"}
            class="mt-2 space-y-1 text-xs leading-5 text-zinc-700"
          >
            <li :for={member <- state.unread}>{member.user.email}</li>
          </ul>
        </div>
      </section>
    </div>
    """
  end

  defp assign_read_state(socket) do
    case Announcements.list_with_read_state(socket.assigns.current_member) do
      {:ok, read_state} -> assign(socket, :read_state, read_state)
      {:error, :forbidden} -> assign(socket, :read_state, [])
    end
  end

  defp blank_form, do: to_form(%{"body" => "", "site_id" => ""}, as: :announcement)

  defp error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end
end
