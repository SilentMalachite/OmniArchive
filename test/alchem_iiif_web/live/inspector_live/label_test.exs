defmodule AlchemIiifWeb.InspectorLive.LabelTest do
  @moduledoc """
  Label LiveView のテスト。

  ウィザード Step 4 のラベリング画面をテストします。
  マウント時の初期表示、メタデータ入力、Auto-Save、
  Undo 機能、ナビゲーションを検証します。
  """
  use AlchemIiifWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  setup :register_and_log_in_user

  # ヘルパー: ログインユーザー所有の PdfSource + ExtractedImage を作成
  defp create_user_image(user, overrides \\ %{}) do
    pdf_source = insert_pdf_source(%{user_id: user.id})
    insert_extracted_image(Map.put(overrides, :pdf_source_id, pdf_source.id))
  end

  describe "マウント" do
    test "初期状態でステップ4が表示される", %{conn: conn, user: user} do
      image =
        create_user_image(user, %{
          caption: "テスト土器第3図",
          label: "fig-3-1",
          site: "テスト市遺跡",
          period: "縄文時代",
          artifact_type: "土器"
        })

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      # ステップ4（ラベリング）が表示される
      assert html =~ "ラベリング"
      assert html =~ "いまここ"
      assert html =~ "4 / 5"
    end

    test "既存のメタデータが入力フィールドに表示される", %{conn: conn, user: user} do
      image =
        create_user_image(user, %{
          caption: "テスト土器第3図",
          label: "fig-3-1",
          site: "テスト市遺跡",
          period: "縄文時代",
          artifact_type: "土器"
        })

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      assert html =~ "テスト土器第3図"
      assert html =~ "fig-3-1"
      assert html =~ "テスト市遺跡"
      assert html =~ "縄文時代"
      assert html =~ "土器"
    end

    test "メタデータが空の場合でも正常に表示される", %{conn: conn, user: user} do
      image =
        create_user_image(user, %{
          caption: nil,
          label: nil,
          site: nil,
          period: nil,
          artifact_type: nil
        })

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      # フォームが表示される
      assert html =~ "図版の情報を入力してください"
      assert html =~ "キャプション"
    end
  end

  describe "ナビゲーション" do
    test "戻るリンクがクロップ画面を指す", %{conn: conn, user: user} do
      image = create_user_image(user)

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      assert html =~ "← 戻る"
      assert html =~ "/lab/crop/#{image.pdf_source_id}/#{image.page_number}"
    end

    test "保存して次の図版へボタンが表示される", %{conn: conn, user: user} do
      image = create_user_image(user)

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      assert html =~ "保存して次の図版へ"
    end

    test "保存して終了ボタンが表示される", %{conn: conn, user: user} do
      image = create_user_image(user)

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      assert html =~ "保存して終了"
    end

    test "save continue で Browse 画面に遷移し status が pending_review になる", %{conn: conn, user: user} do
      image = create_user_image(user)

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{image.id}")

      assert {:error, {:live_redirect, %{to: path}}} =
               view |> element(".btn-save-continue") |> render_click()

      assert path =~ "/lab/browse/#{image.pdf_source_id}"

      # DB 上で status が pending_review に更新されていることを確認
      updated = AlchemIiif.Ingestion.get_extracted_image!(image.id)
      assert updated.status == "pending_review"
    end

    test "save finish で Lab ダッシュボードに遷移する", %{conn: conn, user: user} do
      image = create_user_image(user)

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{image.id}")

      assert {:error, {:live_redirect, %{to: "/lab"}}} =
               view |> element(".btn-save-finish") |> render_click()
    end

    test "geometry nil の場合、保存がブロックされる", %{conn: conn, user: user} do
      image = create_user_image(user, %{geometry: nil})

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{image.id}")

      # 保存しようとするとブロックされる（ページ遷移しない）
      view |> element(".btn-save-finish") |> render_click()

      # ページ遷移せず同じ画面に留まることを検証
      html = render(view)
      assert html =~ "図版の情報を入力してください"

      # DB 上の status が draft のまま（pending_review に変更されていない）
      unchanged = AlchemIiif.Ingestion.get_extracted_image!(image.id)
      assert unchanged.status == "draft"
    end
  end

  describe "Undo 機能" do
    test "Undo スタックが空の場合ボタンが無効", %{conn: conn, user: user} do
      image = create_user_image(user)

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{image.id}")

      assert has_element?(view, "button.btn-undo[disabled]")
    end
  end

  describe "重複ラベル検出" do
    test "同一 PDF 内で重複ラベルがある場合に警告が表示される", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{user_id: user.id})

      # 1つ目のレコード — ラベル fig-1-1 で保存
      _existing =
        insert_extracted_image(%{
          pdf_source_id: pdf_source.id,
          label: "fig-1-1",
          site: "重複検出テスト市遺跡",
          caption: "既存の図版"
        })

      # 2つ目のレコード — 同じ pdf_source_id でラベル未設定
      current =
        insert_extracted_image(%{
          pdf_source_id: pdf_source.id,
          site: "重複検出テスト市遺跡",
          label: nil,
          page_number: 2
        })

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{current.id}")

      # ラベル入力で同じ fig-1-1 を入力（blur イベント）
      view
      |> element("#label-input")
      |> render_blur(%{"field" => "label", "value" => "fig-1-1"})

      html = render(view)
      assert html =~ "この遺跡でそのラベルは既に登録されています"
      assert html =~ "既存レコードを更新"
    end

    test "異なる PDF では重複として扱わない", %{conn: conn, user: user} do
      # PDF A のレコード
      pdf_a = insert_pdf_source(%{user_id: user.id})

      _image_a =
        insert_extracted_image(%{
          pdf_source_id: pdf_a.id,
          label: "fig-1-1",
          site: "別PDFテスト市遺跡",
          caption: "PDF A の図版"
        })

      # PDF B のレコード（別の pdf_source）
      pdf_b = insert_pdf_source(%{user_id: user.id})

      image_b =
        insert_extracted_image(%{
          pdf_source_id: pdf_b.id,
          label: nil,
          page_number: 1
        })

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{image_b.id}")

      # 同じラベルを入力しても別 PDF なので重複にならない
      view
      |> element("#label-input")
      |> render_blur(%{"field" => "label", "value" => "fig-1-1"})

      html = render(view)
      refute html =~ "この遺跡でそのラベルは既に登録されています"
    end

    test "空ラベルでは重複警告が出ない", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{user_id: user.id})

      _existing =
        insert_extracted_image(%{
          pdf_source_id: pdf_source.id,
          label: ""
        })

      current =
        insert_extracted_image(%{
          pdf_source_id: pdf_source.id,
          label: nil,
          page_number: 2
        })

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{current.id}")

      # 空文字を入力
      view
      |> element("#label-input")
      |> render_blur(%{"field" => "label", "value" => ""})

      html = render(view)
      refute html =~ "この遺跡でそのラベルは既に登録されています"
    end

    test "重複がある状態で保存して終了がブロックされる", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{user_id: user.id})

      _existing =
        insert_extracted_image(%{
          pdf_source_id: pdf_source.id,
          label: "fig-1-1",
          site: "ブロックテスト市遺跡"
        })

      # current は別のラベルで作成（DB 制約回避）
      current =
        insert_extracted_image(%{
          pdf_source_id: pdf_source.id,
          site: "ブロックテスト市遺跡",
          label: nil,
          page_number: 2
        })

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{current.id}")

      # 重複ラベルを入力して duplicate_record をセット
      view
      |> element("#label-input")
      |> render_blur(%{"field" => "label", "value" => "fig-1-1"})

      # save finish を押しても遷移しない（ブロックされる）
      html =
        view
        |> element(".btn-save-finish")
        |> render_click()

      # ページ遷移せず重複警告が表示されたまま
      assert html =~ "この遺跡でそのラベルは既に登録されています"
      assert html =~ "既存レコードを更新"
    end

    test "マージボタンで既存レコードの編集画面に遷移する", %{conn: conn, user: user} do
      pdf_source = insert_pdf_source(%{user_id: user.id})

      existing =
        insert_extracted_image(%{
          pdf_source_id: pdf_source.id,
          label: "fig-1-1",
          site: "マージテスト市遺跡",
          caption: "既存の図版"
        })

      # current は別のラベルで作成（DB 制約回避）
      current =
        insert_extracted_image(%{
          pdf_source_id: pdf_source.id,
          site: "マージテスト市遺跡",
          label: nil,
          page_number: 2
        })

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{current.id}")

      # 重複ラベルを入力して duplicate_record をセット
      view
      |> element("#label-input")
      |> render_blur(%{"field" => "label", "value" => "fig-1-1"})

      # マージボタンをクリック
      assert {:error, {:live_redirect, %{to: path}}} =
               view |> element(".btn-merge") |> render_click()

      assert path =~ "/lab/label/#{existing.id}"
    end
  end
end
