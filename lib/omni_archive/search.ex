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
  alias OmniArchive.DomainProfiles
  alias OmniArchive.Ingestion.ExtractedImage
  alias OmniArchive.Ingestion.ExtractedImageMetadata
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
  各フィルターの DISTINCT 値を field 名キーの map で返します。
  """
  def list_filter_options do
    Enum.reduce(facet_definitions(), %{}, fn facet, acc ->
      Map.put(acc, facet.field, list_distinct_values(facet.field))
    end)
  end

  @doc "有効な profile に定義された検索ファセット一覧を返します。"
  def facet_definitions, do: DomainProfiles.search_facets()

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
    pattern = "%#{sanitized}%"
    metadata_search = metadata_text_search_dynamic(sanitized)

    text_search =
      dynamic(
        [e],
        fragment(
          "to_tsvector('simple', coalesce(?, '')) @@ plainto_tsquery('simple', ?)",
          e.caption,
          ^sanitized
        ) or
          ilike(e.label, ^pattern) or
          ilike(e.caption, ^pattern) or
          ^metadata_search
      )

    query
    |> where(^text_search)
  end

  # フィルターの適用
  defp apply_filters(query, filters) when is_map(filters) do
    Enum.reduce(facet_definitions(), query, fn facet, acc ->
      maybe_filter(acc, facet.field, filters[facet.param])
    end)
  end

  defp apply_filters(query, _), do: query

  # 個別フィルターの適用
  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query

  defp maybe_filter(query, field_name, value) do
    where(query, ^field_equals_dynamic(field_name, value))
  end

  # DISTINCT 値の取得
  defp list_distinct_values(field_name),
    do: list_distinct_fragment_values(field_name, Atom.to_string(field_name))

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

  defp list_distinct_fragment_values(field_name, metadata_key) do
    ExtractedImage
    |> where(^field_present_dynamic(field_name, metadata_key))
    |> select(^field_value_dynamic(field_name, metadata_key))
    |> distinct(true)
    |> Repo.all()
    |> Enum.sort()
  end

  defp metadata_text_search_dynamic(sanitized) do
    pattern = "%#{sanitized}%"

    Enum.reduce(ExtractedImageMetadata.metadata_field_names(), dynamic(false), fn metadata_field,
                                                                                  acc ->
      metadata_key = Atom.to_string(metadata_field)

      dynamic(
        [e],
        ^acc or
          ilike(^field_value_dynamic(metadata_field, metadata_key), ^pattern)
      )
    end)
  end

  defp field_equals_dynamic(field_name, value) do
    metadata_key = Atom.to_string(field_name)

    dynamic([e], ^field_value_dynamic(field_name, metadata_key) == ^value)
  end

  defp field_present_dynamic(field_name, metadata_key) do
    dynamic(
      [e],
      not is_nil(^field_value_dynamic(field_name, metadata_key)) and
        ^field_value_dynamic(field_name, metadata_key) != ""
    )
  end

  defp field_value_dynamic(field_name, metadata_key) do
    if ExtractedImageMetadata.schema_field?(field_name) do
      dynamic(
        [e],
        fragment("COALESCE(?->>?, ?)", e.metadata, ^metadata_key, field(e, ^field_name))
      )
    else
      dynamic([e], fragment("?->>?", e.metadata, ^metadata_key))
    end
  end
end
