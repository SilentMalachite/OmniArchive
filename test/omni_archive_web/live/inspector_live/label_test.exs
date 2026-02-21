defmodule OmniArchiveWeb.InspectorLive.LabelTest do
  @moduledoc """
  Label LiveView のテスト。

  ウィザード Step 4 のラベリング画面をテストします。
  マウント時の初期表示、メタデータ入力、Auto-Save、
  Undo 機能、ナビゲーションを検証します。
  """
  use OmniArchiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import OmniArchive.Factory

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
          label: "fig-3-1"
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
          label: "fig-3-1"
        })

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      assert html =~ "テスト土器第3図"
      assert html =~ "fig-3-1"
    end

    test "メタデータが空の場合でも正常に表示される", %{conn: conn, user: user} do
      image =
        create_user_image(user, %{
          caption: nil,
          label: nil
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
      updated = OmniArchive.Ingestion.get_extracted_image!(image.id)
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
      unchanged = OmniArchive.Ingestion.get_extracted_image!(image.id)
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
end
