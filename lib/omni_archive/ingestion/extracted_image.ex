defmodule OmniArchive.Ingestion.ExtractedImage do
  @moduledoc """
  抽出画像を管理する Ecto スキーマ。
  クロップデータ(JSONB)、キャプション、ラベル、PTIFパスを保持します。

  ## なぜこの設計か

  - **geometry を JSONB で保持**: クロップ領域 `{x, y, width, height}` を
    マップとして保存することで、将来的に矩形以外のクロップ形状（多角形や
    円形）にも拡張可能です。専用カラムに分離するよりスキーマ変更が不要です。
  - **status フィールド**: Stage-Gate ワークフローに対応し、
    `draft / pending_review / published` の3状態を文字列で管理します。
    Enum 型ではなく文字列を使うことで、マイグレーションなしに新しい
    ステータスを追加できる柔軟性を確保しています。
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias OmniArchive.DomainMetadataValidation
  alias OmniArchive.Ingestion.ExtractedImageMetadata

  schema "extracted_images" do
    # 抽出元のページ番号
    field :page_number, :integer
    # 抽出画像のファイルパス
    field :image_path, :string
    # クロップデータ (x, y, width, height) — JSONB
    field :geometry, :map
    # キャプション (手動入力)
    field :caption, :string
    # ラベル (手動入力)
    field :label, :string
    # 生成された PTIF のパス
    field :ptif_path, :string
    # 可変メタデータ（移行期間は archaeology 旧カラムと dual-write）
    field :metadata, :map, default: %{}
    # 検索用メタデータ（遺跡名、時代、遺物種別）
    field :site, :string
    field :period, :string
    field :artifact_type, :string
    # ステータス (draft / pending_review / rejected / published)
    field :status, :string, default: "draft"
    # レビュアーによる差し戻し理由
    field :review_comment, :string
    # 楽観的ロック用バージョンカウンター
    field :lock_version, :integer, default: 1

    belongs_to :pdf_source, OmniArchive.Ingestion.PdfSource
    has_one :iiif_manifest, OmniArchive.Iiif.Manifest
    # 所有者（アップロードした人）
    belongs_to :owner, OmniArchive.Accounts.User
    # 作業者（現在編集中の人）
    belongs_to :worker, OmniArchive.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "バリデーション用 changeset"
  def changeset(extracted_image, attrs) do
    attrs = ExtractedImageMetadata.normalize_attrs(extracted_image, attrs)

    extracted_image
    |> cast(attrs, [
      :pdf_source_id,
      :page_number,
      :image_path,
      :geometry,
      :caption,
      :label,
      :ptif_path,
      :metadata,
      :site,
      :period,
      :artifact_type,
      :status,
      :review_comment,
      :lock_version,
      :owner_id,
      :worker_id
    ])
    |> validate_required([:pdf_source_id, :page_number])
    |> validate_inclusion(:status, ~w(draft pending_review rejected published deleted))
    |> DomainMetadataValidation.validate_changeset()
    |> foreign_key_constraint(:pdf_source_id)
    |> optimistic_lock(:lock_version)
    |> unique_constraint([:site, :label],
      name: :extracted_images_site_label_unique,
      message: DomainMetadataValidation.duplicate_label_error()
    )
  end
end
