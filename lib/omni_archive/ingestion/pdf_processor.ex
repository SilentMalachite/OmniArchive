defmodule OmniArchive.Ingestion.PdfProcessor do
  require Logger

  @moduledoc """
  pdftoppm を使用して PDF ページを高解像度 PNG 画像に変換するモジュール。

  ## なぜこの設計か

  - **pdftoppm を採用**: Poppler スイートの一部であり、フォント埋め込みや
    日本語レンダリングに優れています。ImageMagick の `convert` コマンドと
    比較して、PDF 処理に特化しており出力品質が安定しています。
  - **300 DPI**: 学術資料（特に線画）の品質を確保するため 300 DPI を
    使用しています。処理速度の最適化は application.ex 側の Vix 設定
    （スレッド数・キャッシュ制限）で対応しています。
  - **チャンク逐次処理**: 2GB RAM の VPS でも安全に動作するよう、
    10 ページ単位でチャンク分割し `max_concurrency: 1` で逐次実行します。
    これにより、任意の時点での最大メモリ使用量を制限できます。
  """

  # OOM 防止のためのチャンクサイズ（2GB RAM VPS 向け）
  @chunk_size 10
  @default_max_pages 200
  @default_command_timeout_ms 120_000
  @default_max_output_bytes 1_000_000_000

  @doc """
  PDFファイルの全ページを PNG に変換します。
  出力ディレクトリに page-001-{timestamp}.png, page-002-{timestamp}.png ... の形式で保存されます。
  タイムスタンプにより、再アップロード時にブラウザキャッシュを自動的にバイパスします。

  ページ数・生成画像サイズ・外部コマンド実行時間に上限を設け、許可範囲内の PDF を
  10 ページ単位のチャンクに分割して逐次処理します。

  ## 引数
    - pdf_path: PDF ファイルのパス
    - output_dir: 出力先ディレクトリ

  ## 戻り値
    - {:ok, %{page_count: integer, image_paths: [String.t()]}}
    - {:error, reason}
  """
  def convert_to_images(pdf_path, output_dir, opts \\ %{}) do
    # セキュリティ注記: output_dir は内部生成パス（priv/static/uploads/pages/{id}）、
    # cmd は固定文字列 "pdftoppm" — 外部入力由来ではないため安全。
    File.mkdir_p!(output_dir)

    abs_pdf_path = Path.expand(pdf_path)
    abs_output_prefix = Path.expand(Path.join(output_dir, "page"))

    # まずページ数を取得してチャンクリストを生成
    case get_page_count(abs_pdf_path, opts) do
      {:ok, total_pages} ->
        with :ok <- validate_page_count(total_pages, opts) do
          run_chunked_conversion(abs_pdf_path, abs_output_prefix, output_dir, total_pages, opts)
        end

      {:error, reason} ->
        Logger.error("[PdfProcessor] Command failed with exit code (pdfinfo): #{reason}")

        {:error, "PDF変換に失敗しました (pdfinfo): #{reason}"}
    end
  end

  @doc """
  PDFのページ数を取得します。
  """
  def get_page_count(pdf_path) do
    get_page_count(pdf_path, %{})
  end

  defp get_page_count(pdf_path, opts) do
    case run_command("pdfinfo", [pdf_path], opts) do
      {:ok, {output, 0}} ->
        parse_page_count(output)

      {:ok, {_error, _}} ->
        {:error, "PDF情報の取得に失敗しました"}

      {:error, :timeout} ->
        {:error, "PDF情報の取得がタイムアウトしました"}

      {:error, reason} ->
        {:error, "PDF情報の取得に失敗しました: #{inspect(reason)}"}
    end
  end

  defp parse_page_count(output) do
    case Regex.run(~r/Pages:\s+(\d+)/, output) do
      [_, count] -> {:ok, String.to_integer(count)}
      _ -> {:error, "ページ数を取得できませんでした"}
    end
  end

  defp validate_page_count(total_pages, opts) do
    max_pages = Map.get(opts, :max_pages, @default_max_pages)

    if total_pages <= max_pages do
      :ok
    else
      {:error, "ページ数上限（#{max_pages}ページ）を超えています: #{total_pages}ページ"}
    end
  end

  defp run_command(command, args, opts) do
    runner = Map.get(opts, :command_runner, &System.cmd/3)
    timeout_ms = command_timeout_ms(opts)
    command_opts = [stderr_to_stdout: true]

    task =
      Task.async(fn ->
        runner.(command, args, command_opts)
      end)

    case Task.yield(task, timeout_ms) do
      {:ok, result} ->
        {:ok, result}

      {:exit, reason} ->
        {:error, reason}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  defp command_timeout_ms(opts),
    do: Map.get(opts, :command_timeout_ms, @default_command_timeout_ms)

  defp collect_and_rename_images(output_dir, opts) do
    timestamp = System.system_time(:second)

    # Path.wildcard で確実に収集し、明示的にソート
    image_paths =
      Path.wildcard(Path.join(output_dir, "page*.png"))
      |> Enum.sort()

    with :ok <- validate_generated_output_size(image_paths, opts) do
      renamed_paths =
        Enum.map(image_paths, fn original_path ->
          original_name = Path.basename(original_path)
          # page-01.png → page-01-1708065543.png
          versioned_name = String.replace(original_name, ~r/\.png$/, "-#{timestamp}.png")
          versioned_path = Path.join(output_dir, versioned_name)
          File.rename!(original_path, versioned_path)
          versioned_path
        end)

      if Enum.empty?(renamed_paths) do
        Logger.error("[PdfProcessor] No images generated despite successful conversion")
        {:error, "画像が生成されませんでした (exit code 0)"}
      else
        Logger.info("[PdfProcessor] Successfully generated #{length(renamed_paths)} images")
        {:ok, %{page_count: length(renamed_paths), image_paths: renamed_paths}}
      end
    else
      {:error, reason} ->
        Enum.each(image_paths, &File.rm/1)
        {:error, reason}
    end
  end

  defp validate_generated_output_size(image_paths, opts) do
    max_output_bytes = Map.get(opts, :max_output_bytes, @default_max_output_bytes)

    total_bytes =
      Enum.reduce(image_paths, 0, fn path, acc ->
        case File.stat(path) do
          {:ok, %{size: size}} -> acc + size
          {:error, _} -> acc
        end
      end)

    if total_bytes <= max_output_bytes do
      :ok
    else
      {:error, "生成画像サイズ上限（#{max_output_bytes} bytes）を超えています: #{total_bytes} bytes"}
    end
  end

  # --- Private Functions ---

  # チャンク逐次処理の実行
  defp run_chunked_conversion(abs_pdf_path, abs_output_prefix, output_dir, total_pages, opts) do
    chunks = build_chunks(total_pages)

    Logger.info(
      "[PdfProcessor] Processing #{total_pages} pages in #{length(chunks)} chunks of #{@chunk_size}"
    )

    try do
      # max_concurrency: 1 で逐次実行（OOM 防止の要）
      results =
        chunks
        |> Task.async_stream(
          fn {first, last} ->
            result = run_pdftoppm_chunk(abs_pdf_path, abs_output_prefix, first, last, opts)

            # チャンク完了ごとに進捗をブロードキャスト（UI プログレスバー用）
            if result == :ok do
              broadcast_chunk_progress(last, total_pages, opts)
            end

            result
          end,
          max_concurrency: 1,
          timeout: command_timeout_ms(opts) + 1_000,
          ordered: true
        )
        |> Enum.to_list()

      # チャンク処理結果を検証
      case find_chunk_error(results) do
        nil ->
          collect_and_rename_images(output_dir, opts)

        error ->
          error
      end
    rescue
      e in ErlangError ->
        handle_erlang_error(e)
    end
  end

  # ページ範囲をチャンクに分割（例: 25ページ → [{1,10}, {11,20}, {21,25}]）
  defp build_chunks(total_pages) do
    1..total_pages
    |> Enum.chunk_every(@chunk_size)
    |> Enum.map(fn chunk ->
      {List.first(chunk), List.last(chunk)}
    end)
  end

  # 1チャンク分の pdftoppm 実行
  defp run_pdftoppm_chunk(abs_pdf_path, abs_output_prefix, first_page, last_page, opts) do
    cmd = "pdftoppm"
    color_mode = Map.get(opts, :color_mode, "mono")

    # カラーモードに応じてフラグを構築
    # "mono" → -gray（グレースケール変換で高速化）
    # "color" → フラグなし（フルカラー出力）
    gray_flag = if color_mode == "mono", do: ["-gray"], else: []

    args =
      gray_flag ++
        [
          "-png",
          "-r",
          "300",
          "-f",
          Integer.to_string(first_page),
          "-l",
          Integer.to_string(last_page),
          abs_pdf_path,
          abs_output_prefix
        ]

    Logger.info("[PdfProcessor] Chunk: pages #{first_page}-#{last_page}")

    case run_command(cmd, args, opts) do
      {:ok, {_output, 0}} ->
        :ok

      {:ok, {error_output, exit_code}} ->
        Logger.error(
          "[PdfProcessor] Chunk failed (pages #{first_page}-#{last_page}), " <>
            "exit code #{exit_code}: #{error_output}"
        )

        {:error, "PDF変換に失敗しました (exit code #{exit_code}): #{error_output}"}

      {:error, :timeout} ->
        Logger.error("[PdfProcessor] Chunk timed out (pages #{first_page}-#{last_page})")
        {:error, "PDF変換がタイムアウトしました (pages #{first_page}-#{last_page})"}

      {:error, reason} ->
        Logger.error("[PdfProcessor] Chunk failed with system error: #{inspect(reason)}")
        {:error, "PDF変換に失敗しました: #{inspect(reason)}"}
    end
  end

  # チャンク結果からエラーを探す
  defp find_chunk_error(results) do
    Enum.find_value(results, fn
      {:ok, :ok} -> nil
      {:ok, {:error, _} = error} -> error
      {:exit, reason} -> {:error, "チャンク処理が異常終了しました: #{inspect(reason)}"}
    end)
  end

  # チャンク完了時の進捗ブロードキャスト（user_id が opts に含まれる場合のみ）
  defp broadcast_chunk_progress(current_page, total_pages, %{user_id: user_id})
       when not is_nil(user_id) do
    Phoenix.PubSub.broadcast(
      OmniArchive.PubSub,
      "pdf_pipeline:#{user_id}",
      {:extraction_progress, current_page, total_pages}
    )
  end

  defp broadcast_chunk_progress(_current_page, _total_pages, _opts), do: :ok

  # ErlangError ハンドリング（enoent 対応）
  defp handle_erlang_error(e) do
    if e.original == :enoent do
      Logger.error("[PdfProcessor] pdftoppm not found")

      {:error, "pdftoppm コマンドが見つかりません。Poppler がインストールされているか確認してください。"}
    else
      Logger.error("[PdfProcessor] System error: #{inspect(e)}")
      {:error, "システムエラーが発生しました: #{inspect(e)}"}
    end
  end
end
