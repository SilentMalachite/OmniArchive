defmodule AlchemIiif.Ingestion do
  @moduledoc """
  取り込みパイプラインのコンテキストモジュール。
  PDFアップロード、ページ画像変換、クロップ、PTIF生成を管理します。

  ## なぜこの設計か

  - **Phoenix Contexts パターン**: LiveView やコントローラーから直接 `Repo` を
    呼ばず、このコンテキストを経由することで、ビジネスロジックを一箇所に集約します。
    将来的に内部実装が変わっても、公開 API を維持すれば呼び出し側に影響しません。
  - **Stage-Gate ステータス遷移**: `draft → pending_review → published` の
    3段階ステータスは、内部ワークスペース（Lab）と公開ギャラリー（Museum）を
    分離するための設計です。明示的なステータス遷移関数により、不正な遷移を
    コンパイル時ではなく実行時にパターンマッチで防ぎます。
  """
  import Ecto.Query
  alias AlchemIiif.Accounts.User
  alias AlchemIiif.Ingestion.{ExtractedImage, PdfSource}
  alias AlchemIiif.Repo

  # === PdfSource ===

  @doc "全てのPDFソースを取得"
  def list_pdf_sources do
    Repo.all(PdfSource)
  end

  @doc """
  ユーザーの PdfSource 一覧を取得（RBAC 対応）。
  Admin は全件、一般ユーザーは自分の ExtractedImage がある PdfSource のみ。
  画像数をバーチャルフィールドとして付与します。
  """
  def list_pdf_sources(%User{role: "admin"}) do
    from(p in PdfSource,
      left_join: e in ExtractedImage,
      on: e.pdf_source_id == p.id,
      left_join: u in AlchemIiif.Accounts.User,
      on: u.id == e.owner_id,
      where: is_nil(p.deleted_at),
      group_by: p.id,
      select: %{p | extracted_images: []},
      select_merge: %{image_count: count(e.id), owner_email: min(u.email)},
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  def list_pdf_sources(%User{id: user_id}) do
    from(p in PdfSource,
      join: e in ExtractedImage,
      on: e.pdf_source_id == p.id and e.owner_id == ^user_id,
      where: is_nil(p.deleted_at),
      group_by: p.id,
      select: %{p | extracted_images: []},
      select_merge: %{image_count: count(e.id)},
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  ユーザーの PdfSource 一覧を取得（user_id ベース厳密スコーピング）。
  Admin は全件、一般ユーザーは自分が作成した PdfSource のみ。
  画像数をバーチャルフィールドとして付与します。
  """
  def list_user_pdf_sources(%User{role: "admin"}) do
    from(p in PdfSource,
      left_join: e in ExtractedImage,
      on: e.pdf_source_id == p.id,
      left_join: u in AlchemIiif.Accounts.User,
      on: u.id == p.user_id,
      where: is_nil(p.deleted_at),
      group_by: p.id,
      select: %{p | extracted_images: []},
      select_merge: %{image_count: count(e.id), owner_email: min(u.email)},
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  def list_user_pdf_sources(%User{id: user_id}) do
    from(p in PdfSource,
      left_join: e in ExtractedImage,
      on: e.pdf_source_id == p.id,
      where: p.user_id == ^user_id and is_nil(p.deleted_at),
      group_by: p.id,
      select: %{p | extracted_images: []},
      select_merge: %{image_count: count(e.id)},
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  @doc "IDでPDFソースを取得"
  def get_pdf_source!(id), do: Repo.get!(PdfSource, id)

  @doc """
  所有権チェック付きで PdfSource を取得。
  Admin は任意の PdfSource を取得可能。
  一般ユーザーは自分が作成した PdfSource のみ取得可能（user_id ベース）。
  """
  def get_pdf_source!(id, %User{role: "admin"}) do
    Repo.get!(PdfSource, id)
  end

  def get_pdf_source!(id, %User{id: user_id}) do
    Repo.get_by!(PdfSource, id: id, user_id: user_id)
  end

  @doc "PDFソースを作成"
  def create_pdf_source(attrs \\ %{}) do
    %PdfSource{}
    |> PdfSource.changeset(attrs)
    |> Repo.insert()
  end

  @doc "PDFソースを更新"
  def update_pdf_source(%PdfSource{} = pdf_source, attrs) do
    pdf_source
    |> PdfSource.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  PdfSource を再処理（Re-process）します。
  物理 PDF ファイルが存在する場合、既存パイプラインで画像を再抽出します。

  ## 戻り値
    - {:ok, pipeline_id} — 非同期パイプラインを開始
    - {:error, :file_not_found} — PDF ファイルが存在しない
  """
  def reprocess_pdf_source(%PdfSource{} = pdf_source, opts \\ %{}) do
    pdf_path = Path.join(["priv", "static", "uploads", "pdfs", pdf_source.filename])

    if File.exists?(pdf_path) do
      # ステータスを converting に戻す
      {:ok, _} = update_pdf_source(pdf_source, %{status: "converting"})

      pipeline_id = AlchemIiif.Pipeline.generate_pipeline_id()

      Task.start(fn ->
        AlchemIiif.Pipeline.run_pdf_extraction(pdf_source, pdf_path, pipeline_id, opts)
      end)

      {:ok, pipeline_id}
    else
      {:error, :file_not_found}
    end
  end

  @doc "PdfSource に公開済み画像があるか判定"
  def published?(%PdfSource{} = pdf_source) do
    Repo.exists?(
      from(e in ExtractedImage,
        where: e.pdf_source_id == ^pdf_source.id,
        where: e.status == "published"
      )
    )
  end

  @doc """
  PdfSource をソフトデリート（ゴミ箱に移動）。
  公開済み画像がある場合はエラーを返します。
  deleted_at を現在時刻に設定します。物理ファイルは削除しません。
  """
  def soft_delete_pdf_source(%PdfSource{} = pdf_source) do
    if published?(pdf_source) do
      {:error, :published_project}
    else
      pdf_source
      |> PdfSource.changeset(%{deleted_at: DateTime.utc_now()})
      |> Repo.update()
    end
  end

  @doc """
  ソフトデリート済みの PdfSource を復元。
  deleted_at を nil に戻します。
  """
  def restore_pdf_source(id) do
    pdf_source = Repo.get!(PdfSource, id)

    pdf_source
    |> PdfSource.changeset(%{deleted_at: nil})
    |> Repo.update()
  end

  @doc """
  ゴミ箱内の PdfSource 一覧を取得（Admin 用）。
  deleted_at が設定されている（ソフトデリート済み）レコードのみ返します。
  """
  def list_deleted_pdf_sources do
    from(p in PdfSource,
      where: not is_nil(p.deleted_at),
      left_join: e in ExtractedImage,
      on: e.pdf_source_id == p.id,
      group_by: p.id,
      select: %{p | extracted_images: []},
      select_merge: %{image_count: count(e.id)},
      order_by: [desc: p.deleted_at]
    )
    |> Repo.all()
  end

  @doc """
  PdfSource を物理ファイルごと完全削除（ハードデリート）。
  Ecto.Multi トランザクション内で以下を実行:
  1. 関連 ExtractedImage の物理ファイル（image_path, ptif_path）を削除
  2. ページ画像ディレクトリを削除
  3. PDF 物理ファイルを削除
  4. 関連 ExtractedImage DB レコードを一括削除
  5. PdfSource DB レコードを削除
  """
  def hard_delete_pdf_source(%PdfSource{} = pdf_source) do
    # 関連画像を事前取得
    images = Repo.all(from(e in ExtractedImage, where: e.pdf_source_id == ^pdf_source.id))

    Repo.transaction(fn ->
      # 1. 関連画像の物理ファイルを削除
      Enum.each(images, fn image ->
        delete_file(image.image_path)
        delete_file(image.ptif_path)
      end)

      # 2. ページ画像ディレクトリを削除
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.rm_rf(pages_dir)

      # 3. PDF 物理ファイルを削除
      pdf_path = Path.join(["priv", "static", "uploads", "pdfs", pdf_source.filename])
      delete_file(pdf_path)

      # 4. 関連 ExtractedImage DB レコードを一括削除
      Repo.delete_all(from(e in ExtractedImage, where: e.pdf_source_id == ^pdf_source.id))

      # 5. PdfSource DB レコードを削除
      Repo.delete!(pdf_source)
    end)
  end

  # === プロジェクト ワークフロー遷移 ===

  @doc """
  作業完了として提出 (wip/returned → pending_review)。
  差し戻しメッセージをクリアして再提出可能。
  """
  def submit_project(%PdfSource{workflow_status: status} = pdf_source)
      when status in ["wip", "returned"] do
    pdf_source
    |> PdfSource.workflow_changeset(%{workflow_status: "pending_review", return_message: nil})
    |> Repo.update()
  end

  def submit_project(_pdf_source), do: {:error, :invalid_status_transition}

  @doc """
  差し戻し (pending_review → returned)。
  管理者が差し戻しメッセージを付与します。
  """
  def return_project(%PdfSource{workflow_status: "pending_review"} = pdf_source, message) do
    pdf_source
    |> PdfSource.workflow_changeset(%{workflow_status: "returned", return_message: message})
    |> Repo.update()
  end

  def return_project(_pdf_source, _message), do: {:error, :invalid_status_transition}

  @doc "承認 (pending_review → approved)"
  def approve_project(%PdfSource{workflow_status: "pending_review"} = pdf_source) do
    pdf_source
    |> PdfSource.workflow_changeset(%{workflow_status: "approved"})
    |> Repo.update()
  end

  def approve_project(_pdf_source), do: {:error, :invalid_status_transition}

  # === ExtractedImage ===

  @doc "抽出画像一覧を取得（RBAC対応）。Admin は全件、一般ユーザーは自分のもののみ。"
  def list_extracted_images(%User{role: "admin"}) do
    from(e in ExtractedImage,
      order_by: [asc: e.page_number],
      preload: [:owner]
    )
    |> Repo.all()
  end

  def list_extracted_images(%User{id: user_id}) do
    from(e in ExtractedImage,
      where: e.owner_id == ^user_id,
      order_by: [asc: e.page_number]
    )
    |> Repo.all()
  end

  # PDFソースに紐づく抽出画像一覧を取得（レガシー互換: 整数ID）
  def list_extracted_images(pdf_source_id) do
    from(e in ExtractedImage,
      where: e.pdf_source_id == ^pdf_source_id,
      order_by: [asc: e.page_number]
    )
    |> Repo.all()
  end

  @doc "IDで抽出画像を取得"
  def get_extracted_image!(id), do: Repo.get!(ExtractedImage, id)

  @doc "IDで抽出画像を取得（iiif_manifest プリロード付き、nil 安全）"
  def get_extracted_image_with_manifest(id) do
    case Repo.get(ExtractedImage, id) do
      nil -> nil
      image -> Repo.preload(image, :iiif_manifest)
    end
  end

  @doc "pdf_source_id と page_number で既存の抽出画像を検索（Write-on-Action 用）"
  def find_extracted_image_by_page(pdf_source_id, page_number) do
    from(e in ExtractedImage,
      where: e.pdf_source_id == ^pdf_source_id,
      where: e.page_number == ^page_number,
      where: e.status != "deleted",
      order_by: [desc: e.updated_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc "抽出画像を作成"
  def create_extracted_image(attrs \\ %{}) do
    %ExtractedImage{}
    |> ExtractedImage.changeset(attrs)
    |> Repo.insert()
  end

  @doc "抽出画像を更新（クロップデータ等）"
  def update_extracted_image(%ExtractedImage{} = image, attrs) do
    image
    |> ExtractedImage.changeset(attrs)
    |> Repo.update()
  rescue
    Ecto.StaleEntryError ->
      {:error, :stale}
  end

  @doc "同一遺跡内で同じラベルを持つレコードを検索（自分自身を除く）"
  def find_duplicate_label(site, label, exclude_id \\ nil)

  def find_duplicate_label(site, label, _exclude_id)
      when is_nil(site) or site == "" or is_nil(label) or label == "",
      do: nil

  def find_duplicate_label(site, label, exclude_id) do
    query =
      from(e in ExtractedImage,
        where: e.site == ^site,
        where: e.label == ^label,
        where: e.status != "deleted",
        limit: 1
      )

    query =
      if exclude_id,
        do: from(e in query, where: e.id != ^exclude_id),
        else: query

    Repo.one(query)
  end

  # === ステータス遷移 ===

  @doc "レビュー提出 (draft → pending_review)"
  def submit_for_review(%ExtractedImage{status: "draft"} = image) do
    update_extracted_image(image, %{status: "pending_review"})
  end

  def submit_for_review(_image), do: {:error, :invalid_status_transition}

  @doc "承認して公開 (pending_review → published)。PubSub で IIIF コレクション更新を通知。"
  def approve_and_publish(%ExtractedImage{status: "pending_review"} = image) do
    case update_extracted_image(image, %{status: "published"}) do
      {:ok, updated} ->
        # IIIF コレクション更新をバックグラウンドワーカーに通知
        Phoenix.PubSub.broadcast(
          AlchemIiif.PubSub,
          "iiif:collection",
          {:image_published, updated.id}
        )

        {:ok, updated}

      error ->
        error
    end
  end

  def approve_and_publish(_image), do: {:error, :invalid_status_transition}

  @doc "差し戻し (pending_review → draft)"
  def reject_to_draft(%ExtractedImage{status: "pending_review"} = image) do
    update_extracted_image(image, %{status: "draft"})
  end

  def reject_to_draft(_image), do: {:error, :invalid_status_transition}

  @doc "差し戻し（理由メモ付き） (pending_review → rejected)"
  def reject_to_draft_with_note(%ExtractedImage{status: "pending_review"} = image, note) do
    update_extracted_image(image, %{status: "rejected", review_comment: note})
  end

  def reject_to_draft_with_note(_image, _note), do: {:error, :invalid_status_transition}

  @doc "再提出 (rejected → pending_review)。review_comment をクリアしてレビュー待ちに戻す。"
  def resubmit_image(%ExtractedImage{status: "rejected"} = image) do
    update_extracted_image(image, %{status: "pending_review", review_comment: nil})
  end

  def resubmit_image(_image), do: {:error, :invalid_status_transition}

  @doc "ソフトデリート (pending_review → deleted)。誤登録エントリの論理削除。"
  def soft_delete_image(%ExtractedImage{status: "pending_review"} = image) do
    update_extracted_image(image, %{status: "deleted"})
  end

  def soft_delete_image(_image), do: {:error, :invalid_status_transition}

  @doc "PdfSource に紐づく公開済み画像を page_number 昇順で取得（IIIF Manifest 用）"
  def list_published_images_by_source(pdf_source_id) do
    from(e in ExtractedImage,
      where: e.pdf_source_id == ^pdf_source_id,
      where: e.status == "published",
      order_by: [asc: e.page_number]
    )
    |> Repo.all()
  end

  @doc "レビュー待ちの画像一覧（Admin Review Dashboard 用）"
  def list_pending_review_images do
    from(e in ExtractedImage,
      where: e.status == "pending_review",
      where: not is_nil(e.image_path),
      where: not is_nil(e.geometry),
      order_by: [desc: e.inserted_at],
      preload: [:iiif_manifest, :pdf_source]
    )
    |> Repo.all()
  end

  @doc "差し戻し済みの画像一覧（Lab 要修正タブ用）"
  def list_rejected_images do
    from(e in ExtractedImage,
      where: e.status == "rejected",
      order_by: [desc: e.updated_at],
      preload: [:pdf_source]
    )
    |> Repo.all()
  end

  @doc "差し戻し済みの画像一覧（ユーザーロール対応版）。Admin は全件、一般ユーザーは自分のもののみ。"
  def list_rejected_images(%User{role: "admin"}) do
    list_rejected_images()
  end

  def list_rejected_images(%User{id: user_id}) do
    from(e in ExtractedImage,
      where: e.status == "rejected",
      where: e.owner_id == ^user_id,
      order_by: [desc: e.updated_at],
      preload: [:pdf_source]
    )
    |> Repo.all()
  end

  # === ユーザーベースアクセス制御 ===

  @doc "ユーザーのロールに応じた画像一覧。Admin は全件、一般ユーザーは自分のもののみ。"
  def list_user_images(%User{role: "admin"}) do
    from(e in ExtractedImage, order_by: [asc: e.page_number])
    |> Repo.all()
  end

  def list_user_images(%User{id: user_id}) do
    from(e in ExtractedImage,
      where: e.owner_id == ^user_id,
      order_by: [asc: e.page_number]
    )
    |> Repo.all()
  end

  @doc "Lab用: 全ステータスの画像一覧（PTIFあり）。opts で owner_id / worker_id フィルタ可能。"
  def list_all_images_for_lab(opts \\ %{}) do
    query =
      from(e in ExtractedImage,
        where: not is_nil(e.ptif_path),
        order_by: [desc: e.inserted_at],
        preload: [:iiif_manifest]
      )

    query =
      if opts[:owner_id], do: from(e in query, where: e.owner_id == ^opts[:owner_id]), else: query

    query =
      if opts[:worker_id],
        do: from(e in query, where: e.worker_id == ^opts[:worker_id]),
        else: query

    Repo.all(query)
  end

  # === 削除 ===

  @doc "抽出画像を物理ファイルごと削除（Admin Dashboard 用）"
  def delete_extracted_image(%ExtractedImage{} = image) do
    # 物理ファイルを先に削除（存在しなくても無視）
    delete_file(image.image_path)
    delete_file(image.ptif_path)
    Repo.delete(image)
  end

  @doc """
  複数の抽出画像を一括削除（Admin Dashboard 一括削除用）。
  Ecto.Multi トランザクション内で物理ファイル削除 → DB レコード削除を実行します。
  ファイルが既に存在しない場合でもエラーにはなりません。
  """
  def delete_multiple_extracted_images([]), do: {:ok, 0}

  def delete_multiple_extracted_images(ids) when is_list(ids) do
    images = Repo.all(from(e in ExtractedImage, where: e.id in ^ids))

    Repo.transaction(fn ->
      # 物理ファイルを削除（存在しなくても無視）
      Enum.each(images, fn image ->
        delete_file(image.image_path)
        delete_file(image.ptif_path)
      end)

      # DB レコードを一括削除
      {count, _} = Repo.delete_all(from(e in ExtractedImage, where: e.id in ^ids))
      count
    end)
  end

  defp delete_file(nil), do: :ok
  defp delete_file(""), do: :ok
  defp delete_file(path), do: File.rm(path)

  # === バリデーション（Admin Review Dashboard 用） ===

  @doc "画像データの技術的妥当性を検証（Validation Badge 用）"
  def validate_image_data(%ExtractedImage{} = image) do
    checks = [
      {:image_file, not is_nil(image.image_path) and image.image_path != ""},
      {:ptif_file, not is_nil(image.ptif_path) and image.ptif_path != ""},
      {:geometry, is_map(image.geometry) and map_size(image.geometry) > 0},
      {:metadata, not is_nil(image.label) and image.label != ""}
    ]

    failed = Enum.filter(checks, fn {_name, result} -> not result end)

    case failed do
      [] -> {:ok, :valid}
      _ -> {:error, Enum.map(failed, fn {name, _} -> name end)}
    end
  end
end
