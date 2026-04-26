defmodule OmniArchive.CustomMetadataFields.Cache do
  @moduledoc """
  カスタムメタデータフィールドの ETS キャッシュ。
  起動時にDBからロードし、書き込み操作時に無効化する。
  """
  use GenServer

  @table __MODULE__
  @loaded_key :__loaded__

  # --- Public API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "指定プロファイルのアクティブなカスタムフィールドをキャッシュから取得"
  def list_active_fields(profile_key) do
    if :ets.whereis(@table) != :undefined and loaded?() do
      case :ets.lookup(@table, {:fields, profile_key}) do
        [{_, fields}] -> fields
        [] -> []
      end
    else
      # キャッシュ未初期化時はDBフォールバック
      load_from_db(profile_key)
    end
  end

  @doc "キャッシュを無効化してDBから再ロード"
  def invalidate do
    if GenServer.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :invalidate)
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    load_all()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast(:invalidate, state) do
    load_all()
    {:noreply, state}
  end

  # --- Private ---

  defp load_all do
    # 全プロファイルキーのフィールドをロード
    import Ecto.Query

    fields =
      OmniArchive.CustomMetadataFields.CustomMetadataField
      |> where([f], f.active == true)
      |> order_by([f], asc: f.sort_order, asc: f.id)
      |> OmniArchive.Repo.all()

    # プロファイルキー別にグループ化してETSに格納
    grouped = Enum.group_by(fields, & &1.profile_key)

    # 既存エントリをクリア
    :ets.delete_all_objects(@table)

    Enum.each(grouped, fn {profile_key, profile_fields} ->
      :ets.insert(@table, {{:fields, profile_key}, profile_fields})
    end)

    :ets.insert(@table, {@loaded_key, true})
  end

  defp loaded? do
    case :ets.lookup(@table, @loaded_key) do
      [{_, true}] -> true
      _ -> false
    end
  end

  defp load_from_db(profile_key) do
    import Ecto.Query

    OmniArchive.CustomMetadataFields.CustomMetadataField
    |> where([f], f.profile_key == ^profile_key and f.active == true)
    |> order_by([f], asc: f.sort_order, asc: f.id)
    |> OmniArchive.Repo.all()
  end
end
