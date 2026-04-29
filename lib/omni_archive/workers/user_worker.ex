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

  def process_pdf(
        user_id,
        pdf_source,
        pdf_path,
        pipeline_id,
        color_mode \\ "mono",
        max_pages \\ nil
      ) do
    GenServer.call(
      via_tuple(user_id),
      {:process_pdf, pdf_source, pdf_path, pipeline_id, color_mode, max_pages}
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
    {:ok, Map.put(state, :active_pdf_job, false)}
  end

  @impl true
  def handle_call(
        {:process_pdf, _pdf_source, _pdf_path, _pipeline_id, _color_mode, _max_pages},
        _from,
        %{active_pdf_job: true} = state
      ) do
    {:reply, {:error, :pdf_job_in_progress}, state}
  end

  def handle_call(
        {:process_pdf, pdf_source, pdf_path, pipeline_id, color_mode, max_pages},
        _from,
        state
      ) do
    Logger.info("⚙️ ユーザー(#{state.user_id})のPDF(ID:#{pdf_source.id})の裏側処理を開始します...")

    worker = self()

    # Run the heavy processing in a separate Task
    Task.start(fn ->
      try do
        # Use the correct extraction function（カラーモードを opts に含める）
        OmniArchive.Pipeline.run_pdf_extraction(pdf_source, pdf_path, pipeline_id, %{
          owner_id: state.user_id,
          color_mode: color_mode,
          max_pages: max_pages
        })

        # Notify the UI that processing is complete
        Phoenix.PubSub.broadcast(
          OmniArchive.PubSub,
          "pdf_source_#{pdf_source.id}",
          {:pdf_processed, pdf_source.id}
        )
      after
        send(worker, {:pdf_job_finished, pdf_source.id})
      end
    end)

    {:reply, :ok, %{state | active_pdf_job: true}}
  end

  @impl true
  def handle_info({:pdf_job_finished, pdf_source_id}, state) do
    Logger.info("✅ ユーザー(#{state.user_id})のPDF(ID:#{pdf_source_id})の裏側処理が終了しました")
    {:noreply, %{state | active_pdf_job: false}}
  end
end
