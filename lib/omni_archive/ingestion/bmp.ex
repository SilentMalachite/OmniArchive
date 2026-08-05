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
  - **ヘッダ先行検証**: `decode_file/1` は固定長ヘッダ（54 バイト）だけを読んで
    寸法・ビット深度・圧縮形式を検証し、棄却対象のファイルは本体を一切読まない。
    ファイル全体を先に読むと、最終的に寸法超過で拒否する入力でもファイルサイズ
    分のメモリを確保してしまい、上限チェック自体が OOM 経路になる。
    合格後はピクセル行を逐次読み込み、生ファイルと RGB を同時に保持しない。
  """

  alias Vix.Vips.Image

  # クロップ経路（ImageProcessor）と同じ上限を BMP デコードにも適用する。
  @max_dimension 20_000
  @max_area 100_000_000

  # BITMAPFILEHEADER(14) + BITMAPINFOHEADER(40)。妥当な BMP は必ずこれ以上ある。
  @header_bytes 54

  @doc """
  BMP ファイルを vix 画像へデコードする。

  ヘッダのみを読んで検証し、合格した場合だけピクセルデータを行単位で読み込む。

  ## 戻り値
    - `{:ok, %Vix.Vips.Image{}}` 成功
    - `:not_bmp` BMP シグネチャ（"BM"）ではない
    - `{:error, reason}` 破損・非対応変種・読み込み失敗
  """
  @spec decode_file(Path.t()) :: {:ok, Image.t()} | :not_bmp | {:error, term()}
  def decode_file(path) do
    case File.open(path, [:read, :binary, :raw, {:read_ahead, 65_536}]) do
      {:ok, io} ->
        try do
          decode_io(io)
        rescue
          e -> {:error, "BMP の解析に失敗: #{Exception.message(e)}"}
        after
          File.close(io)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  BMP バイナリを vix 画像へデコードする。戻り値は `decode_file/1` と同じ。
  """
  @spec decode(binary()) :: {:ok, Image.t()} | :not_bmp | {:error, term()}
  def decode(<<"BM", _::binary>> = bin) do
    with {:ok, info} <- parse_header(bin) do
      build_from_binary(bin, info)
    end
  rescue
    e -> {:error, "BMP の解析に失敗: #{Exception.message(e)}"}
  end

  def decode(_), do: :not_bmp

  # 固定長ヘッダだけを読んで検証し、合格時のみピクセルデータへ進む。
  defp decode_io(io) do
    case :file.read(io, @header_bytes) do
      {:ok, <<"BM", _::binary>> = header} when byte_size(header) == @header_bytes ->
        with {:ok, info} <- parse_header(header), do: read_pixels(io, info)

      {:ok, <<"BM", _::binary>>} ->
        {:error, "BMP ヘッダが不正です"}

      {:ok, _other} ->
        :not_bmp

      :eof ->
        :not_bmp

      {:error, reason} ->
        {:error, reason}
    end
  end

  # BITMAPFILEHEADER(14) + BITMAPINFOHEADER 先頭フィールド。
  # width/height/planes/bpp/compression のオフセットは BITMAPINFOHEADER 以降の
  # 全バージョンで共通。ピクセル位置は dib_size ではなく pixel_offset で解決する
  # ため、V4/V5 のような大きい DIB ヘッダでも正しく扱える。
  defp parse_header(
         <<"BM", _fsize::little-32, _r1::little-16, _r2::little-16, pixel_offset::little-32,
           dib_size::little-32, width::little-signed-32, height_raw::little-signed-32,
           _planes::little-16, bpp::little-16, compression::little-32, _::binary>>
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
        {:ok, %{pixel_offset: pixel_offset, width: width, height_raw: height_raw, bpp: bpp}}
    end
  end

  defp parse_header(_), do: {:error, "BMP ヘッダが不正です"}

  # 検証済みヘッダに従い、ピクセル行を逐次読み込んで RGB へ詰め替える。
  defp read_pixels(io, %{pixel_offset: pixel_offset} = info) do
    %{width: width, height_raw: height_raw, bpp: bpp} = info
    abs_height = abs(height_raw)
    pixel_bytes = width * div(bpp, 8)
    # 行は 4 バイト境界へパディング: ((bpp*width + 31) / 32) * 4
    row_stride = div(bpp * width + 31, 32) * 4

    with {:ok, _pos} <- :file.position(io, {:bof, pixel_offset}),
         {:ok, rows} <- read_rows(io, abs_height, row_stride, pixel_bytes, bpp, []) do
      # rows はファイル格納順の逆順で積まれている。ボトムアップ格納
      # （height > 0）は最終行が画像最上段なので、この逆順がそのまま
      # 上から下の並びになる。トップダウンのときだけ戻す。
      ordered = if height_raw < 0, do: Enum.reverse(rows), else: rows

      Image.new_from_binary(
        IO.iodata_to_binary(ordered),
        width,
        abs_height,
        3,
        :VIPS_FORMAT_UCHAR
      )
    end
  end

  defp read_rows(_io, 0, _row_stride, _pixel_bytes, _bpp, acc), do: {:ok, acc}

  defp read_rows(io, remaining, row_stride, pixel_bytes, bpp, acc) do
    case :file.read(io, row_stride) do
      {:ok, <<pixels::binary-size(^pixel_bytes), _padding::binary>> = row}
      when byte_size(row) == row_stride ->
        read_rows(io, remaining - 1, row_stride, pixel_bytes, bpp, [
          bgr_to_rgb(pixels, bpp) | acc
        ])

      {:error, reason} ->
        {:error, reason}

      _short_read ->
        {:error, "BMP のピクセルデータが不足しています"}
    end
  end

  # バイナリ入力版（decode/1）。全量がすでにメモリ上にあるためスライスで取り出す。
  defp build_from_binary(bin, %{pixel_offset: pixel_offset} = info) do
    %{width: width, height_raw: height_raw, bpp: bpp} = info
    abs_height = abs(height_raw)
    pixel_bytes = width * div(bpp, 8)
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
    ordered = if height_raw < 0, do: rows, else: Enum.reverse(rows)

    Image.new_from_binary(IO.iodata_to_binary(ordered), width, abs_height, 3, :VIPS_FORMAT_UCHAR)
  end

  # BMP は BGR(A) 順。RGB 順へ詰め替える（32bit は第 4 バイトを破棄）。
  defp bgr_to_rgb(pixels, 24), do: for(<<b, g, r <- pixels>>, into: <<>>, do: <<r, g, b>>)
  defp bgr_to_rgb(pixels, 32), do: for(<<b, g, r, _x <- pixels>>, into: <<>>, do: <<r, g, b>>)
end
