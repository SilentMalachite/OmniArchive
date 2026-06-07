defmodule OmniArchive.Ingestion.ZipProcessorTest do
  @moduledoc """
  ZipProcessor の正常系・セキュリティ・容量上限テスト。

  AlchemIIIF v0.3.0 同等の 3 層防御（zip-slip / マジックバイト / 容量上限）と、
  AppleDouble 除外・自然順ソート・ネストディレクトリ平坦化を検証する。
  """
  use ExUnit.Case, async: true

  alias OmniArchive.Ingestion.ZipProcessor

  # 1x1 PNG のバイナリ（マジックバイト + 最小限ヘッダ）
  @png_min <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
             8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 11, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0,
             0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  setup %{tmp_dir: tmp_dir} = ctx do
    output_dir = Path.join(tmp_dir, "out")
    File.mkdir_p!(output_dir)
    Map.put(ctx, :output_dir, output_dir)
  end

  describe "extract_pngs/3 正常系" do
    @tag :tmp_dir
    test "PNG エントリを page-NNN-{ts}.png 形式で展開する", %{tmp_dir: tmp_dir, output_dir: output_dir} do
      zip_path =
        build_zip(tmp_dir, "ok.zip", [
          {"page-001.png", @png_min},
          {"page-002.png", @png_min}
        ])

      assert {:ok, %{page_count: 2, image_paths: paths}} =
               ZipProcessor.extract_pngs(zip_path, output_dir)

      assert length(paths) == 2

      Enum.each(paths, fn path ->
        assert Path.dirname(path) == Path.expand(output_dir)
        assert Regex.match?(~r/page-\d{3}-\d+\.png$/, Path.basename(path))
      end)
    end

    @tag :tmp_dir
    test "ネストディレクトリ内の PNG も平坦化して取り込む",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      zip_path =
        build_zip(tmp_dir, "nested.zip", [
          {"book/chapter1/p1.png", @png_min},
          {"book/chapter2/p2.png", @png_min}
        ])

      assert {:ok, %{page_count: 2, image_paths: paths}} =
               ZipProcessor.extract_pngs(zip_path, output_dir)

      Enum.each(paths, fn path ->
        assert Path.dirname(Path.expand(path)) == Path.expand(output_dir)
      end)

      # ネストの一時ディレクトリは削除されている
      assert Path.wildcard(Path.join(output_dir, "book")) == []
    end

    @tag :tmp_dir
    test "数値を含むファイル名は自然順でソートされる",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      zip_path =
        build_zip(tmp_dir, "natural.zip", [
          {"p10.png", @png_min},
          {"p2.png", @png_min},
          {"p1.png", @png_min}
        ])

      assert {:ok, %{image_paths: paths}} = ZipProcessor.extract_pngs(zip_path, output_dir)

      # page-001 が p1.png 由来、page-002 が p2.png 由来、page-003 が p10.png 由来
      basenames = Enum.map(paths, &Path.basename/1)
      assert Enum.at(basenames, 0) =~ ~r/^page-001-\d+/
      assert Enum.at(basenames, 1) =~ ~r/^page-002-\d+/
      assert Enum.at(basenames, 2) =~ ~r/^page-003-\d+/
    end

    @tag :tmp_dir
    test "AppleDouble メタデータ (__MACOSX/, ._*) は除外される",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      zip_path =
        build_zip(tmp_dir, "applefiles.zip", [
          {"__MACOSX/junk.png", @png_min},
          {"._sidecar.png", @png_min},
          {"page.png", @png_min}
        ])

      assert {:ok, %{page_count: 1, image_paths: paths}} =
               ZipProcessor.extract_pngs(zip_path, output_dir)

      # 残った 1 ファイル（page.png 由来）のみ
      assert length(paths) == 1
    end
  end

  describe "extract_pngs/3 セキュリティ" do
    @tag :tmp_dir
    test "PNG マジックバイトに合致しないファイルは取り込まれず破棄される",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      fake_png = "GIF89a fake content"

      zip_path =
        build_zip(tmp_dir, "fake.zip", [
          {"page1.png", fake_png},
          {"page2.png", @png_min}
        ])

      assert {:ok, %{page_count: 1, image_paths: paths}} =
               ZipProcessor.extract_pngs(zip_path, output_dir)

      assert length(paths) == 1
    end

    @tag :tmp_dir
    test "画像ファイルが 1 件も含まれていない ZIP はエラーを返す",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      zip_path =
        build_zip(tmp_dir, "empty.zip", [
          {"readme.txt", "no images here"}
        ])

      assert {:error, message} = ZipProcessor.extract_pngs(zip_path, output_dir)
      assert message =~ "画像"
    end
  end

  describe "extract_pngs/3 容量上限" do
    @tag :tmp_dir
    test "ページ数上限を超える ZIP はエラーを返す",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      entries = for i <- 1..5, do: {"p#{i}.png", @png_min}
      zip_path = build_zip(tmp_dir, "many.zip", entries)

      assert {:error, message} =
               ZipProcessor.extract_pngs(zip_path, output_dir, %{max_pages: 3})

      assert message =~ "ページ数上限"
    end

    @tag :tmp_dir
    test "展開後サイズ上限を超える ZIP はエラーを返す",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      zip_path = build_zip(tmp_dir, "big.zip", [{"p1.png", @png_min}])

      # PNG ファイルサイズより小さい上限を渡す
      assert {:error, message} =
               ZipProcessor.extract_pngs(zip_path, output_dir, %{max_extracted_bytes: 10})

      assert message =~ "展開後サイズ上限"
    end
  end

  describe "extract_pngs/3 非PNG画像の変換" do
    @tag :tmp_dir
    test "ZIP 内 JPEG は PNG ページに変換される",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      zip_path = build_zip(tmp_dir, "jpg.zip", [{"p1.jpg", image_bytes(".jpg")}])

      assert {:ok, %{page_count: 1, image_paths: [path]}} =
               ZipProcessor.extract_pngs(zip_path, output_dir)

      <<header::binary-size(8), _rest::binary>> = File.read!(path)
      assert header == <<137, 80, 78, 71, 13, 10, 26, 10>>
    end

    @tag :tmp_dir
    test "ZIP 内 PNG は再エンコードされず素通しする（バイト一致）",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      png_bytes = File.read!("priv/static/images/lab_wizard.png")
      zip_path = build_zip(tmp_dir, "pass.zip", [{"page-001.png", png_bytes}])

      assert {:ok, %{page_count: 1, image_paths: [path]}} =
               ZipProcessor.extract_pngs(zip_path, output_dir)

      # 素通し＝rename によるファイル移動のみ。バイト列は入力 PNG と一致する。
      assert File.read!(path) == png_bytes
    end

    @tag :tmp_dir
    test "ZIP 内 TIFF は PNG ページに変換される",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      zip_path = build_zip(tmp_dir, "tif.zip", [{"p1.tif", image_bytes(".tif")}])

      assert {:ok, %{page_count: 1, image_paths: [path]}} =
               ZipProcessor.extract_pngs(zip_path, output_dir)

      <<header::binary-size(8), _rest::binary>> = File.read!(path)
      assert header == <<137, 80, 78, 71, 13, 10, 26, 10>>
    end

    @tag :tmp_dir
    test "PNG・JPEG・TIFF 混在 ZIP は全て PNG ページになる（件数3）",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      png_bytes = File.read!("priv/static/images/lab_wizard.png")

      zip_path =
        build_zip(tmp_dir, "mixed.zip", [
          {"page-001.png", png_bytes},
          {"page-002.jpg", image_bytes(".jpg")},
          {"page-003.tif", image_bytes(".tif")}
        ])

      assert {:ok, %{page_count: 3, image_paths: paths}} =
               ZipProcessor.extract_pngs(zip_path, output_dir)

      assert length(paths) == 3

      Enum.each(paths, fn path ->
        <<header::binary-size(8), _rest::binary>> = File.read!(path)
        assert header == <<137, 80, 78, 71, 13, 10, 26, 10>>
        assert Regex.match?(~r/page-\d{3}-\d+\.png$/, Path.basename(path))
      end)
    end

    @tag :tmp_dir
    test "不良画像が混在しても有効な画像は取り込まれる",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      png_bytes = File.read!("priv/static/images/lab_wizard.png")

      zip_path =
        build_zip(tmp_dir, "mix_bad.zip", [
          {"bad.jpg", "not really a jpeg"},
          {"good.png", png_bytes},
          {"good2.jpg", image_bytes(".jpg")}
        ])

      assert {:ok, %{page_count: 2, image_paths: paths}} =
               ZipProcessor.extract_pngs(zip_path, output_dir)

      assert length(paths) == 2

      Enum.each(paths, fn path ->
        <<header::binary-size(8), _rest::binary>> = File.read!(path)
        assert header == <<137, 80, 78, 71, 13, 10, 26, 10>>
      end)
    end

    @tag :tmp_dir
    test "有効な画像が無い ZIP はエラーを返す",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      zip_path =
        build_zip(tmp_dir, "all_bad.zip", [
          {"bad1.jpg", "xxxx"},
          {"bad2.tif", "yyyy"}
        ])

      assert {:error, message} = ZipProcessor.extract_pngs(zip_path, output_dir)
      assert message =~ "有効な画像"
    end
  end

  describe "extract_pngs/3 ページ採番順" do
    @tag :tmp_dir
    test "出力ページはファイル名（自然順）で採番される（ZIP 格納順に依存しない）",
         %{tmp_dir: tmp_dir, output_dir: output_dir} do
      # 格納順を意図的にシャッフル（p10, p2, p1）し、各画像を識別用に異なる幅で生成。
      # 形式も混在させ、変換後も採番順がファイル名順になることを確認する。
      zip_path =
        build_zip(tmp_dir, "order.zip", [
          {"p10.tif", sized_image_bytes(100, 5, ".tif")},
          {"p2.jpg", sized_image_bytes(22, 5, ".jpg")},
          {"p1.png", sized_image_bytes(11, 5, ".png")}
        ])

      assert {:ok, %{image_paths: paths}} = ZipProcessor.extract_pngs(zip_path, output_dir)

      widths =
        Enum.map(paths, fn path ->
          {:ok, %{width: w}} = OmniArchive.Ingestion.ImageProcessor.get_image_dimensions(path)
          w
        end)

      # page-001=p1（幅11） / page-002=p2（幅22） / page-003=p10（幅100）
      assert widths == [11, 22, 100]
    end
  end

  # === ヘルパ ===

  defp build_zip(tmp_dir, name, entries) do
    zip_path = Path.join(tmp_dir, name)

    file_list =
      Enum.map(entries, fn {entry_name, content} ->
        {String.to_charlist(entry_name), content}
      end)

    {:ok, _} = :zip.create(String.to_charlist(zip_path), file_list)
    zip_path
  end

  # lab_wizard.png を指定形式のバイト列に変換して返す（バイナリ資産をコミットしないため）
  defp image_bytes(suffix) do
    {:ok, img} = Vix.Vips.Image.new_from_file("priv/static/images/lab_wizard.png")
    {:ok, bytes} = Vix.Vips.Image.write_to_buffer(img, suffix)
    bytes
  end

  # 識別用に指定サイズの単色画像を生成して指定形式のバイト列で返す
  defp sized_image_bytes(width, height, suffix) do
    {:ok, image} = Vix.Vips.Operation.black(width, height)
    {:ok, bytes} = Vix.Vips.Image.write_to_buffer(image, suffix)
    bytes
  end
end
