defmodule OmniArchive.Workers.UserWorker do
  @moduledoc """
  ユーザーごとのバックグラウンドワーカー GenServer。

  DynamicSupervisor 配下で起動され、PDF 抽出などの重い処理を
  LiveView プロセスから分離して非同期実行します。
  """
  use GenServer
  require Logger

  @registry OmniArchive.UserWorkerRegistry
  @supervisor OmniArchive.UserWorkerSupervisor

  # Client API

  def start_user_worker(user_id) do
    name = via_tuple(user_id)
    DynamicSupervisor.start_child(@supervisor, {__MODULE__, [user_id: user_id, name: name]})
  end

  def process_pdf(user_id, pdf_source, pdf_path, pipeline_id, color_mode \\ "mono") do
    GenServer.cast(
      via_tuple(user_id),
      {:process_pdf, pdf_source, pdf_path, pipeline_id, color_mode}
    )
  end

  defp via_tuple(user_id), do: {:via, Registry, {@registry, user_id}}

  # Server Callbacks

  def start_link(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, %{user_id: user_id}, name: name)
  end

  @impl true
  def init(state) do
    Logger.info("✅ UserWorker started safely for user_id: #{state.user_id}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:process_pdf, pdf_source, pdf_path, pipeline_id, color_mode}, state) do
    Logger.info("⚙️ ユーザー(#{state.user_id})のPDF(ID:#{pdf_source.id})の裏側処理を開始します...")

    # Run the heavy processing in a separate Task
    Task.start(fn ->
      # Use the correct extraction function（カラーモードを opts に含める）
      OmniArchive.Pipeline.run_pdf_extraction(pdf_source, pdf_path, pipeline_id, %{
        owner_id: state.user_id,
        color_mode: color_mode
      })

      # Notify the UI that processing is complete
      Phoenix.PubSub.broadcast(
        OmniArchive.PubSub,
        "pdf_source_#{pdf_source.id}",
        {:pdf_processed, pdf_source.id}
      )
    end)

    {:noreply, state}
  end
end
