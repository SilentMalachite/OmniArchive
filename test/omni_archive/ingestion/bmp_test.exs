defmodule OmniArchive.Ingestion.BmpTest do
  @moduledoc """
  pure Elixir BMP デコーダの単体テスト。
  寸法・ピクセル色・ボトムアップ格納の正しさと、非対応/破損入力の安全な拒否を検証する。
  """
  use ExUnit.Case, async: true

  alias OmniArchive.BmpFixture
  alias OmniArchive.Ingestion.Bmp
  alias Vix.Vips.Image
  alias Vix.Vips.Operation

  # スパースファイルで用意する見かけ上のファイルサイズ（実ディスク消費はほぼ 0）
  @sparse_bytes 192 * 1024 * 1024

  describe "decode/1" do
    test "24bit ボトムアップ BMP を正しい寸法・色でデコードする" do
      # トップダウン指定: (0,0)=赤 (1,0)=緑 / (0,1)=青 (1,1)=白
      rows = [
        [{255, 0, 0}, {0, 255, 0}],
        [{0, 0, 255}, {255, 255, 255}]
      ]

      bmp = BmpFixture.encode(2, 2, rows)

      assert {:ok, img} = Bmp.decode(bmp)
      assert Image.width(img) == 2
      assert Image.height(img) == 2
      assert Image.bands(img) == 3

      assert pixel(img, 0, 0) == {255, 0, 0}
      assert pixel(img, 1, 0) == {0, 255, 0}
      assert pixel(img, 0, 1) == {0, 0, 255}
      assert pixel(img, 1, 1) == {255, 255, 255}
    end

    test "トップダウン BMP（height < 0）を正しい行順でデコードする" do
      rows = [
        [{255, 0, 0}, {0, 255, 0}],
        [{0, 0, 255}, {255, 255, 255}]
      ]

      bmp = BmpFixture.encode(2, 2, rows, top_down: true)

      assert {:ok, img} = Bmp.decode(bmp)
      assert pixel(img, 0, 0) == {255, 0, 0}
      assert pixel(img, 1, 0) == {0, 255, 0}
      assert pixel(img, 0, 1) == {0, 0, 255}
      assert pixel(img, 1, 1) == {255, 255, 255}
    end

    test "32bit BMP をデコードし、アルファを破棄して 3 バンド RGB を返す" do
      rows = [[{10, 20, 30}, {40, 50, 60}]]

      bmp = BmpFixture.encode(2, 1, rows, bpp: 32)

      assert {:ok, img} = Bmp.decode(bmp)
      assert Image.bands(img) == 3
      assert pixel(img, 0, 0) == {10, 20, 30}
      assert pixel(img, 1, 0) == {40, 50, 60}
    end

    test "BMP シグネチャでないデータは :not_bmp を返す" do
      assert :not_bmp = Bmp.decode("this is not a bmp file")
    end

    test "寸法上限を超える BMP は {:error, _} を返す（メモリ保護）" do
      # width=30000 (>20000px) のヘッダのみ。build_image 前にガードで弾く。
      assert {:error, message} = Bmp.decode(bmp_header(30_000, 10, 24, 0))
      assert message =~ "寸法"
    end

    test "未対応の圧縮形式（RLE）は {:error, _} を返す" do
      assert {:error, _reason} = Bmp.decode(bmp_with_compression(1))
    end

    test "未対応のビット深度（8bit）は {:error, _} を返す" do
      assert {:error, _reason} = Bmp.decode(bmp_with_bpp(8))
    end

    test "破損した（切り詰められた）BMP は raise せず {:error, _} を返す" do
      truncated = binary_part(BmpFixture.solid(4, 4), 0, 30)
      assert {:error, _reason} = Bmp.decode(truncated)
    end
  end

  describe "decode_file/1" do
    @tag :tmp_dir
    test "有効な BMP ファイルをデコードする", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "solid.bmp")
      File.write!(path, BmpFixture.solid(8, 6, {200, 100, 50}))

      assert {:ok, img} = Bmp.decode_file(path)
      assert Image.width(img) == 8
      assert Image.height(img) == 6
      assert pixel(img, 0, 0) == {200, 100, 50}
    end

    @tag :tmp_dir
    test "BMP でないファイルは :not_bmp を返す", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "not_bmp.dat")
      File.write!(path, "this is definitely not a bitmap")

      assert :not_bmp = Bmp.decode_file(path)
    end

    @tag :tmp_dir
    test "ピクセルデータが不足したファイルは {:error, _} を返す", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "truncated.bmp")
      full = BmpFixture.solid(8, 6)
      File.write!(path, binary_part(full, 0, byte_size(full) - 20))

      assert {:error, _reason} = Bmp.decode_file(path)
    end

    @tag :tmp_dir
    test "ヘッダが不正な巨大ファイルを全量メモリへ読み込まない（メモリ保護）", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "huge_invalid.bmp")
      # dib_size=0 の不正ヘッダ。検証はヘッダだけで完結するため、
      # 後続の巨大な本体を読み込む理由はない。
      File.write!(path, invalid_header())
      append_sparse_bytes(path, @sparse_bytes)
      assert File.stat!(path).size > @sparse_bytes

      {result, peak_binary_bytes} = measure_peak_binary(fn -> Bmp.decode_file(path) end)

      assert {:error, _reason} = result

      assert peak_binary_bytes < 32 * 1024 * 1024,
             "デコードプロセスが #{peak_binary_bytes} バイトのバイナリを保持しました（ファイル全量の読み込み）"
    end
  end

  # dib_size=0（BITMAPINFOHEADER 未満）でヘッダ検証のみで棄却できる BMP
  defp invalid_header do
    <<"BM", 0::little-32, 0::little-16, 0::little-16, 54::little-32, 0::little-32,
      4::little-signed-32, 4::little-signed-32, 1::little-16, 24::little-16, 0::little-32>> <>
      :binary.copy(<<0>>, 20)
  end

  # 末尾に 1 バイト書き込んでファイルサイズだけを膨らませる（スパース領域）
  defp append_sparse_bytes(path, bytes) do
    {:ok, io} = :file.open(String.to_charlist(path), [:read, :write, :binary])
    :ok = :file.pwrite(io, bytes, <<0>>)
    :ok = :file.close(io)
  end

  # fun を別プロセスで実行し、そのプロセスが保持した refc バイナリの最大量を返す。
  # 「ファイル全量をメモリへ載せたか」をプロセス局所に観測できる。
  defp measure_peak_binary(fun) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        result = fun.()

        # 観測ウィンドウを確保する（保持中のバイナリは GC まで一覧に残る）
        Process.sleep(50)
        send(parent, {:measured, result})
      end)

    peak = poll_peak_binary(pid, 0)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      60_000 -> flunk("デコードプロセスが終了しませんでした")
    end

    result =
      receive do
        {:measured, result} -> result
      after
        1_000 -> flunk("デコード結果を受信できませんでした")
      end

    {result, peak}
  end

  defp poll_peak_binary(pid, peak) do
    case :erlang.process_info(pid, :binary) do
      {:binary, binaries} ->
        current = Enum.reduce(binaries, 0, fn info, acc -> acc + elem(info, 1) end)
        poll_peak_binary(pid, max(peak, current))

      _dead ->
        peak
    end
  end

  defp pixel(img, x, y) do
    {:ok, [r, g, b | _]} = Operation.getpoint(img, x, y)
    {round(r), round(g), round(b)}
  end

  # 16 バイトのダミーピクセルを持つ 2x2 BMP ヘッダを、指定 compression で生成
  defp bmp_with_compression(compression) do
    bmp_header(2, 2, 24, compression) <> :binary.copy(<<0>>, 16)
  end

  # 指定ビット深度（24以外で非対応を誘発）の最小 BMP
  defp bmp_with_bpp(bpp) do
    bmp_header(2, 2, bpp, 0) <> :binary.copy(<<0>>, 16)
  end

  defp bmp_header(width, height, bpp, compression) do
    offset = 54

    dib =
      <<40::little-32, width::little-signed-32, height::little-signed-32, 1::little-16,
        bpp::little-16, compression::little-32, 16::little-32, 2835::little-32, 2835::little-32,
        0::little-32, 0::little-32>>

    <<"BM", offset + 16::little-32, 0::little-16, 0::little-16, offset::little-32>> <> dib
  end
end
