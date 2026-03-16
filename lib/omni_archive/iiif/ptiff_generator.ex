defmodule OmniArchive.Iiif.PtiffGenerator do
  @moduledoc """
  高解像度 PNG 画像から Pyramid TIFF (PTIFF) を生成するモジュール。

  ## 概要

  IIIF Image API のディープズーム配信に必要な Pyramid TIFF を、
  Vix（libvips バインディング）を用いて生成します。
  2GB VPS 上でもメモリオーバーヘッドなく動作するよう、
  libvips のストリーミング処理を活用しています。

  ## なぜ DEFLATE 圧縮か

  考古学的線画（モノクロ図面）では、JPEG 圧縮を使用すると
  モスキートノイズ（ブロック境界のアーティファクト）が発生し、
  細い線や文字が劣化します。DEFLATE（zlib）は可逆圧縮のため、
  原画の品質を完全に保持しつつファイルサイズを削減できます。

  ## 生成オプション

  | オプション      | 値      | 理由                                   |
  |----------------|---------|----------------------------------------|
  | `tile`         | `true`  | IIIF タイルサービングに必須             |
  | `pyramid`      | `true`  | ディープズーム用マルチ解像度レイヤー    |
  | `tile_width`   | `256`   | IIIF 標準タイルサイズ                   |
  | `tile_height`  | `256`   | IIIF 標準タイルサイズ                   |
  | `compression`  | DEFLATE | 可逆圧縮によるモスキートノイズ防止      |
  """

  require Logger

  alias Vix.Vips.Image

  @tiff_options [
    tile: true,
    pyramid: true,
    tile_width: 256,
    tile_height: 256,
    compression: :VIPS_FOREIGN_TIFF_COMPRESSION_DEFLATE
  ]

  @doc """
  PNG 画像を読み込み、Pyramid TIFF として保存します。

  ## 引数

    - `input_png_path` — 入力 PNG ファイルの絶対パス
    - `output_tiff_path` — 出力 PTIFF ファイルの絶対パス（拡張子 `.tif` または `.tiff`）

  ## 戻り値

    - `{:ok, output_tiff_path}` — 成功時、出力パスを返します
    - `{:error, reason}` — 失敗時、エラー理由を返します

  ## 例

      iex> OmniArchive.Iiif.PtiffGenerator.generate_ptiff(
      ...>   "/data/images/page-001.png",
      ...>   "/data/ptiff/page-001.tif"
      ...> )
      {:ok, "/data/ptiff/page-001.tif"}
  """
  @spec generate_ptiff(input_png_path :: String.t(), output_tiff_path :: String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_ptiff(input_png_path, output_tiff_path) do
    Logger.info("PTIFF 生成開始: #{input_png_path} → #{output_tiff_path}")

    with {:ok, image} <- Image.new_from_file(input_png_path) do
      # 白背景マスキングは crop_image 時に完了済みのため、そのまま PTIFF を生成

      case Image.write_to_file(image, output_tiff_path, @tiff_options) do
        :ok ->
          Logger.info("PTIFF 生成完了: #{output_tiff_path}")
          {:ok, output_tiff_path}

        {:error, reason} = error ->
          Logger.error("PTIFF 生成失敗: #{inspect(reason)}")
          error
      end
    else
      {:error, reason} = error ->
        Logger.error("PTIFF 読み込み失敗: #{inspect(reason)}")
        error
    end
  end
end
