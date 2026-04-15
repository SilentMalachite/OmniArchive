defmodule OmniArchive.DomainProfiles.YamlCache do
  @moduledoc """
  YAML profile を保持する GenServer + ETS テーブル。
  起動時に YamlLoader で読み込み、:omni_archive_yaml_profile テーブルに書き込む。
  """
  use GenServer

  alias OmniArchive.DomainProfiles.YamlLoader

  @table :omni_archive_yaml_profile

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def metadata_fields, do: fetch!(:metadata_fields)
  def validation_rules, do: fetch!(:validation_rules)
  def search_facets, do: fetch!(:search_facets)
  def ui_texts, do: fetch!(:ui_texts)
  def duplicate_identity, do: fetch!(:duplicate_identity)

  @doc "GenServer を停止させて supervisor に YAML を再読み込みさせる。"
  def reload! do
    if pid = Process.whereis(__MODULE__) do
      GenServer.stop(pid)
    end

    :ok
  end

  defp fetch!(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> raise RuntimeError, "YamlCache not initialized for key #{inspect(key)}"
    end
  end

  @impl true
  def init(_) do
    path = Application.get_env(:omni_archive, :domain_profile_yaml_path)

    with :ok <- ensure_path(path),
         {:ok, profile} <- YamlLoader.load(path) do
      ensure_table()
      :ets.delete_all_objects(@table)

      Enum.each(profile, fn {k, v} -> :ets.insert(@table, {k, v}) end)

      {:ok, %{path: path}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

      _ ->
        @table
    end
  end

  defp ensure_path(nil), do: {:error, "domain_profile_yaml_path is not set"}

  defp ensure_path(path) do
    if File.exists?(path), do: :ok, else: {:error, "YAML file not found: #{path}"}
  end
end
