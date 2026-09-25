defmodule NightShiftWeb.GroupLive do
  @moduledoc """
  One group: its history, a composer, and messages arriving live.

  Every decision belongs to `NightShift.Chat` — whether this member may see the
  group at all, whether a body is acceptable, and which topic to subscribe to.
  A group id from the path is never trusted: `Chat.get_group/2` is what turns it
  into a group, and it refuses another tenant's id, another site's and another
  team's identically, so nothing here reveals whether an id exists.

  Opening the group marks it read, and so does every message that arrives while
  it is open, so a group being looked at never shows an unread count.
  """

  use NightShiftWeb, :live_view

  alias NightShift.Chat
  alias NightShift.Chat.Group

  @impl true
  def mount(%{"id" => group_id}, _session, socket) do
    member = socket.assigns.current_member

    case Chat.get_group(member, group_id) do
      {:ok, group} ->
        {:ok, messages} = Chat.list_messages(member, group)

        if connected?(socket) do
          Chat.subscribe(member, group)
          Chat.mark_read(member, group)
        end

        {:ok,
         socket
         |> assign(:group, group)
         |> assign(:error, nil)
         |> assign(:form, message_form())
         |> stream(:messages, messages)}

      {:error, :forbidden} ->
        {:ok,
         socket
         |> put_flash(:error, "That group is not available.")
         |> redirect(to: ~p"/chat")}
    end
  end

  @impl true
  def handle_event("send", %{"message" => params}, socket) do
    member = socket.assigns.current_member
    group = socket.assigns.group

    case Chat.post_message(member, group, params) do
      {:ok, message} ->
        {:noreply,
         socket
         |> assign(:error, nil)
         |> assign(:form, message_form())
         |> stream_insert(:messages, message)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:error, first_error(changeset))
         |> assign(:form, message_form(params))}

      # The member was moved or deactivated after this view mounted. Ruling 6
      # keeps the view alive; the context is what refuses the post.
      {:error, :forbidden} ->
        {:noreply, assign(socket, :error, "You can no longer post to this group.")}
    end
  end

  # Arrives for every member viewing the group, the sender included. Inserting
  # by the message's own id makes the sender's local insert and this one the
  # same row rather than two.
  @impl true
  def handle_info({:message_posted, message}, socket) do
    Chat.mark_read(socket.assigns.current_member, socket.assigns.group)

    {:noreply, stream_insert(socket, :messages, message)}
  end

  defp message_form(params \\ %{"body" => ""}), do: to_form(params, as: :message)

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Map.get(:body, [])
    |> List.first()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-[calc(100vh-4rem)] flex-col">
      <header class="border-b border-zinc-100 px-4 py-3">
        <.link navigate={~p"/chat"} class="text-sm text-zinc-500">← Chat</.link>

        <h1 data-test-id="group-title" class="text-lg font-semibold text-zinc-900">
          {Group.display_name(@group)}
        </h1>
      </header>

      <ul id="messages" phx-update="stream" class="flex-1 space-y-3 overflow-y-auto px-4 py-4">
        <li
          :for={{dom_id, message} <- @streams.messages}
          id={dom_id}
          data-test-id={"message-#{message.id}"}
        >
          <p class="text-xs text-zinc-500">{message.author_email}</p>
          <p class="whitespace-pre-wrap break-words text-sm text-zinc-900">{message.body}</p>
        </li>
      </ul>

      <div class="border-t border-zinc-100 px-4 py-3">
        <p :if={@error} data-test-id="message-error" class="mb-2 text-sm text-rose-600">
          {@error}
        </p>

        <.form for={@form} data-test-id="message-form" phx-submit="send" class="flex gap-2">
          <textarea
            id="message-body"
            name="message[body]"
            rows="2"
            placeholder="Write a message"
            class="flex-1 rounded-lg border-zinc-300 text-sm focus:border-zinc-400 focus:ring-0"
          >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>

          <button
            type="submit"
            data-test-id="message-send"
            class="self-end rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white"
          >
            Send
          </button>
        </.form>
      </div>
    </div>
    """
  end
end
