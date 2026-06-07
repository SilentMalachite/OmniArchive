defmodule OmniArchive.Ingestion.Bmp do
  @moduledoc """
  無圧縮 BMP（24/32bit）を pure Elixir でデコードする最小デコーダ。

  ## なぜこの設計か

  - **この環境の libvips は BMP ローダ（および magickload）を持たない**ため、
    `Vix.Vips.Image.new_from_file/1` は BMP を読めない。`ImageProcessor.to_png/2`
    のフォールバックとして BMP を生の RGB ピクセルへ展開し、
    `Vix.Vips.Image.new_from_binary/5` で vix 画像へ変換することで、**新規依存を
    増やさず** BMP→PNG 変換を実現する（AGENTS.md「No new dependencies」遵守）。
  - **対応範囲**: BITMAPINFOHEADER 以降（`dib_size >= 40`）・無圧縮（BI_RGB,
    `compression == 0`）・24/32bit。パレット（≤8bit）・RLE・BITFIELDS 等の稀な
    変種は非対応で `{:error, _}` を返し、呼び出し側（ZipProcessor）はログを出して
    スキップする（バッチ耐性）。
  - **アルファ**: 32bit BMP の第 4 バイトは BI_RGB では未定義のため、誤った
    全透過を避ける目的で破棄し RGB として扱う。
  - **行格納**: BMP は既定でボトムアップ（`height > 0`）。トップダウン
    （`height < 0`）にも対応する。各行は 4 バイト境界へパディングされる。
  - **メモリ保護**: libvips のストリーミングと異なり BMP は BEAM ヒープ上に
    全画素を展開するため、クロップ経路と同じ寸法・面積上限を適用して
    巨大/細長い BMP による過大なメモリ確保を防ぐ（2GB-VPS のメモリ予算保護）。
  """

  alias Vix.Vips.Image

  # クロップ経路（ImageProcessor）と同じ上限を BMP デコードにも適用する。
  @max_dimension 20_000
  @max_area 100_000_000

  @doc """
  BMP ファイルを vix 画像へデコードする。

  ## 戻り値
    - `{:ok, %Vix.Vips.Image{}}` 成功
    - `:not_bmp` BMP シグネチャ（"BM"）ではない
    - `{:error, reason}` 破損・非対応変種・読み込み失敗
  """
  @spec decode_file(Path.t()) :: {:ok, Image.t()} | :not_bmp | {:error, term()}
  def decode_file(path) do
    case File.read(path) do
      {:ok, <<"BM", _::binary>> = bin} -> decode(bin)
      {:ok, _} -> :not_bmp
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  BMP バイナリを vix 画像へデコードする。戻り値は `decode_file/1` と同じ。
  """
  @spec decode(binary()) :: {:ok, Image.t()} | :not_bmp | {:error, term()}
  def decode(<<"BM", _::binary>> = bin) do
    parse(bin)
  rescue
    e -> {:error, "BMP の解析に失敗: #{Exception.message(e)}"}
  end

  def decode(_), do: :not_bmp

  # BITMAPFILEHEADER(14) + BITMAPINFOHEADER 先頭フィールド。
  # width/height/planes/bpp/compression のオフセットは BITMAPINFOHEADER 以降の
  # 全バージョンで共通。ピクセル位置は dib_size ではなく pixel_offset で解決する
  # ため、V4/V5 のような大きい DIB ヘッダでも正しく扱える。
  defp parse(
         <<"BM", _fsize::little-32, _r1::little-16, _r2::little-16, pixel_offset::little-32,
           dib_size::little-32, width::little-signed-32, height_raw::little-signed-32,
           _planes::little-16, bpp::little-16, compression::little-32, _::binary>> = bin
       ) do
    cond do
      dib_size < 40 ->
        {:error, "未対応の BMP ヘッダ（dib_size=#{dib_size}）"}

      compression != 0 ->
        {:error, "未対応の BMP 圧縮形式: #{compression}"}

      bpp not in [24, 32] ->
        {:error, "未対応の BMP ビット深度: #{bpp}"}

      width <= 0 or height_raw == 0 ->
        {:error, "不正な BMP 寸法: #{width}x#{height_raw}"}

      width > @max_dimension or abs(height_raw) > @max_dimension ->
        {:error, "BMP の寸法が上限（#{@max_dimension}px）を超えています: #{width}x#{height_raw}"}

      width * abs(height_raw) > @max_area ->
        {:error, "BMP の面積が上限（#{@max_area}px）を超えています: #{width}x#{abs(height_raw)}"}

      true ->
        build_image(bin, pixel_offset, width, height_raw, bpp)
    end
  end

  defp parse(_), do: {:error, "BMP ヘッダが不正です"}

  defp build_image(bin, pixel_offset, width, height_raw, bpp) do
    abs_height = abs(height_raw)
    top_down? = height_raw < 0
    bytes_per_pixel = div(bpp, 8)
    pixel_bytes = width * bytes_per_pixel
    # 行は 4 バイト境界へパディング: ((bpp*width + 31) / 32) * 4
    row_stride = div(bpp * width + 31, 32) * 4

    <<_::binary-size(^pixel_offset), pixel_data::binary>> = bin

    rows =
      for row_index <- 0..(abs_height - 1) do
        skip = row_index * row_stride
        <<_::binary-size(^skip), row::binary-size(^row_stride), _::binary>> = pixel_data
        <<pixels::binary-size(^pixel_bytes), _padding::binary>> = row
        bgr_to_rgb(pixels, bpp)
      end

    # ボトムアップ格納は最終行が画像最上段。トップダウンはそのまま。
    ordered = if top_down?, do: rows, else: Enum.reverse(rows)
    rgb = IO.iodata_to_binary(ordered)

    Image.new_from_binary(rgb, width, abs_height, 3, :VIPS_FORMAT_UCHAR)
  end

  # BMP は BGR(A) 順。RGB 順へ詰め替える（32bit は第 4 バイトを破棄）。
  defp bgr_to_rgb(pixels, 24), do: for(<<b, g, r <- pixels>>, into: <<>>, do: <<r, g, b>>)
  defp bgr_to_rgb(pixels, 32), do: for(<<b, g, r, _x <- pixels>>, into: <<>>, do: <<r, g, b>>)
end
