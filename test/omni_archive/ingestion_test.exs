defmodule OmniArchive.IngestionTest do
  use OmniArchive.DataCase, async: true

  alias OmniArchive.Ingestion
  alias OmniArchive.Ingestion.{ExtractedImage, PdfSource}
  import OmniArchive.Factory

  # === PdfSource テスト ===

  describe "list_pdf_sources/0" do
    test "全ての PdfSource を返す" do
      pdf1 = insert_pdf_source(%{filename: "report_a.pdf"})
      pdf2 = insert_pdf_source(%{filename: "report_b.pdf"})

      result = Ingestion.list_pdf_sources()
      ids = Enum.map(result, & &1.id)

      assert pdf1.id in ids
      assert pdf2.id in ids
    end

    test "PdfSource がない場合は空リストを返す" do
      assert Ingestion.list_pdf_sources() == []
    end
  end

  describe "get_pdf_source!/1" do
    test "ID で PdfSource を取得する" do
      pdf = insert_pdf_source()
      assert Ingestion.get_pdf_source!(pdf.id).id == pdf.id
    end

    test "存在しない ID で Ecto.NoResultsError を発生させる" do
      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_pdf_source!(0)
      end
    end
  end

  describe "create_pdf_source/1" do
    test "有効な属性で PdfSource を作成する" do
      attrs = %{filename: "new_report.pdf", page_count: 15, status: "uploading"}
      assert {:ok, %PdfSource{} = pdf} = Ingestion.create_pdf_source(attrs)
      assert pdf.filename == "new_report.pdf"
      assert pdf.page_count == 15
      assert pdf.status == "uploading"
    end

    test "無効な属性でエラーを返す" do
      assert {:error, %Ecto.Changeset{}} = Ingestion.create_pdf_source(%{})
    end
  end

  describe "update_pdf_source/2" do
    test "PdfSource を更新する" do
      pdf = insert_pdf_source(%{status: "uploading"})
      assert {:ok, updated} = Ingestion.update_pdf_source(pdf, %{status: "ready", page_count: 20})
      assert updated.status == "ready"
      assert updated.page_count == 20
    end
  end

  # === ExtractedImage テスト ===

  describe "list_extracted_images/1" do
    test "指定した PdfSource の画像のみを返す" do
      pdf1 = insert_pdf_source()
      pdf2 = insert_pdf_source()

      img1 = insert_extracted_image(%{pdf_source_id: pdf1.id, page_number: 1, label: "fig-1-1"})
      _img2 = insert_extracted_image(%{pdf_source_id: pdf2.id, page_number: 1, label: "fig-2-1"})

      result = Ingestion.list_extracted_images(pdf1.id)
      assert length(result) == 1
      assert hd(result).id == img1.id
    end

    test "page_number の昇順でソートされる" do
      pdf = insert_pdf_source()

      # 順不同で挿入
      img3 = insert_extracted_image(%{pdf_source_id: pdf.id, page_number: 3, label: "fig-3-1"})
      img1 = insert_extracted_image(%{pdf_source_id: pdf.id, page_number: 1, label: "fig-1-1"})
      img2 = insert_extracted_image(%{pdf_source_id: pdf.id, page_number: 2, label: "fig-2-1"})

      result = Ingestion.list_extracted_images(pdf.id)
      ids = Enum.map(result, & &1.id)

      assert ids == [img1.id, img2.id, img3.id]
    end

    test "画像がない場合は空リストを返す" do
      pdf = insert_pdf_source()
      assert Ingestion.list_extracted_images(pdf.id) == []
    end
  end

  describe "list_extracted_images/1 (RBAC)" do
    test "Admin ユーザーは全ての画像を取得できる" do
      admin = insert_user(%{role: "admin"})
      user = insert_user()

      # 異なるオーナーの画像を作成
      img1 = insert_extracted_image(%{owner_id: admin.id, label: "fig-9001-1"})
      img2 = insert_extracted_image(%{owner_id: user.id, label: "fig-9001-2"})

      result = Ingestion.list_extracted_images(admin)
      ids = Enum.map(result, & &1.id)

      assert img1.id in ids
      assert img2.id in ids
    end

    test "一般ユーザーは自分の画像のみ取得できる" do
      user_a = insert_user()
      user_b = insert_user()

      img_a = insert_extracted_image(%{owner_id: user_a.id, label: "fig-9002-1"})
      _img_b = insert_extracted_image(%{owner_id: user_b.id, label: "fig-9002-2"})

      result = Ingestion.list_extracted_images(user_a)
      ids = Enum.map(result, & &1.id)

      assert img_a.id in ids
      assert length(result) == 1
    end

    test "データ分離: 他ユーザーの画像が含まれない" do
      user_a = insert_user()
      user_b = insert_user()

      _img_a = insert_extracted_image(%{owner_id: user_a.id, label: "fig-9003-1"})
      img_b = insert_extracted_image(%{owner_id: user_b.id, label: "fig-9003-2"})

      result_a = Ingestion.list_extracted_images(user_a)
      ids_a = Enum.map(result_a, & &1.id)

      refute img_b.id in ids_a
    end
  end

  describe "get_extracted_image!/1" do
    test "ID で ExtractedImage を取得する" do
      image = insert_extracted_image(%{label: "fig-99-1"})
      assert Ingestion.get_extracted_image!(image.id).id == image.id
    end

    test "存在しない ID で Ecto.NoResultsError を発生させる" do
      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_extracted_image!(0)
      end
    end
  end

  describe "create_extracted_image/1" do
    test "有効な属性で ExtractedImage を作成する" do
      pdf = insert_pdf_source()

      attrs = %{
        pdf_source_id: pdf.id,
        page_number: 3,
        image_path: "priv/static/uploads/pages/1/page-003.png",
        caption: "テスト図版",
        label: "fig-100-1"
      }

      assert {:ok, %ExtractedImage{} = image} = Ingestion.create_extracted_image(attrs)
      assert image.page_number == 3
      assert image.caption == "テスト図版"
      assert image.status == "draft"
    end

    test "必須フィールド未指定でエラーを返す" do
      assert {:error, %Ecto.Changeset{}} = Ingestion.create_extracted_image(%{})
    end
  end

  describe "update_extracted_image/2" do
    test "ExtractedImage を更新する" do
      image = insert_extracted_image(%{label: "fig-200-1"})

      assert {:ok, updated} =
               Ingestion.update_extracted_image(image, %{
                 caption: "更新されたキャプション",
                 label: "fig-200-2"
               })

      assert updated.caption == "更新されたキャプション"
      assert updated.label == "fig-200-2"
    end
  end

  # === ステータス遷移テスト ===

  describe "submit_for_review/1" do
    test "draft → pending_review に遷移する" do
      image = insert_extracted_image(%{status: "draft", label: "fig-300-1"})
      assert {:ok, updated} = Ingestion.submit_for_review(image)
      assert updated.status == "pending_review"
    end

    test "draft 以外のステータスではエラーを返す" do
      image = insert_extracted_image(%{status: "published", label: "fig-300-2"})
      assert {:error, :invalid_status_transition} = Ingestion.submit_for_review(image)
    end

    test "pending_review からの遷移はエラーを返す" do
      image = insert_extracted_image(%{status: "pending_review", label: "fig-300-3"})
      assert {:error, :invalid_status_transition} = Ingestion.submit_for_review(image)
    end
  end

  describe "approve_and_publish/1" do
    test "pending_review → published に遷移する" do
      image = insert_extracted_image(%{status: "pending_review", label: "fig-400-1"})
      assert {:ok, updated} = Ingestion.approve_and_publish(image)
      assert updated.status == "published"
    end

    test "pending_review 以外のステータスではエラーを返す" do
      image = insert_extracted_image(%{status: "draft", label: "fig-400-2"})
      assert {:error, :invalid_status_transition} = Ingestion.approve_and_publish(image)
    end
  end

  describe "reject_to_draft/1" do
    test "pending_review → draft に遷移する" do
      image = insert_extracted_image(%{status: "pending_review", label: "fig-500-1"})
      assert {:ok, updated} = Ingestion.reject_to_draft(image)
      assert updated.status == "draft"
    end

    test "pending_review 以外のステータスではエラーを返す" do
      image = insert_extracted_image(%{status: "draft", label: "fig-500-2"})
      assert {:error, :invalid_status_transition} = Ingestion.reject_to_draft(image)
    end

    test "published からの遷移はエラーを返す" do
      image = insert_extracted_image(%{status: "published", label: "fig-500-3"})
      assert {:error, :invalid_status_transition} = Ingestion.reject_to_draft(image)
    end
  end

  describe "list_pending_review_images/0" do
    test "pending_review の画像を返す（PTIF の有無を問わない）" do
      _draft =
        insert_extracted_image(%{
          status: "draft",
          ptif_path: "/path/to/test.tif",
          label: "fig-600-1"
        })

      pending_with_ptif =
        insert_extracted_image(%{
          status: "pending_review",
          ptif_path: "/path/to/test2.tif",
          label: "fig-600-2"
        })

      _published =
        insert_extracted_image(%{
          status: "published",
          ptif_path: "/path/to/test3.tif",
          label: "fig-600-3"
        })

      pending_no_ptif =
        insert_extracted_image(%{status: "pending_review", ptif_path: nil, label: "fig-600-4"})

      result = Ingestion.list_pending_review_images()
      ids = Enum.map(result, & &1.id)

      assert pending_with_ptif.id in ids
      assert pending_no_ptif.id in ids
      assert length(result) == 2
    end
  end

  describe "list_all_images_for_lab/0" do
    test "PTIF ありの全ステータス画像を返す" do
      img1 =
        insert_extracted_image(%{status: "draft", ptif_path: "/path/a.tif", label: "fig-700-1"})

      img2 =
        insert_extracted_image(%{
          status: "published",
          ptif_path: "/path/b.tif",
          label: "fig-700-2"
        })

      _no_ptif = insert_extracted_image(%{status: "draft", ptif_path: nil, label: "fig-700-3"})

      result = Ingestion.list_all_images_for_lab()
      ids = Enum.map(result, & &1.id)

      assert img1.id in ids
      assert img2.id in ids
      assert length(result) == 2
    end
  end

  describe "list_rejected_images/0" do
    test "rejected ステータスの画像のみを返す" do
      _draft = insert_extracted_image(%{status: "draft", label: "fig-800-1"})

      rejected1 =
        insert_extracted_image(%{
          status: "rejected",
          review_comment: "メタデータ不足",
          label: "fig-800-2"
        })

      rejected2 =
        insert_extracted_image(%{
          status: "rejected",
          review_comment: "クロップが不正確",
          label: "fig-800-3"
        })

      _published = insert_extracted_image(%{status: "published", label: "fig-800-4"})

      result = Ingestion.list_rejected_images()
      ids = Enum.map(result, & &1.id)

      assert rejected1.id in ids
      assert rejected2.id in ids
      assert length(result) == 2
    end

    test "rejected がない場合は空リストを返す" do
      _draft = insert_extracted_image(%{status: "draft", label: "fig-800-5"})
      assert Ingestion.list_rejected_images() == []
    end
  end

  describe "resubmit_image/1" do
    test "rejected → pending_review に遷移し review_comment をクリアする" do
      image =
        insert_extracted_image(%{status: "rejected", review_comment: "要修正", label: "fig-900-1"})

      assert {:ok, updated} = Ingestion.resubmit_image(image)
      assert updated.status == "pending_review"
      assert is_nil(updated.review_comment)
    end

    test "rejected 以外のステータスではエラーを返す" do
      image = insert_extracted_image(%{status: "draft", label: "fig-900-2"})
      assert {:error, :invalid_status_transition} = Ingestion.resubmit_image(image)
    end

    test "pending_review からの再提出はエラーを返す" do
      image = insert_extracted_image(%{status: "pending_review", label: "fig-900-3"})
      assert {:error, :invalid_status_transition} = Ingestion.resubmit_image(image)
    end
  end

  # === 楽観的ロック テスト ===

  describe "optimistic locking" do
    test "lock_version 不一致で {:error, :stale} を返す" do
      image = insert_extracted_image(%{label: "fig-1000-1"})
      # lock_version を意図的にずらして stale を再現
      stale_image = %{image | lock_version: image.lock_version - 1}

      assert {:error, :stale} =
               Ingestion.update_extracted_image(stale_image, %{caption: "新caption"})
    end

    test "lock_version が一致していれば正常に更新される" do
      image = insert_extracted_image(%{label: "fig-1000-2"})
      assert {:ok, updated} = Ingestion.update_extracted_image(image, %{caption: "更新OK"})
      assert updated.caption == "更新OK"
      assert updated.lock_version == image.lock_version + 1
    end

    test "ステータス遷移でも楽観的ロックが適用される" do
      image = insert_extracted_image(%{status: "draft", label: "fig-1000-3"})
      stale_image = %{image | lock_version: image.lock_version - 1}
      assert {:error, :stale} = Ingestion.submit_for_review(stale_image)
    end
  end

  # === 削除テスト ===

  describe "delete_extracted_image/1" do
    test "DB レコードが削除される" do
      image = insert_extracted_image(%{label: "fig-8001-1"})
      assert {:ok, _} = Ingestion.delete_extracted_image(image)

      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_extracted_image!(image.id)
      end
    end

    test "物理ファイルが削除される" do
      # ダミーファイルを作成
      dir = Path.join(System.tmp_dir!(), "alchem_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      img_path = Path.join(dir, "page-001.png")
      ptif_path = Path.join(dir, "page-001.tif")
      File.write!(img_path, "dummy")
      File.write!(ptif_path, "dummy")

      image =
        insert_extracted_image(%{
          image_path: img_path,
          ptif_path: ptif_path,
          label: "fig-8002-1"
        })

      assert {:ok, _} = Ingestion.delete_extracted_image(image)
      refute File.exists?(img_path)
      refute File.exists?(ptif_path)

      # クリーンアップ
      File.rm_rf!(dir)
    end

    test "ファイルが存在しなくてもエラーにならない" do
      image =
        insert_extracted_image(%{
          image_path: "/tmp/nonexistent_file.png",
          ptif_path: nil,
          label: "fig-8003-1"
        })

      assert {:ok, _} = Ingestion.delete_extracted_image(image)
    end
  end

  # === 一括削除テスト ===

  describe "delete_multiple_extracted_images/1" do
    test "複数の DB レコードが削除される" do
      img1 = insert_extracted_image(%{label: "fig-9501-1"})
      img2 = insert_extracted_image(%{label: "fig-9501-2"})
      img3 = insert_extracted_image(%{label: "fig-9501-3"})

      assert {:ok, 2} = Ingestion.delete_multiple_extracted_images([img1.id, img2.id])

      # 削除されたレコードは取得不可
      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_extracted_image!(img1.id)
      end

      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_extracted_image!(img2.id)
      end

      # 削除されなかったレコードは残っている
      assert Ingestion.get_extracted_image!(img3.id).id == img3.id
    end

    test "物理ファイルも削除される" do
      dir = Path.join(System.tmp_dir!(), "alchem_bulk_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)

      img1_path = Path.join(dir, "bulk-001.png")
      ptif1_path = Path.join(dir, "bulk-001.tif")
      img2_path = Path.join(dir, "bulk-002.png")
      File.write!(img1_path, "dummy1")
      File.write!(ptif1_path, "dummy1_ptif")
      File.write!(img2_path, "dummy2")

      image1 =
        insert_extracted_image(%{
          image_path: img1_path,
          ptif_path: ptif1_path,
          label: "fig-9502-1"
        })

      image2 =
        insert_extracted_image(%{
          image_path: img2_path,
          ptif_path: nil,
          label: "fig-9502-2"
        })

      assert {:ok, 2} = Ingestion.delete_multiple_extracted_images([image1.id, image2.id])

      refute File.exists?(img1_path)
      refute File.exists?(ptif1_path)
      refute File.exists?(img2_path)

      # クリーンアップ
      File.rm_rf!(dir)
    end

    test "空リストで {:ok, 0} を返す" do
      assert {:ok, 0} = Ingestion.delete_multiple_extracted_images([])
    end

    test "存在しない ID が混在しても正常動作する" do
      img = insert_extracted_image(%{label: "fig-9504-1"})
      nonexistent_id = 999_999

      assert {:ok, 1} = Ingestion.delete_multiple_extracted_images([img.id, nonexistent_id])

      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_extracted_image!(img.id)
      end
    end
  end

  # === list_pdf_sources/1 (RBAC) テスト ===

  describe "list_pdf_sources/1 (RBAC)" do
    test "Admin は全ての PdfSource を取得できる" do
      admin = insert_user(%{role: "admin"})
      user = insert_user()

      pdf1 = insert_pdf_source(%{filename: "admin-report.pdf"})
      pdf2 = insert_pdf_source(%{filename: "user-report.pdf"})

      # 各 PDF に画像を紐付け
      insert_extracted_image(%{pdf_source_id: pdf1.id, owner_id: admin.id, label: "fig-10001-1"})
      insert_extracted_image(%{pdf_source_id: pdf2.id, owner_id: user.id, label: "fig-10001-2"})

      result = Ingestion.list_pdf_sources(admin)
      ids = Enum.map(result, & &1.id)

      assert pdf1.id in ids
      assert pdf2.id in ids
    end

    test "一般ユーザーは自分の画像がある PdfSource のみ取得できる" do
      user_a = insert_user()
      user_b = insert_user()

      pdf1 = insert_pdf_source(%{filename: "shared.pdf"})
      pdf2 = insert_pdf_source(%{filename: "other.pdf"})

      insert_extracted_image(%{pdf_source_id: pdf1.id, owner_id: user_a.id, label: "fig-10002-1"})
      insert_extracted_image(%{pdf_source_id: pdf2.id, owner_id: user_b.id, label: "fig-10002-2"})

      result = Ingestion.list_pdf_sources(user_a)
      ids = Enum.map(result, & &1.id)

      assert pdf1.id in ids
      refute pdf2.id in ids
    end

    test "image_count が正しく計算される" do
      admin = insert_user(%{role: "admin"})
      pdf = insert_pdf_source(%{filename: "count-test.pdf"})

      insert_extracted_image(%{pdf_source_id: pdf.id, owner_id: admin.id, label: "fig-10003-1"})
      insert_extracted_image(%{pdf_source_id: pdf.id, owner_id: admin.id, label: "fig-10003-2"})

      [result] = Ingestion.list_pdf_sources(admin)
      assert result.image_count == 2
    end
  end

  # === get_pdf_source!/2 (user_id ベース所有権チェック) テスト ===

  describe "get_pdf_source!/2 (user_id)" do
    test "Admin は任意の PdfSource を取得できる" do
      admin = insert_user(%{role: "admin"})
      user = insert_user()
      pdf = insert_pdf_source(%{user_id: user.id})

      assert Ingestion.get_pdf_source!(pdf.id, admin).id == pdf.id
    end

    test "一般ユーザーは自分の PdfSource を取得できる" do
      user = insert_user()
      pdf = insert_pdf_source(%{user_id: user.id})

      assert Ingestion.get_pdf_source!(pdf.id, user).id == pdf.id
    end

    test "一般ユーザーは他ユーザーの PdfSource を取得できない" do
      user_a = insert_user()
      user_b = insert_user()
      pdf = insert_pdf_source(%{user_id: user_b.id})

      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_pdf_source!(pdf.id, user_a)
      end
    end

    test "user_id が nil の PdfSource は一般ユーザーから取得できない" do
      user = insert_user()
      pdf = insert_pdf_source()

      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_pdf_source!(pdf.id, user)
      end
    end
  end

  # === list_user_pdf_sources/1 (user_id ベーススコーピング) テスト ===

  describe "list_user_pdf_sources/1" do
    test "Admin は全ての PdfSource を取得できる" do
      admin = insert_user(%{role: "admin"})
      user = insert_user()

      pdf1 = insert_pdf_source(%{filename: "admin-owned.pdf", user_id: admin.id})
      pdf2 = insert_pdf_source(%{filename: "user-owned.pdf", user_id: user.id})

      result = Ingestion.list_user_pdf_sources(admin)
      ids = Enum.map(result, & &1.id)

      assert pdf1.id in ids
      assert pdf2.id in ids
    end

    test "一般ユーザーは自分の PdfSource のみ取得できる" do
      user_a = insert_user()
      user_b = insert_user()

      pdf1 = insert_pdf_source(%{filename: "my-project.pdf", user_id: user_a.id})
      _pdf2 = insert_pdf_source(%{filename: "other-project.pdf", user_id: user_b.id})

      result = Ingestion.list_user_pdf_sources(user_a)
      ids = Enum.map(result, & &1.id)

      assert pdf1.id in ids
      assert length(result) == 1
    end

    test "ソフトデリート済みの PdfSource は除外される" do
      user = insert_user()
      _pdf_active = insert_pdf_source(%{filename: "active.pdf", user_id: user.id})
      pdf_deleted = insert_pdf_source(%{filename: "deleted.pdf", user_id: user.id})
      {:ok, _} = Ingestion.soft_delete_pdf_source(pdf_deleted)

      result = Ingestion.list_user_pdf_sources(user)
      ids = Enum.map(result, & &1.id)

      refute pdf_deleted.id in ids
    end

    test "image_count が正しく計算される" do
      user = insert_user()
      pdf = insert_pdf_source(%{filename: "count-test.pdf", user_id: user.id})

      insert_extracted_image(%{pdf_source_id: pdf.id, owner_id: user.id, label: "fig-30001-1"})
      insert_extracted_image(%{pdf_source_id: pdf.id, owner_id: user.id, label: "fig-30001-2"})

      [result] = Ingestion.list_user_pdf_sources(user)
      assert result.image_count == 2
    end

    test "Admin の結果に owner_email が含まれる" do
      admin = insert_user(%{role: "admin"})
      user = insert_user()
      _pdf = insert_pdf_source(%{filename: "email-test.pdf", user_id: user.id})

      [result] = Ingestion.list_user_pdf_sources(admin)
      assert result.owner_email == user.email
    end
  end

  # === soft_delete_pdf_source / restore / list_deleted テスト ===

  describe "soft_delete_pdf_source/1" do
    test "deleted_at が設定される" do
      pdf = insert_pdf_source(%{filename: "soft-del.pdf"})
      assert is_nil(pdf.deleted_at)

      assert {:ok, updated} = Ingestion.soft_delete_pdf_source(pdf)
      refute is_nil(updated.deleted_at)
    end

    test "ソフトデリート後、list_pdf_sources から除外される" do
      admin = insert_user(%{role: "admin"})
      pdf = insert_pdf_source(%{filename: "hidden.pdf"})
      insert_extracted_image(%{pdf_source_id: pdf.id, owner_id: admin.id, label: "fig-20001-1"})

      # ソフトデリート前: 含まれる
      result_before = Ingestion.list_pdf_sources(admin)
      assert Enum.any?(result_before, &(&1.id == pdf.id))

      # ソフトデリート
      {:ok, _} = Ingestion.soft_delete_pdf_source(pdf)

      # ソフトデリート後: 除外される
      result_after = Ingestion.list_pdf_sources(admin)
      refute Enum.any?(result_after, &(&1.id == pdf.id))
    end
  end

  # === published? テスト ===

  describe "published?/1" do
    test "公開済み画像がある場合 true を返す" do
      pdf = insert_pdf_source(%{filename: "pub-check.pdf"})
      insert_extracted_image(%{pdf_source_id: pdf.id, status: "published", label: "fig-30001-1"})

      assert Ingestion.published?(pdf) == true
    end

    test "公開済み画像がない（draft のみ）場合 false を返す" do
      pdf = insert_pdf_source(%{filename: "draft-only.pdf"})
      insert_extracted_image(%{pdf_source_id: pdf.id, status: "draft", label: "fig-30002-1"})

      assert Ingestion.published?(pdf) == false
    end

    test "画像が0件の場合 false を返す" do
      pdf = insert_pdf_source(%{filename: "no-images.pdf"})

      assert Ingestion.published?(pdf) == false
    end
  end

  # === soft_delete 公開ロックテスト ===

  describe "soft_delete_pdf_source/1 (publish lock)" do
    test "公開済み画像がある場合 {:error, :published_project} を返す" do
      pdf = insert_pdf_source(%{filename: "locked.pdf"})
      insert_extracted_image(%{pdf_source_id: pdf.id, status: "published", label: "fig-30003-1"})

      assert {:error, :published_project} = Ingestion.soft_delete_pdf_source(pdf)
      # deleted_at が設定されていないことを確認
      reloaded = Ingestion.get_pdf_source!(pdf.id)
      assert is_nil(reloaded.deleted_at)
    end

    test "公開済み画像がない場合は正常にソフトデリートされる" do
      pdf = insert_pdf_source(%{filename: "unlocked.pdf"})
      insert_extracted_image(%{pdf_source_id: pdf.id, status: "draft", label: "fig-30004-1"})

      assert {:ok, updated} = Ingestion.soft_delete_pdf_source(pdf)
      refute is_nil(updated.deleted_at)
    end
  end

  describe "restore_pdf_source/1" do
    test "deleted_at が nil に戻る" do
      pdf = insert_pdf_source(%{filename: "restore-me.pdf"})
      {:ok, deleted} = Ingestion.soft_delete_pdf_source(pdf)
      refute is_nil(deleted.deleted_at)

      assert {:ok, restored} = Ingestion.restore_pdf_source(deleted.id)
      assert is_nil(restored.deleted_at)
    end
  end

  describe "list_deleted_pdf_sources/0" do
    test "ソフトデリート済みのみ返す" do
      pdf_active = insert_pdf_source(%{filename: "active.pdf"})
      pdf_deleted = insert_pdf_source(%{filename: "deleted.pdf"})
      {:ok, _} = Ingestion.soft_delete_pdf_source(pdf_deleted)

      result = Ingestion.list_deleted_pdf_sources()
      ids = Enum.map(result, & &1.id)

      assert pdf_deleted.id in ids
      refute pdf_active.id in ids
    end

    test "ゴミ箱が空の場合は空リストを返す" do
      _pdf = insert_pdf_source(%{filename: "still-active.pdf"})
      assert Ingestion.list_deleted_pdf_sources() == []
    end
  end

  # === hard_delete_pdf_source/1 テスト ===

  describe "hard_delete_pdf_source/1" do
    test "PdfSource と関連 ExtractedImage の DB レコードが削除される" do
      pdf = insert_pdf_source(%{filename: "to-delete.pdf"})
      img = insert_extracted_image(%{pdf_source_id: pdf.id, label: "fig-10006-1"})

      assert {:ok, _} = Ingestion.hard_delete_pdf_source(pdf)

      # PdfSource が削除されたことを確認
      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_pdf_source!(pdf.id)
      end

      # ExtractedImage も削除されたことを確認
      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_extracted_image!(img.id)
      end
    end

    test "関連する物理ファイルが削除される" do
      dir = Path.join(System.tmp_dir!(), "alchem_del_proj_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)

      img_path = Path.join(dir, "del-img.png")
      ptif_path = Path.join(dir, "del-img.tif")
      File.write!(img_path, "dummy")
      File.write!(ptif_path, "dummy")

      pdf = insert_pdf_source(%{filename: "del-project.pdf"})

      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        image_path: img_path,
        ptif_path: ptif_path,
        label: "fig-10007-1"
      })

      assert {:ok, _} = Ingestion.hard_delete_pdf_source(pdf)

      refute File.exists?(img_path)
      refute File.exists?(ptif_path)

      # クリーンアップ
      File.rm_rf!(dir)
    end

    test "画像がない PdfSource でもエラーなく削除される" do
      pdf = insert_pdf_source(%{filename: "empty-project.pdf"})
      assert {:ok, _} = Ingestion.hard_delete_pdf_source(pdf)

      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_pdf_source!(pdf.id)
      end
    end
  end

  # === プロジェクト ワークフロー遷移テスト ===

  describe "submit_project/1" do
    test "wip → pending_review に遷移する" do
      pdf = insert_pdf_source(%{workflow_status: "wip"})
      assert {:ok, updated} = Ingestion.submit_project(pdf)
      assert updated.workflow_status == "pending_review"
    end

    test "returned → pending_review に遷移し return_message がクリアされる" do
      pdf = insert_pdf_source(%{workflow_status: "returned", return_message: "要修正"})
      assert {:ok, updated} = Ingestion.submit_project(pdf)
      assert updated.workflow_status == "pending_review"
      assert is_nil(updated.return_message)
    end

    test "pending_review からはエラーを返す" do
      pdf = insert_pdf_source(%{workflow_status: "pending_review"})
      assert {:error, :invalid_status_transition} = Ingestion.submit_project(pdf)
    end

    test "approved からはエラーを返す" do
      pdf = insert_pdf_source(%{workflow_status: "approved"})
      assert {:error, :invalid_status_transition} = Ingestion.submit_project(pdf)
    end
  end

  describe "return_project/2" do
    test "pending_review → returned に遷移しメッセージが保存される" do
      pdf = insert_pdf_source(%{workflow_status: "pending_review"})
      assert {:ok, updated} = Ingestion.return_project(pdf, "クロップ範囲を修正してください")
      assert updated.workflow_status == "returned"
      assert updated.return_message == "クロップ範囲を修正してください"
    end

    test "wip からはエラーを返す" do
      pdf = insert_pdf_source(%{workflow_status: "wip"})
      assert {:error, :invalid_status_transition} = Ingestion.return_project(pdf, "msg")
    end

    test "approved からはエラーを返す" do
      pdf = insert_pdf_source(%{workflow_status: "approved"})
      assert {:error, :invalid_status_transition} = Ingestion.return_project(pdf, "msg")
    end
  end

  describe "approve_project/1" do
    test "pending_review → approved に遷移する" do
      pdf = insert_pdf_source(%{workflow_status: "pending_review"})
      assert {:ok, updated} = Ingestion.approve_project(pdf)
      assert updated.workflow_status == "approved"
    end

    test "wip からはエラーを返す" do
      pdf = insert_pdf_source(%{workflow_status: "wip"})
      assert {:error, :invalid_status_transition} = Ingestion.approve_project(pdf)
    end

    test "returned からはエラーを返す" do
      pdf = insert_pdf_source(%{workflow_status: "returned"})
      assert {:error, :invalid_status_transition} = Ingestion.approve_project(pdf)
    end
  end
end
