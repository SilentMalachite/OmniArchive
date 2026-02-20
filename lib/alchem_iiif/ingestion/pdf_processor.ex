defmodule AlchemIiif.Ingestion.PdfProcessor do
  require Logger

  @moduledoc """
  pdftoppm を使用して PDF ページを高解像度 PNG 画像に変換するモジュール。

  ## なぜこの設計か

  - **pdftoppm を採用**: Poppler スイートの一部であり、フォント埋め込みや
    日本語レンダリングに優れています。ImageMagick の `convert` コマンドと
    比較して、PDF 処理に特化しており出力品質が安定しています。
  - **300 DPI**: 考古学資料の画像では細部の確認が重要です。72 DPI では
    テキストが不鮮明になり、600 DPI はファイルサイズが過大になるため、
    300 DPI を品質とサイズのバランス点として選択しています。
  """

  @doc """
  PDFファイルの全ページを PNG に変換します。
  出力ディレクトリに page-001-{timestamp}.png, page-002-{timestamp}.png ... の形式で保存されます。
  タイムスタンプにより、再アップロード時にブラウザキャッシュを自動的にバイパスします。

  ## 引数
    - pdf_path: PDF ファイルのパス
    - output_dir: 出力先ディレクトリ

  ## 戻り値
    - {:ok, %{page_count: integer, image_paths: [String.t()]}}
    - {:error, reason}
  """
  def convert_to_images(pdf_path, output_dir) do
    # セキュリティ注記: output_dir は内部生成パス（priv/static/uploads/pages/{id}）、
    # cmd は固定文字列 "pdftoppm" — 外部入力由来ではないため安全。
    # 出力ディレクトリを作成
    File.mkdir_p!(output_dir)

    output_prefix = Path.join(output_dir, "page")

    # pdftoppm で PDF→PNG 変換 (300 DPI)
    # 絶対パスに変換して実行ディレクトリに依存しないようにする
    abs_pdf_path = Path.expand(pdf_path)
    abs_output_prefix = Path.expand(output_prefix)

    # コマンドと引数を準備
    cmd = "pdftoppm"

    args = [
      "-png",
      "-r",
      "300",
      abs_pdf_path,
      abs_output_prefix
    ]

    Logger.info("[PdfProcessor] Executing: #{cmd} #{Enum.join(args, " ")}")

    try do
      case System.cmd(cmd, args, stderr_to_stdout: true) do
        {_output, 0} ->
          # 生成された画像ファイルを取得し、タイムスタンプでバージョニング
          timestamp = System.system_time(:second)

          image_paths =
            output_dir
            |> File.ls!()
            |> Enum.filter(&String.ends_with?(&1, ".png"))
            |> Enum.sort()
            |> Enum.map(fn original_name ->
              # page-01.png → page-01-1708065543.png
              versioned_name =
                String.replace(original_name, ~r/\.png$/, "-#{timestamp}.png")

              original_path = Path.join(output_dir, original_name)
              versioned_path = Path.join(output_dir, versioned_name)
              File.rename!(original_path, versioned_path)
              versioned_path
            end)

          if Enum.empty?(image_paths) do
            Logger.error("[PdfProcessor] No images generated despite exit code 0")
            {:error, "画像が生成されませんでした (exit code 0)"}
          else
            Logger.info("[PdfProcessor] Successfully generated #{length(image_paths)} images")
            {:ok, %{page_count: length(image_paths), image_paths: image_paths}}
          end

        {error_output, exit_code} ->
          Logger.error(
            "[PdfProcessor] Command failed with exit code #{exit_code}: #{error_output}"
          )

          {:error, "PDF変換に失敗しました (exit code #{exit_code}): #{error_output}"}
      end
    rescue
      e in ErlangError ->
        if e.original == :enoent do
          Logger.error("[PdfProcessor] pdftoppm not found")
          {:error, "pdftoppm コマンドが見つかりません。Poppler がインストールされているか確認してください。"}
        else
          Logger.error("[PdfProcessor] System error: #{inspect(e)}")
          {:error, "システムエラーが発生しました: #{inspect(e)}"}
        end
    end
  end

  @doc """
  PDFのページ数を取得します。
  """
  def get_page_count(pdf_path) do
    case System.cmd("pdfinfo", [pdf_path], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/Pages:\s+(\d+)/, output) do
          [_, count] -> {:ok, String.to_integer(count)}
          _ -> {:error, "ページ数を取得できませんでした"}
        end

      {_error, _} ->
        {:error, "PDF情報の取得に失敗しました"}
    end
  end
end
