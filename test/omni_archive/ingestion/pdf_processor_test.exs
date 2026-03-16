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
end
