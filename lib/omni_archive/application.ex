defmodule OmniArchive.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # libvips のグローバル制約: Elixir 側で並行処理を管理するため、
    # libvips 内部のスレッド競合を防止し、メモリ/CPU 使用量を制限する
    Vix.Vips.concurrency_set(1)
    Vix.Vips.cache_set_max(100)
    Vix.Vips.cache_set_max_mem(512 * 1024 * 1024)

    yaml_children =
      if Application.get_env(:omni_archive, :domain_profile) == OmniArchive.DomainProfiles.Yaml do
        [OmniArchive.DomainProfiles.YamlCache]
      else
        []
      end

    base_children = [
      OmniArchiveWeb.Telemetry,
      OmniArchive.Repo,
      {DNSCluster, query: Application.get_env(:omni_archive, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: OmniArchive.PubSub}
    ]

    post_children = [
      OmniArchive.CustomMetadataFields.Cache,
      OmniArchive.Pipeline.ResourceMonitor,
      {Registry, keys: :unique, name: OmniArchive.UserWorkerRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: OmniArchive.UserWorkerSupervisor},
      OmniArchiveWeb.Endpoint
    ]

    children = base_children ++ yaml_children ++ post_children

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: OmniArchive.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OmniArchiveWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
