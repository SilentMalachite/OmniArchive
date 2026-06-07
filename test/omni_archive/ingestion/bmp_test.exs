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
