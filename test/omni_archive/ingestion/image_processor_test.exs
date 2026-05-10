defmodule OmniArchive.Ingestion.ImageProcessorTest do
  @moduledoc """
  ImageProcessor のクロップ処理テスト。
  ポリゴン境界色サンプリング・Gaussian feathering の出力が
  期待形式（PNG バイナリ）になることを検証します。
  """
  use ExUnit.Case, async: true

  alias OmniArchive.Ingestion.ImageProcessor

  @sample_png "priv/static/images/lab_wizard.png"

  describe "crop_to_binary/2 矩形クロップ" do
    test "PNG バイナリを返す（JPEG ではない）" do
      geometry = %{"x" => 50, "y" => 50, "width" => 100, "height" => 100}

      assert {:ok, binary} = ImageProcessor.crop_to_binary(@sample_png, geometry)
      assert byte_size(binary) > 0
      # PNG マジックバイト
      assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = binary
    end
  end

  describe "crop_to_binary/2 ポリゴンクロップ（境界色 + Gaussian feathering）" do
    test "PNG バイナリを返す" do
      points = [
        %{"x" => 50, "y" => 50},
        %{"x" => 200, "y" => 50},
        %{"x" => 200, "y" => 200},
        %{"x" => 50, "y" => 200}
      ]

      assert {:ok, binary} = ImageProcessor.crop_to_binary(@sample_png, %{"points" => points})
      assert byte_size(binary) > 0
      assert <<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = binary
    end

    test "極小ポリゴン（3 頂点）でも正常に処理する" do
      points = [
        %{"x" => 10, "y" => 10},
        %{"x" => 30, "y" => 10},
        %{"x" => 20, "y" => 30}
      ]

      assert {:ok, binary} = ImageProcessor.crop_to_binary(@sample_png, %{"points" => points})
      assert byte_size(binary) > 0
    end
  end

  describe "crop_image/3 ポリゴン書き出し" do
    @tag :tmp_dir
    test "PNG ファイルとして保存される", %{tmp_dir: tmp_dir} do
      output_path = Path.join(tmp_dir, "polygon_out.png")

      points = [
        %{"x" => 30, "y" => 30},
        %{"x" => 150, "y" => 30},
        %{"x" => 150, "y" => 150},
        %{"x" => 30, "y" => 150}
      ]

      assert :ok = ImageProcessor.crop_image(@sample_png, %{"points" => points}, output_path)
      assert File.exists?(output_path)

      # 出力ファイルの先頭が PNG マジックバイトであることを確認
      <<header::binary-size(8), _rest::binary>> = File.read!(output_path)
      assert header == <<137, 80, 78, 71, 13, 10, 26, 10>>
    end
  end
end
