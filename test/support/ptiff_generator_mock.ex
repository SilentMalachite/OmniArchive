defmodule OmniArchive.Iiif.PtiffGeneratorMock do
  @moduledoc """
  テスト用の PtiffGenerator スタブモジュール。
  実際のファイル I/O を行わず、常に成功を返します。
  """

  @doc "テスト用: 常に {:ok, output_tiff_path} を返す"
  @spec generate_ptiff(String.t(), String.t()) :: {:ok, String.t()}
  def generate_ptiff(_input_png_path, output_tiff_path) do
    {:ok, output_tiff_path}
  end
end
