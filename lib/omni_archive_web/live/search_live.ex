defmodule OmniArchiveWeb.SearchLive do
  @moduledoc """
  検索画面の LiveView。
  インクリメンタル検索バーと大きなフィルターチップスによる
  画像メタデータ検索を提供します。

  認知アクセシビリティ対応:
  - 大きなフィルターチップス（最小60x60px）
  - サムネイルグリッドで結果表示（テキスト密度を低減）
  - search-as-you-type（300ms デバウンス）
  """
  use OmniArchiveWeb, :live_view

  alias OmniArchive.DomainProfiles
  alias OmniArchive.Ingestion.ExtractedImageMetadata
  alias OmniArchive.Search

  @impl true
  def mount(_params, _session, socket) do
    # 利用可能なフィルターオプションを取得
    filter_options = Search.list_filter_options()

    # 初期表示: 全ての公開済み画像を表示
    results = Search.search_images()
    result_count = length(results)

    {:ok,
     socket
     |> assign(:page_title, DomainProfiles.ui_text([:search, :page_title]))
     |> assign(:query, "")
     |> assign(:filters, %{})
     |> assign(:facets, Search.facet_definitions())
     |> assign(:filter_options, filter_options)
     |> assign(:results, results)
     |> assign(:result_count, result_count)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    results = Search.search_images(query, socket.assigns.filters)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:results, results)
     |> assign(:result_count, length(results))}
  end

  @impl true
  def handle_event("toggle_filter", %{"type" => type, "value" => value}, socket) do
    filters = socket.assigns.filters

    # 同じフィルターを再度クリックした場合はクリア
    updated_filters =
      if filters[type] == value do
        Map.delete(filters, type)
      else
        Map.put(filters, type, value)
      end

    results = Search.search_images(socket.assigns.query, updated_filters)

    {:noreply,
     socket
     |> assign(:filters, updated_filters)
     |> assign(:results, results)
     |> assign(:result_count, length(results))}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    results = Search.search_images(socket.assigns.query, %{})

    {:noreply,
     socket
     |> assign(:filters, %{})
     |> assign(:results, results)
     |> assign(:result_count, length(results))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="search-container">
      <div class="search-header">
        <h1 class="section-title">{ui_text([:search, :heading])}</h1>
        <p class="section-description">
          {ui_text([:search, :description])}
        </p>
      </div>

      <%!-- 検索バー --%>
      <div class="search-bar">
        <span class="search-icon">🔍</span>
        <input
          type="search"
          id="search-input"
          class="search-input"
          placeholder={ui_text([:search, :placeholder])}
          value={@query}
          phx-keyup="search"
          phx-value-query={@query}
          phx-debounce="300"
          name="query"
          autocomplete="off"
        />
      </div>

      <%!-- フィルターチップス --%>
      <div class="filter-section">
        <%= if has_any_filters?(@filter_options) do %>
          <%= for facet <- @facets do %>
            <% options = facet_options(@filter_options, facet) %>
            <%= if options != [] do %>
              <div class="filter-group">
                <span class="filter-group-label">{facet.label}</span>
                <div class="filter-chips">
                  <%= for option <- options do %>
                    <button
                      type="button"
                      class={"filter-chip #{if @filters[facet.param] == option, do: "active", else: ""}"}
                      phx-click="toggle_filter"
                      phx-value-type={facet.param}
                      phx-value-value={option}
                      aria-pressed={@filters[facet.param] == option}
                    >
                      {option}
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
          <% end %>

          <%!-- フィルタークリア --%>
          <%= if @filters != %{} do %>
            <button
              type="button"
              class="btn-secondary btn-large"
              phx-click="clear_filters"
              style="margin-top: 1rem;"
            >
              {ui_text([:search, :clear_filters])}
            </button>
          <% end %>
        <% end %>
      </div>

      <%!-- 検索結果 --%>
      <div class="results-count">
        {result_text(@result_count)}
      </div>

      <%= if @results == [] do %>
        <div class="no-results">
          <span class="no-results-icon">📭</span>
          <p class="section-description">
            <%= if @query != "" || @filters != %{} do %>
              {ui_text([:search, :empty_filtered])}<br /> {ui_text([:search, :empty_filtered_hint])}
            <% else %>
              {ui_text([:search, :empty_initial])}<br />
              <a href="/inspector" class="info-link">Inspector</a> から PDF をアップロードして図版を登録してください。
            <% end %>
          </p>
        </div>
      <% else %>
        <div class="results-grid">
          <%= for image <- @results do %>
            <div class="result-card">
              <a href={manifest_url(image)} class="result-card-link" target="_blank">
                <img
                  src={image_thumbnail_url(image)}
                  alt={image.caption || "図版"}
                  class="result-card-image"
                  loading="lazy"
                />
                <div class="result-card-body">
                  <h3 class="result-card-title">{image.label || "名称未設定"}</h3>
                  <%= if image.caption do %>
                    <p class="result-card-caption">{image.caption}</p>
                  <% end %>
                  <div class="result-card-meta">
                    <%= for field <- metadata_display_fields() do %>
                      <% value = metadata_value(image, field.field) %>
                      <%= if value not in [nil, ""] do %>
                        <span class="meta-tag">{metadata_icon(field.field)} {value}</span>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              </a>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- プライベート関数 ---

  # フィルターオプションが存在するかチェック
  defp has_any_filters?(filter_options) do
    Enum.any?(Search.facet_definitions(), fn facet ->
      facet_options(filter_options, facet) != []
    end)
  end

  # 結果件数のテキスト
  defp result_text(0), do: ui_text([:search, :result_none])
  defp result_text(count), do: "#{count} #{ui_text([:search, :result_suffix])}"

  defp ui_text(path), do: DomainProfiles.ui_text(path)
  defp metadata_value(image, field), do: ExtractedImageMetadata.read(image, field)
  defp metadata_display_fields, do: ExtractedImageMetadata.metadata_fields()
  defp facet_options(filter_options, facet), do: Map.get(filter_options, facet.field, [])

  defp metadata_icon(:site), do: "📍"
  defp metadata_icon(:period), do: "⏳"
  defp metadata_icon(:artifact_type), do: "🏺"
  defp metadata_icon(_field), do: "•"

  # Manifest URL の生成
  defp manifest_url(image) do
    case image.iiif_manifest do
      nil -> "#"
      manifest -> "/iiif/manifest/#{manifest.identifier}"
    end
  end

  # サムネイル URL の生成
  defp image_thumbnail_url(image) do
    case image.iiif_manifest do
      nil ->
        # PTIF なし：元画像を使用
        image.image_path
        |> String.replace_leading("priv/static/", "/")

      manifest ->
        # IIIF Image API でサムネイルを取得
        "/iiif/image/#{manifest.identifier}/full/300,/0/default.jpg"
    end
  end
end
