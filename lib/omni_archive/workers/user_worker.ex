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
    process_source(user_id, pdf_source, pdf_path, pipeline_id, %{
      color_mode: color_mode,
      max_pages: max_pages
    })
  end

  @doc """
  汎用ソース（PDF / ZIP）処理を起動する。Pipeline.run_source_extraction を
  バックグラウンドで実行し、完了通知を PubSub でブロードキャストする。

  ## 引数
    - user_id: アクセス制御の owner
    - pdf_source: PdfSource レコード（source_type を含む）
    - source_path: 物理ファイルパス
    - pipeline_id: パイプライン識別子
    - opts: マップ。color_mode / max_pages / max_extracted_bytes を許容
  """
  def process_source(user_id, pdf_source, source_path, pipeline_id, opts \\ %{})
      when is_map(opts) do
    GenServer.call(
      via_tuple(user_id),
      {:process_source, pdf_source, source_path, pipeline_id, opts}
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
        {:process_source, _pdf_source, _source_path, _pipeline_id, _opts},
        _from,
        %{active_pdf_job: true} = state
      ) do
    {:reply, {:error, :pdf_job_in_progress}, state}
  end

  def handle_call(
        {:process_source, pdf_source, source_path, pipeline_id, opts},
        _from,
        state
      ) do
    source_type = pdf_source.source_type || "pdf"

    Logger.info(
      "⚙️ ユーザー(#{state.user_id})の#{String.upcase(source_type)}(ID:#{pdf_source.id})の裏側処理を開始します..."
    )

    worker = self()

    # Run the heavy processing in a separate Task
    Task.start(fn ->
      try do
        run_opts =
          opts
          |> Map.put(:owner_id, state.user_id)
          |> Map.put_new(:color_mode, "mono")

        OmniArchive.Pipeline.run_source_extraction(
          pdf_source,
          source_path,
          pipeline_id,
          run_opts
        )

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
