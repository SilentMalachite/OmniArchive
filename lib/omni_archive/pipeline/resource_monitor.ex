defmodule OmniArchive.Pipeline.ResourceMonitor do
  @moduledoc """
  システムリソースの検出と動的並列度の計算を担当する GenServer。

  - `System.schedulers_online()` で論理 CPU コア数を動的に取得
  - macOS / Linux 対応のメモリ検出
  - PTIF 変換の最大同時実行数を計算する「メモリガード」
  - UI レスポンシブネスのための CPU 予約

  ## なぜこの設計か

  - **GenServer で状態保持**: リソース情報を定期的にリフレッシュし、
    複数のパイプラインリクエスト間で一貫した情報を提供します。
    毎回 `vm_stat` や `/proc/meminfo` を呼ぶオーバーヘッドを避けます。
  - **メモリガード**: PTIF 変換は1件あたり約500MB のメモリを消費する
    重い処理です。利用可能メモリの70%を上限とすることで、BEAM VM や
    PostgreSQL など他のプロセスのメモリを確保し、スワッピングを防ぎます。
  - **CPU 1コア予約**: Phoenix LiveView の UI 更新とWebSocket 通信は
    リアルタイム性が求められます。処理パイプラインに全コアを使うと
    UI がフリーズするため、最低1コアを Web サーバー用に確保しています。
  """
  use GenServer
  require Logger

  # PTIF変換1件あたりの推定メモリ使用量 (バイト)
  @estimated_ptif_memory_bytes 500 * 1024 * 1024

  # 利用可能メモリのうち処理に使用する割合
  @memory_utilization_ratio 0.7

  # リソース情報の更新間隔 (ミリ秒)
  @refresh_interval_ms 30_000

  # --- 公開 API ---

  @doc "GenServer を開始します。"
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  パイプライン処理用の並列度を返します。
  UIレスポンシブネスのため、最低1コアをWebサーバー用に確保します。
  """
  def pipeline_concurrency do
    GenServer.call(__MODULE__, :pipeline_concurrency)
  end

  @doc """
  メモリガードに基づく PTIF 同時変換の最大数を返します。
  利用可能メモリの70%を上限とし、1変換あたり約500MBで計算します。
  """
  def max_ptif_workers do
    GenServer.call(__MODULE__, :max_ptif_workers)
  end

  @doc "現在のシステムリソース情報を返します。"
  def system_info do
    GenServer.call(__MODULE__, :system_info)
  end

  # --- GenServer コールバック ---

  @impl true
  def init(_opts) do
    state = detect_resources()

    Logger.info(
      "[ResourceMonitor] 検出: CPU #{state.cpu_cores}コア, " <>
        "メモリ #{format_bytes(state.total_memory_bytes)}, " <>
        "利用可能 #{format_bytes(state.available_memory_bytes)}, " <>
        "パイプライン並列度 #{state.pipeline_concurrency}, " <>
        "最大PTIF同時変換数 #{state.max_ptif_workers}"
    )

    # 定期的にリソース情報を更新
    Process.send_after(self(), :refresh, @refresh_interval_ms)

    {:ok, state}
  end

  @impl true
  def handle_call(:pipeline_concurrency, _from, state) do
    {:reply, state.pipeline_concurrency, state}
  end

  @impl true
  def handle_call(:max_ptif_workers, _from, state) do
    {:reply, state.max_ptif_workers, state}
  end

  @impl true
  def handle_call(:system_info, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:refresh, _state) do
    new_state = detect_resources()
    Process.send_after(self(), :refresh, @refresh_interval_ms)
    {:noreply, new_state}
  end

  # --- プライベート関数 ---

  defp detect_resources do
    cpu_cores = System.schedulers_online()
    {total_mem, available_mem} = detect_memory()

    # UIレスポンシブネス: 最低1コアをWebサーバー用に確保
    pipeline_conc = max(cpu_cores - 1, 1)

    # メモリガード: 利用可能メモリに基づく最大PTIF同時変換数
    ptif_workers = calculate_max_ptif_workers(available_mem, pipeline_conc)

    %{
      cpu_cores: cpu_cores,
      total_memory_bytes: total_mem,
      available_memory_bytes: available_mem,
      pipeline_concurrency: pipeline_conc,
      max_ptif_workers: ptif_workers,
      detected_at: DateTime.utc_now()
    }
  end

  @doc false
  defp calculate_max_ptif_workers(available_memory_bytes, pipeline_concurrency) do
    # 利用可能メモリの70%をPTIF処理に割り当て
    allocatable = trunc(available_memory_bytes * @memory_utilization_ratio)
    mem_based = max(div(allocatable, @estimated_ptif_memory_bytes), 1)

    # CPU制限とメモリ制限の小さい方を採用
    min(mem_based, pipeline_concurrency)
  end

  @doc false
  defp detect_memory do
    case :os.type() do
      {:unix, :darwin} -> detect_memory_macos()
      {:unix, _} -> detect_memory_linux()
      _ -> {0, 0}
    end
  end

  # macOS: sysctl でメモリ情報を取得
  defp detect_memory_macos do
    total = get_sysctl_value("hw.memsize")

    # vm_stat で利用可能メモリを推定
    available =
      case System.cmd("vm_stat", [], stderr_to_stdout: true) do
        {output, 0} ->
          estimate_available_memory_macos(output, total)

        _ ->
          # フォールバック: 総メモリの50%を利用可能と仮定
          div(total, 2)
      end

    {total, available}
  end

  # macOS: vm_stat の出力から利用可能メモリを推定
  defp estimate_available_memory_macos(vm_stat_output, total_memory) do
    # ページサイズを取得
    page_size =
      case Regex.run(~r/page size of (\d+) bytes/, vm_stat_output) do
        [_, size] -> String.to_integer(size)
        _ -> 4096
      end

    # free + inactive ページ数を合計
    free_pages = extract_vm_stat_pages(vm_stat_output, "Pages free")
    inactive_pages = extract_vm_stat_pages(vm_stat_output, "Pages inactive")

    available = (free_pages + inactive_pages) * page_size

    # 妥当性チェック: 0以下なら総メモリの30%をフォールバック
    if available > 0, do: available, else: div(total_memory * 3, 10)
  end

  defp extract_vm_stat_pages(output, label) do
    case Regex.run(~r/#{Regex.escape(label)}:\s+(\d+)/, output) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
  end

  defp get_sysctl_value(key) do
    case System.cmd("sysctl", ["-n", key], stderr_to_stdout: true) do
      {output, 0} ->
        output |> String.trim() |> String.to_integer()

      _ ->
        0
    end
  end

  # Linux: /proc/meminfo からメモリ情報を取得
  defp detect_memory_linux do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        total = extract_meminfo_kb(content, "MemTotal") * 1024
        available = extract_meminfo_kb(content, "MemAvailable") * 1024

        # MemAvailable が無い古いカーネルの場合のフォールバック
        available =
          if available > 0 do
            available
          else
            free = extract_meminfo_kb(content, "MemFree") * 1024
            buffers = extract_meminfo_kb(content, "Buffers") * 1024
            cached = extract_meminfo_kb(content, "Cached") * 1024
            free + buffers + cached
          end

        {total, available}

      _ ->
        {0, 0}
    end
  end

  defp extract_meminfo_kb(content, key) do
    case Regex.run(~r/#{key}:\s+(\d+)\s+kB/, content) do
      [_, value] -> String.to_integer(value)
      _ -> 0
    end
  end

  # バイトを人間が読みやすい形式にフォーマット
  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  defp format_bytes(bytes) do
    "#{bytes} B"
  end
end
