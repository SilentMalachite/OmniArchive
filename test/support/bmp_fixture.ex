defmodule OmniArchive.BmpFixture do
  @moduledoc """
  テスト用の最小 BMP（24bit 無圧縮・ボトムアップ）バイト列生成ヘルパ。

  vix も（保証されない）ImageMagick も BMP 書き出しに使えないため、テストでは
  純 Elixir で BMP フィクスチャを生成する。`OmniArchive.Ingestion.Bmp` の
  デコード対象（BITMAPINFOHEADER・無圧縮・24bit）と一致する形式を出力する。
  """

  @doc """
  指定サイズの単色 24bit BMP バイト列を生成する。`color` は `{r, g, b}`。
  """
  def solid(width, height, {_r, _g, _b} = color \\ {10, 20, 30}) do
    rows = List.duplicate(List.duplicate(color, width), height)
    encode(width, height, rows)
  end

  @doc """
  RGB 行（トップダウン、各行は `{r, g, b}` のリスト）から無圧縮 BMP を生成する。

  ## オプション
    - `:bpp` — ビット深度（`24`（既定）または `32`）。32bit はアルファ 255 で書く。
    - `:top_down` — `true` のとき height を負値で書き、行をトップダウンで格納する。
  """
  def encode(width, height, rgb_rows_top_down, opts \\ []) do
    bpp = Keyword.get(opts, :bpp, 24)
    top_down = Keyword.get(opts, :top_down, false)
    bytes_per_pixel = div(bpp, 8)
    row_stride = div(bpp * width + 31, 32) * 4
    pad = row_stride - width * bytes_per_pixel

    # ファイル格納順: ボトムアップなら行を反転、トップダウンならそのまま
    file_rows = if top_down, do: rgb_rows_top_down, else: Enum.reverse(rgb_rows_top_down)

    pixels =
      file_rows
      |> Enum.map(fn row ->
        body = for {r, g, b} <- row, into: <<>>, do: encode_pixel(bpp, r, g, b)
        body <> :binary.copy(<<0>>, pad)
      end)
      |> IO.iodata_to_binary()

    offset = 54
    stored_height = if top_down, do: -height, else: height

    dib =
      <<40::little-32, width::little-signed-32, stored_height::little-signed-32, 1::little-16,
        bpp::little-16, 0::little-32, byte_size(pixels)::little-32, 2835::little-32,
        2835::little-32, 0::little-32, 0::little-32>>

    file_header =
      <<"BM", offset + byte_size(pixels)::little-32, 0::little-16, 0::little-16,
        offset::little-32>>

    file_header <> dib <> pixels
  end

  defp encode_pixel(24, r, g, b), do: <<b, g, r>>
  defp encode_pixel(32, r, g, b), do: <<b, g, r, 255>>
end
