defmodule TestProject.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TestProjectWeb.Telemetry,
      TestProject.Repo,
      {DNSCluster, query: Application.get_env(:test_project, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TestProject.PubSub},
      # Start a worker by calling: TestProject.Worker.start_link(arg)
      # {TestProject.Worker, arg},
      # Start to serve requests, typically the last entry
      TestProjectWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TestProject.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TestProjectWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
