defmodule OmniArchive.SearchTest do
  use OmniArchive.DataCase, async: false

  alias OmniArchive.DomainProfiles.GeneralArchive
  alias OmniArchive.Repo
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
        site: "吉野ヶ里町遺跡",
        period: "縄文時代",
        artifact_type: "土器",
        status: "published",
        ptif_path: "/path/to/test1.tif"
      })

    img2 =
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 2,
        caption: "第2図 弥生時代の銅鉛",
        label: "fig-2-1",
        site: "静岡市登呂遺跡",
        period: "弥生時代",
        artifact_type: "銅鉛",
        status: "published",
        ptif_path: "/path/to/test2.tif"
      })

    img3 =
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 3,
        caption: "第3図 下書きの図版",
        label: "fig-3-1",
        site: "吉野ヶ里町遺跡",
        period: "縄文時代",
        artifact_type: "石器",
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

    test "テキスト検索で遺跡名にマッチする" do
      create_test_images()

      results = Search.search_images("静岡市登呂遺跡")
      assert results != []
      assert Enum.any?(results, &(&1.site == "静岡市登呂遺跡"))
    end

    test "テキスト検索で metadata 保存された profile フィールドにマッチする" do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/test.tif",
          site: "旧サイト市遺跡",
          period: "旧時代",
          artifact_type: "旧種別",
          metadata: %{
            "site" => "新サイト市遺跡",
            "period" => "新時代",
            "artifact_type" => "新種別"
          }
        })

      results = Search.search_images("新時代")
      assert Enum.any?(results, &(&1.id == image.id))
    end

    test "site フィルターで絞り込みできる" do
      create_test_images()

      results = Search.search_images("", %{"site" => "吉野ヶ里町遺跡"})
      assert Enum.all?(results, &(&1.site == "吉野ヶ里町遺跡"))
    end

    test "period フィルターで絞り込みできる" do
      create_test_images()

      results = Search.search_images("", %{"period" => "弥生時代"})
      assert length(results) == 1
      assert hd(results).period == "弥生時代"
    end

    test "artifact_type フィルターで絞り込みできる" do
      create_test_images()

      results = Search.search_images("", %{"artifact_type" => "土器"})
      assert Enum.all?(results, &(&1.artifact_type == "土器"))
    end

    test "複数フィルターの組み合わせで絞り込みできる" do
      create_test_images()

      results =
        Search.search_images("", %{
          "site" => "吉野ヶ里町遺跡",
          "period" => "縄文時代"
        })

      assert Enum.all?(results, fn img ->
               img.site == "吉野ヶ里町遺跡" and img.period == "縄文時代"
             end)
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

    test "metadata の値を優先して site フィルターに使う" do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/test.tif",
          site: "旧サイト市遺跡",
          period: "旧時代",
          artifact_type: "旧種別"
        })

      Repo.query!(
        """
        UPDATE extracted_images
        SET metadata = jsonb_build_object('site', $1::text, 'period', $2::text, 'artifact_type', $3::text)
        WHERE id = $4
        """,
        ["新サイト市遺跡", "新時代", "新種別", image.id]
      )

      results = Search.search_images("", %{"site" => "新サイト市遺跡"})
      assert Enum.any?(results, &(&1.id == image.id))
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

      results = Search.search_published_images("吉野ヶ里")
      assert Enum.all?(results, &(&1.status == "published"))
    end
  end

  describe "list_filter_options/0" do
    test "利用可能なフィルターオプションを field 名キーで返す" do
      create_test_images()

      options = Search.list_filter_options()
      assert is_list(options.site)
      assert is_list(options.period)
      assert is_list(options.artifact_type)
    end

    test "データがない場合は空リストを返す" do
      options = Search.list_filter_options()
      assert options.site == []
      assert options.period == []
      assert options.artifact_type == []
    end

    test "DISTINCT な値のみを返す" do
      create_test_images()

      options = Search.list_filter_options()
      # 吉野ヶ里町遺跡は2回登録されているが、1回のみ出力
      assert Enum.count(options.site, &(&1 == "吉野ヶ里町遺跡")) == 1
    end
  end

  describe "count_results/2" do
    test "全結果件数を返す" do
      create_test_images()

      count = Search.count_results()
      assert count == 3
    end

    test "テキスト検索の結果件数を返す" do
      create_test_images()

      count = Search.count_results("静岡市登呂遺跡")
      assert count >= 1
    end

    test "フィルター適用時の結果件数を返す" do
      create_test_images()

      count = Search.count_results("", %{"period" => "弥生時代"})
      assert count == 1
    end
  end

  describe "GeneralArchive metadata-only fields" do
    setup do
      put_domain_profile(GeneralArchive)
      :ok
    end

    test "metadata-only field で検索と filter options が動く" do
      image =
        insert_extracted_image(%{
          caption: "市史写真",
          label: "photo-001",
          ptif_path: "/path/to/general.tif",
          site: "旧サイト値",
          metadata: %{
            "collection" => "広報写真アーカイブ",
            "item_type" => "写真",
            "date_note" => "1960年代"
          }
        })

      assert Enum.any?(Search.search_images("広報写真", %{}), &(&1.id == image.id))

      assert Enum.any?(
               Search.search_images("", %{"collection" => "広報写真アーカイブ"}),
               &(&1.id == image.id)
             )

      assert Enum.any?(Search.search_images("", %{"item_type" => "写真"}), &(&1.id == image.id))
      assert Enum.any?(Search.search_images("", %{"date_note" => "1960年代"}), &(&1.id == image.id))

      options = Search.list_filter_options()
      assert options.collection == ["広報写真アーカイブ"]
      assert options.item_type == ["写真"]
      assert options.date_note == ["1960年代"]
    end

    test "metadata-only field を使って count_results/2 できる" do
      insert_extracted_image(%{
        caption: "館報",
        label: "doc-2024-05",
        ptif_path: "/path/to/general-count.tif",
        metadata: %{
          "collection" => "市史資料",
          "item_type" => "冊子",
          "date_note" => "2024年5月"
        }
      })

      assert Search.count_results("", %{"collection" => "市史資料"}) == 1
    end

    test "duplicate label が collection + label で検出される" do
      existing =
        insert_extracted_image(%{
          label: "photo-001",
          metadata: %{"collection" => "広報写真アーカイブ"},
          ptif_path: "/path/to/duplicate-general.tif"
        })

      duplicate =
        OmniArchive.Ingestion.find_duplicate_extracted_image(
          %OmniArchive.Ingestion.ExtractedImage{},
          %{
            label: "photo-001",
            metadata: %{"collection" => "広報写真アーカイブ"}
          }
        )

      assert duplicate.id == existing.id
    end
  end
end
