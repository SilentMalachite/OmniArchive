defmodule OmniArchive.Ingestion.PdfSource do
  @moduledoc """
  取り込みソース（PDF / ZIP）を管理する Ecto スキーマ。
  歴史的経緯から名前は PdfSource のままだが、`source_type` で
  PDF と ZIP（PNG コレクション）の双方を表現する。

  ## なぜこの設計か

  - **ステータス管理**: `uploading → converting → ready / error` の遷移を
    追跡することで、処理途中でサーバーが再起動した場合でも、
    どのソースがどの段階にあるか復元できます。
  - **ワークフロー管理**: `wip → pending_review → returned / approved` の
    遷移で、作業完了提出・管理者差し戻し・承認のフローを管理します。
  - **ExtractedImage との 1:N 関連**: 1つのソースから複数のページ画像が
    抽出されるため、親子関係で管理します。ソース単位での一括削除にも対応します。
  - **storage_key**: 物理ファイルディレクトリの一意キー。新規行は UUID
    ベースで自動付与し、既存行は migration で `src-<id>` を backfill。
    これにより整数 ID をパスに露出させずに済み、ZIP 取り込みなど将来の
    再帰的なソース体系にも備えます。
  """
  use Ecto.Schema
  import Ecto.Changeset

  @workflow_statuses ["wip", "pending_review", "returned", "approved"]
  @source_types ["pdf", "zip"]
  @pages_root Path.join(["priv", "static", "uploads", "pages"])

  schema "pdf_sources" do
    # ソースのファイル名
    field :filename, :string
    # ページ数
    field :page_count, :integer
    # 処理ステータス (uploading, converting, ready, error)
    field :status, :string, default: "uploading"

    # ソース種別 ("pdf" | "zip")
    field :source_type, :string, default: "pdf"
    # 物理ファイルディレクトリの一意キー
    field :storage_key, :string

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
      :source_type,
      :storage_key,
      :deleted_at,
      :workflow_status,
      :return_message,
      :user_id
    ])
    |> validate_required([:filename])
    |> validate_inclusion(:status, ["uploading", "converting", "ready", "error"])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:workflow_status, @workflow_statuses)
    |> ensure_storage_key()
    |> unique_constraint(:storage_key)
  end

  @doc "ワークフロー遷移専用 changeset"
  def workflow_changeset(pdf_source, attrs) do
    pdf_source
    |> cast(attrs, [:workflow_status, :return_message])
    |> validate_required([:workflow_status])
    |> validate_inclusion(:workflow_status, @workflow_statuses)
  end

  @doc "ソースが PDF か判定"
  def pdf?(%__MODULE__{source_type: source_type}), do: source_type == "pdf"
  def pdf?(_), do: false

  @doc "ソースが ZIP か判定"
  def zip?(%__MODULE__{source_type: source_type}), do: source_type == "zip"
  def zip?(_), do: false

  @doc """
  ページ画像ディレクトリの絶対パス（priv/static/uploads/pages/<storage_key>）を返す。
  storage_key が未設定の場合は id ベースのフォールバック（後方互換）を返す。
  """
  def pages_dir(%__MODULE__{storage_key: key, id: id}) when is_binary(key) and key != "" do
    storage_key_dir = page_dir_for(key)
    legacy_id_dir = if id, do: page_dir_for(id)

    cond do
      File.dir?(storage_key_dir) -> storage_key_dir
      legacy_id_dir && File.dir?(legacy_id_dir) -> legacy_id_dir
      true -> storage_key_dir
    end
  end

  def pages_dir(%__MODULE__{id: id}) when not is_nil(id) do
    page_dir_for(id)
  end

  defp page_dir_for(value), do: Path.join(@pages_root, to_string(value))

  # 新規 changeset で storage_key が未指定なら UUID ベースの値を自動付与する。
  # 既存レコードの更新では既存値を尊重する。
  defp ensure_storage_key(changeset) do
    case get_field(changeset, :storage_key) do
      nil -> put_change(changeset, :storage_key, generate_storage_key())
      "" -> put_change(changeset, :storage_key, generate_storage_key())
      _ -> changeset
    end
  end

  defp generate_storage_key do
    "src-" <> (Ecto.UUID.generate() |> String.replace("-", "") |> String.slice(0, 16))
  end
end
