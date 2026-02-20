defmodule AlchemIiif.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AlchemIiifWeb.Telemetry,
      AlchemIiif.Repo,
      {DNSCluster, query: Application.get_env(:alchem_iiif, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AlchemIiif.PubSub},
      # リソース監視 GenServer（CPU/メモリの動的検出）
      AlchemIiif.Pipeline.ResourceMonitor,
      # Start to serve requests, typically the last entry
      AlchemIiifWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AlchemIiif.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AlchemIiifWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
