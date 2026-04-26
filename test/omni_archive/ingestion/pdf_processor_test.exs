defmodule OmniArchive.Ingestion.PdfProcessorTest do
  use ExUnit.Case, async: true
  alias OmniArchive.Ingestion.PdfProcessor
  import ExUnit.CaptureLog

  @tag :tmp_dir
  test "returns error when PDF file does not exist", %{tmp_dir: tmp_dir} do
    # 存在しないPDFパスを指定
    pdf_path = Path.join(tmp_dir, "non_existent.pdf")
    output_dir = Path.join(tmp_dir, "output")

    # ログをキャプチャして検証
    assert capture_log(fn ->
             assert {:error, message} = PdfProcessor.convert_to_images(pdf_path, output_dir)
             assert message =~ "PDF変換に失敗しました"

             # pdftoppm のエラーメッセージが含まれていることを期待（環境によるが）
           end) =~ "Command failed with exit code"
  end

  @tag :tmp_dir
  test "returns error when pdftoppm fails (e.g. invalid file)", %{tmp_dir: tmp_dir} do
    # 空のファイルを作成（PDFとして不正）
    pdf_path = Path.join(tmp_dir, "invalid.pdf")
    File.write!(pdf_path, "not a pdf")
    output_dir = Path.join(tmp_dir, "output")

    assert capture_log(fn ->
             assert {:error, message} = PdfProcessor.convert_to_images(pdf_path, output_dir)
             assert message =~ "PDF変換に失敗しました"
           end) =~ "Command failed with exit code"
  end

  @tag :tmp_dir
  test "ページ数上限を超える PDF は変換前に拒否する", %{tmp_dir: tmp_dir} do
    pdf_path = Path.join(tmp_dir, "too_many_pages.pdf")
    File.write!(pdf_path, "%PDF-1.0")
    output_dir = Path.join(tmp_dir, "output")

    runner = fn
      "pdfinfo", _args, _opts ->
        {"Pages: 11\n", 0}

      "pdftoppm", _args, _opts ->
        send(self(), :pdftoppm_called)
        {"", 0}
    end

    assert {:error, message} =
             PdfProcessor.convert_to_images(pdf_path, output_dir, %{
               command_runner: runner,
               max_pages: 10
             })

    assert message =~ "ページ数上限"
    refute_received :pdftoppm_called
  end

  @tag :tmp_dir
  test "pdfinfo がタイムアウトした場合はエラーを返す", %{tmp_dir: tmp_dir} do
    pdf_path = Path.join(tmp_dir, "slow-info.pdf")
    File.write!(pdf_path, "%PDF-1.0")
    output_dir = Path.join(tmp_dir, "output")

    runner = fn "pdfinfo", _args, _opts ->
      Process.sleep(50)
      {"Pages: 1\n", 0}
    end

    assert {:error, message} =
             PdfProcessor.convert_to_images(pdf_path, output_dir, %{
               command_runner: runner,
               command_timeout_ms: 10
             })

    assert message =~ "タイムアウト"
  end

  @tag :tmp_dir
  test "pdftoppm チャンクがタイムアウトした場合はエラーを返す", %{tmp_dir: tmp_dir} do
    pdf_path = Path.join(tmp_dir, "slow-conversion.pdf")
    File.write!(pdf_path, "%PDF-1.0")
    output_dir = Path.join(tmp_dir, "output")

    runner = fn
      "pdfinfo", _args, _opts ->
        {"Pages: 1\n", 0}

      "pdftoppm", _args, _opts ->
        Process.sleep(50)
        {"", 0}
    end

    assert {:error, message} =
             PdfProcessor.convert_to_images(pdf_path, output_dir, %{
               command_runner: runner,
               command_timeout_ms: 10
             })

    assert message =~ "タイムアウト"
  end

  @tag :tmp_dir
  test "生成画像の総サイズ上限を超えた場合はエラーを返して生成物を掃除する", %{tmp_dir: tmp_dir} do
    pdf_path = Path.join(tmp_dir, "large-output.pdf")
    File.write!(pdf_path, "%PDF-1.0")
    output_dir = Path.join(tmp_dir, "output")

    runner = fn
      "pdfinfo", _args, _opts ->
        {"Pages: 1\n", 0}

      "pdftoppm", args, _opts ->
        output_prefix = List.last(args)
        File.write!("#{output_prefix}-1.png", "too large")
        {"", 0}
    end

    assert {:error, message} =
             PdfProcessor.convert_to_images(pdf_path, output_dir, %{
               command_runner: runner,
               max_output_bytes: 4
             })

    assert message =~ "生成画像サイズ上限"
    assert Path.wildcard(Path.join(output_dir, "*.png")) == []
  end
end
