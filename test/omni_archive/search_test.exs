defmodule OmniArchive.SearchTest do
  use OmniArchive.DataCase, async: true

  alias OmniArchive.Search
  import OmniArchive.Factory

  # テストデータのセットアップヘルパー
  defp create_test_images do
    pdf = insert_pdf_source()

    img1 =
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 1,
        caption: "第1図 縄文土器出土状況",
        label: "fig-1-1",
        status: "published",
        ptif_path: "/path/to/test1.tif"
      })

    img2 =
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 2,
        caption: "第2図 弥生時代の銅鉛",
        label: "fig-2-1",
        status: "published",
        ptif_path: "/path/to/test2.tif"
      })

    img3 =
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 3,
        caption: "第3図 下書きの図版",
        label: "fig-3-1",
        status: "draft",
        ptif_path: "/path/to/test3.tif"
      })

    %{img1: img1, img2: img2, img3: img3}
  end

  describe "search_images/2" do
    test "PTIF ありの全画像を返す（フィルターなし）" do
      %{img1: img1, img2: img2, img3: img3} = create_test_images()

      results = Search.search_images()
      ids = Enum.map(results, & &1.id)

      assert img1.id in ids
      assert img2.id in ids
      assert img3.id in ids
    end

    test "PTIF なしの画像を除外する" do
      _no_ptif = insert_extracted_image(%{ptif_path: nil, status: "published"})

      results = Search.search_images()
      assert Enum.empty?(results)
    end

    test "テキスト検索でキャプションにマッチする" do
      create_test_images()

      results = Search.search_images("縄文土器")
      assert results != []
      assert Enum.any?(results, &(&1.label == "fig-1-1"))
    end

    test "テキスト検索でラベルにマッチする" do
      create_test_images()

      results = Search.search_images("fig-2-1")
      assert results != []
      assert Enum.any?(results, &(&1.label == "fig-2-1"))
    end

    test "空文字列のフィルターは無視される" do
      %{img1: _, img2: _, img3: _} = create_test_images()

      results_with_empty = Search.search_images("", %{"site" => ""})
      results_without = Search.search_images()

      assert length(results_with_empty) == length(results_without)
    end

    test "nil のフィルターは無視される" do
      %{img1: _, img2: _, img3: _} = create_test_images()

      results_with_nil = Search.search_images("", %{"site" => nil})
      results_without = Search.search_images()

      assert length(results_with_nil) == length(results_without)
    end
  end

  describe "search_published_images/2" do
    test "published 画像のみを返す" do
      %{img1: _, img2: _, img3: _} = create_test_images()

      results = Search.search_published_images()
      assert Enum.all?(results, &(&1.status == "published"))
    end

    test "draft 画像を含まない" do
      %{img3: img3} = create_test_images()

      results = Search.search_published_images()
      ids = Enum.map(results, & &1.id)
      refute img3.id in ids
    end

    test "テキスト検索が published 画像にのみ適用される" do
      create_test_images()

      results = Search.search_published_images("弥生時代")
      assert Enum.all?(results, &(&1.status == "published"))
    end
  end

  describe "list_filter_options/0" do
    test "空のフィルターオプションを返す" do
      create_test_images()

      options = Search.list_filter_options()
      assert options.sites == []
      assert options.periods == []
      assert options.artifact_types == []
    end
  end

  describe "count_results/2" do
    test "全結果件数を返す" do
      create_test_images()

      count = Search.count_results()
      assert count >= 3
    end

    test "テキスト検索の結果件数を返す" do
      create_test_images()

      count = Search.count_results("弥生時代")
      assert count >= 1
    end
  end
end
