defmodule OmniArchive.Ingestion.PdfSource do
  @moduledoc """
  PDF ソースを管理する Ecto スキーマ。
  PDFファイルの追跡・ステータス管理を行います。

  ## なぜこの設計か

  - **ステータス管理**: `uploading → converting → ready / error` の遷移を
    追跡することで、処理途中でサーバーが再起動した場合でも、
    どのPDFがどの段階にあるか復元できます。
  - **ワークフロー管理**: `wip → pending_review → returned / approved` の
    遷移で、作業完了提出・管理者差し戻し・承認のフローを管理します。
  - **ExtractedImage との 1:N 関連**: 1つのPDFから複数のページ画像が
    抽出されるため、親子関係で管理します。PDF単位での一括削除にも対応します。
  """
  use Ecto.Schema
  import Ecto.Changeset

  @workflow_statuses ["wip", "pending_review", "returned", "approved"]

  schema "pdf_sources" do
    # PDFファイル名
    field :filename, :string
    # ページ数
    field :page_count, :integer
    # 処理ステータス (uploading, converting, ready, error)
    field :status, :string, default: "uploading"

    # ワークフローステータス (wip, pending_review, returned, approved)
    field :workflow_status, :string, default: "wip"
    # 差し戻し時の管理者メッセージ
    field :return_message, :string

    # ソフトデリート用タイムスタンプ（nil = アクティブ、値あり = ゴミ箱内）
    field :deleted_at, :utc_datetime

    # プロジェクトオーナー（アクセス制御の基盤）
    belongs_to :user, OmniArchive.Accounts.User

    has_many :extracted_images, OmniArchive.Ingestion.ExtractedImage

    # バーチャルフィールド（クエリの select_merge で注入）
    field :image_count, :integer, virtual: true, default: 0
    # オーナーのメールアドレス（Admin 用、クエリの select_merge で注入）
    field :owner_email, :string, virtual: true, default: nil

    timestamps(type: :utc_datetime)
  end

  @doc "バリデーション用 changeset"
  def changeset(pdf_source, attrs) do
    pdf_source
    |> cast(attrs, [
      :filename,
      :page_count,
      :status,
      :deleted_at,
      :workflow_status,
      :return_message,
      :user_id
    ])
    |> validate_required([:filename])
    |> validate_inclusion(:status, ["uploading", "converting", "ready", "error"])
    |> validate_inclusion(:workflow_status, @workflow_statuses)
  end

  @doc "ワークフロー遷移専用 changeset"
  def workflow_changeset(pdf_source, attrs) do
    pdf_source
    |> cast(attrs, [:workflow_status, :return_message])
    |> validate_required([:workflow_status])
    |> validate_inclusion(:workflow_status, @workflow_statuses)
  end
end
