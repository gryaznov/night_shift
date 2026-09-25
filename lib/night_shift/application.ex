defmodule NightShift.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NightShiftWeb.Telemetry,
      NightShift.Repo,
      {DNSCluster, query: Application.get_env(:night_shift, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NightShift.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: NightShift.Finch},
      # Start a worker by calling: NightShift.Worker.start_link(arg)
      # {NightShift.Worker, arg},
      # Start to serve requests, typically the last entry
      NightShiftWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NightShift.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NightShiftWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
