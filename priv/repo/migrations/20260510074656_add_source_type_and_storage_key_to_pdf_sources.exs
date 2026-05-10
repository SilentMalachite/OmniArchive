defmodule OmniArchive.Repo.Migrations.AddSourceTypeAndStorageKeyToPdfSources do
  use Ecto.Migration

  @moduledoc """
  AlchemIIIF v0.3.0 同等の ZIP ソース対応に向けて、PdfSource に
  以下の 2 列を追加する additive migration。

  - `source_type` (TEXT, default "pdf", NOT NULL): 取り込みソースの種別
    （現状 "pdf" / "zip" の 2 値、将来的に拡張可能）。
  - `storage_key` (TEXT, NOT NULL, unique): ページ画像ディレクトリ
    （priv/static/uploads/pages/<storage_key>/...）の物理パスキー。
    既存行は backfill で `src-<id>` を割り当て、物理ディレクトリの
    リネームは行わずに後方互換を維持する。
    新規行は changeset 側で UUID ベースの値を自動付与する。

  CLAUDE.md の "Additive migrations only" 不変条件に準拠：
  - 列追加 → backfill → NOT NULL 化 → unique index 作成、の 4 段階。
  - down マイグレーションは storage_key を NULL に戻し列を落とす。
  """

  def up do
    alter table(:pdf_sources) do
      add :source_type, :string, default: "pdf", null: false
      add :storage_key, :string
    end

    flush()

    # 既存行の backfill: storage_key = "src-<id>"
    execute("UPDATE pdf_sources SET storage_key = 'src-' || id WHERE storage_key IS NULL")

    alter table(:pdf_sources) do
      modify :storage_key, :string, null: false
    end

    create unique_index(:pdf_sources, [:storage_key])
  end

  def down do
    drop_if_exists unique_index(:pdf_sources, [:storage_key])

    alter table(:pdf_sources) do
      remove :storage_key
      remove :source_type
    end
  end
end
