defmodule OmniArchive.Search do
  @moduledoc """
  検索エンジンコンテキストモジュール。
  PostgreSQL Full-Text Search (FTS) と JSONB フィルタリングによる
  画像メタデータ検索を提供します。

  ## なぜこの設計か

  - **`simple` 辞書を採用**: PostgreSQL の `english` 辞書はステミング処理が
    日本語に対応していません。`simple` 辞書はトークンをそのまま保持するため、
    日本語テキストでも安全に FTS を実行できます。
  - **LIKE フォールバック**: FTS だけでは部分一致検索ができないため、
    `ilike` による部分一致を併用しています。ユーザーが遺跡名の一部だけを
    入力した場合でもヒットするようにするためです。
  - **名前空間分離**: `OmniArchive.Ingestion` モジュールのスキーマを参照しますが、
    変更は一切行いません。Phoenix Contexts の設計思想に従い、読み取り専用の
    クエリのみ実行することで、責任の境界を明確にしています。
  """
  import Ecto.Query
  alias OmniArchive.Ingestion.ExtractedImage
  alias OmniArchive.Repo

  @doc """
  画像をテキスト検索 + フィルターで検索します。

  ## 引数
    - query_text: 検索テキスト（キャプション・ラベルで FTS）
    - filters: フィルター条件のマップ
      - "site" => 遺跡名
      - "period" => 時代
      - "artifact_type" => 遺物種別

  ## 戻り値
    - 検索結果の ExtractedImage リスト（iiif_manifest をプリロード）
  """
  def search_images(query_text \\ "", filters \\ %{}) do
    ExtractedImage
    |> where([e], not is_nil(e.ptif_path))
    |> apply_text_search(query_text)
    |> apply_filters(filters)
    |> order_by([e], desc: e.inserted_at)
    |> preload(:iiif_manifest)
    |> Repo.all()
  end

  @doc """
  公開済み画像のみを検索（Gallery用）。
  status == 'published' のみ返します。
  """
  def search_published_images(query_text \\ "", filters \\ %{}) do
    ExtractedImage
    |> where([e], e.status == "published" and e.status != "deleted")
    |> where([e], not is_nil(e.ptif_path) and e.ptif_path != "")
    |> apply_text_search(query_text)
    |> apply_filters(filters)
    |> order_by([e], desc: e.inserted_at)
    |> preload(:iiif_manifest)
    |> Repo.all()
  end

  @doc """
  利用可能なフィルターオプションを取得します。
  各フィルターの DISTINCT 値をリストで返します。
  """
  def list_filter_options do
    %{
      sites: list_distinct_values(:site),
      periods: list_distinct_values(:period),
      artifact_types: list_distinct_values(:artifact_type)
    }
  end

  @doc """
  検索結果の総件数を取得します。
  """
  def count_results(query_text \\ "", filters \\ %{}) do
    ExtractedImage
    |> where([e], not is_nil(e.ptif_path))
    |> apply_text_search(query_text)
    |> apply_filters(filters)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  公開済み検索結果の総件数を取得します（Gallery用）。
  """
  def count_published_results(query_text \\ "", filters \\ %{}) do
    ExtractedImage
    |> where([e], e.status == "published" and e.status != "deleted")
    |> where([e], not is_nil(e.ptif_path) and e.ptif_path != "")
    |> apply_text_search(query_text)
    |> apply_filters(filters)
    |> Repo.aggregate(:count, :id)
  end

  # --- プライベート関数 ---

  # テキスト検索（PostgreSQL FTS）の適用
  defp apply_text_search(query, nil), do: query
  defp apply_text_search(query, ""), do: query

  defp apply_text_search(query, text) when is_binary(text) do
    # simple 辞書で日本語も安全に処理
    sanitized = sanitize_search_text(text)

    query
    |> where(
      [e],
      fragment(
        "to_tsvector('simple', coalesce(?, '')) @@ plainto_tsquery('simple', ?)",
        e.caption,
        ^sanitized
      ) or
        ilike(e.label, ^"%#{sanitized}%") or
        ilike(e.caption, ^"%#{sanitized}%") or
        ilike(e.site, ^"%#{sanitized}%")
    )
  end

  # フィルターの適用
  defp apply_filters(query, filters) when is_map(filters) do
    query
    |> maybe_filter(:site, filters["site"])
    |> maybe_filter(:period, filters["period"])
    |> maybe_filter(:artifact_type, filters["artifact_type"])
  end

  defp apply_filters(query, _), do: query

  # 個別フィルターの適用
  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query

  defp maybe_filter(query, :site, value) do
    where(query, [e], e.site == ^value)
  end

  defp maybe_filter(query, :period, value) do
    where(query, [e], e.period == ^value)
  end

  defp maybe_filter(query, :artifact_type, value) do
    where(query, [e], e.artifact_type == ^value)
  end

  # DISTINCT 値の取得
  defp list_distinct_values(field) do
    ExtractedImage
    |> where([e], not is_nil(field(e, ^field)))
    |> where([e], field(e, ^field) != "")
    |> select([e], field(e, ^field))
    |> distinct(true)
    |> order_by([e], asc: field(e, ^field))
    |> Repo.all()
  end

  # 検索テキストのサニタイズ（SQLインジェクション防止）
  defp sanitize_search_text(text) do
    text
    |> String.trim()
    |> String.replace(~r/[%_\\]/, fn
      "%" -> "\\%"
      "_" -> "\\_"
      "\\" -> "\\\\"
    end)
  end
end
