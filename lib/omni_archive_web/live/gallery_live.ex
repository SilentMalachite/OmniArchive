defmodule OmniArchiveWeb.GalleryLive do
  @moduledoc """
  公開ギャラリー (Museum) LiveView。
  status == 'published' の画像のみを表示する読み取り専用ビューです。
  編集ツールや Nudge ボタンは配置しません。

  認知アクセシビリティ対応:
  - 大きなフィルターチップス（最小60x60px）
  - サムネイルグリッドで結果表示（テキスト密度を低減）
  - search-as-you-type（300ms デバウンス）
  """
  use OmniArchiveWeb, :live_view

  alias OmniArchive.DomainProfiles
  alias OmniArchive.Ingestion
  alias OmniArchive.Ingestion.ExtractedImageMetadata
  alias OmniArchive.Ingestion.ImageProcessor
  alias OmniArchive.Search

  @impl true
  def mount(_params, _session, socket) do
    # 利用可能なフィルターオプションを取得
    filter_options = Search.list_filter_options()

    # 公開済み画像のみ表示
    results = Search.search_published_images()
    match_count = Search.count_published_results()
    preview_map = build_preview_map(results)

    {:ok,
     socket
     |> assign(:page_title, "ギャラリー")
     |> assign(:query, "")
     |> assign(:filters, %{})
     |> assign(:facets, Search.facet_definitions())
     |> assign(:filter_options, filter_options)
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:preview_map, preview_map)
     |> assign(:selected_image, nil)
     |> assign(:selected_dims, {0, 0})
     |> assign(:selected_polygon_points, nil)
     |> assign(:selected_bbox, nil)
     |> assign(:iiif_image_info_url, nil)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    results = Search.search_published_images(query, socket.assigns.filters)
    match_count = Search.count_published_results(query, socket.assigns.filters)
    preview_map = build_preview_map(results)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:preview_map, preview_map)}
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

    results = Search.search_published_images(socket.assigns.query, updated_filters)
    match_count = Search.count_published_results(socket.assigns.query, updated_filters)
    preview_map = build_preview_map(results)

    {:noreply,
     socket
     |> assign(:filters, updated_filters)
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:preview_map, preview_map)}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    results = Search.search_published_images(socket.assigns.query, %{})
    match_count = Search.count_published_results(socket.assigns.query, %{})
    preview_map = build_preview_map(results)

    {:noreply,
     socket
     |> assign(:filters, %{})
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:preview_map, preview_map)}
  end

  @impl true
  def handle_event("select_image", %{"id" => id}, socket) do
    case Ingestion.get_extracted_image_with_manifest(id) do
      nil ->
        {:noreply, socket}

      image ->
        dims = read_source_dimensions(image.image_path)
        info_url = build_iiif_info_url(image)
        {polygon_points, bbox} = extract_preview_data(image.geometry)

        {:noreply,
         socket
         |> assign(:selected_image, image)
         |> assign(:selected_dims, dims)
         |> assign(:selected_polygon_points, polygon_points)
         |> assign(:selected_bbox, bbox)
         |> assign(:iiif_image_info_url, info_url)}
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_image, nil)
     |> assign(:selected_dims, {0, 0})
     |> assign(:selected_polygon_points, nil)
     |> assign(:selected_bbox, nil)
     |> assign(:iiif_image_info_url, nil)}
  end

  # Esc キーによるモーダル閉鎖（常時リッスン、モーダル開時のみ反応）
  @impl true
  def handle_event("handle_keydown", %{"key" => "Escape"}, socket) do
    if socket.assigns.selected_image do
      {:noreply,
       socket
       |> assign(:selected_image, nil)
       |> assign(:selected_dims, {0, 0})
       |> assign(:selected_polygon_points, nil)
       |> assign(:selected_bbox, nil)
       |> assign(:iiif_image_info_url, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("handle_keydown", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="gallery-container" phx-window-keydown="handle_keydown" phx-key="Escape">
      <div class="gallery-header">
        <h1 class="section-title">🏛️ ギャラリー</h1>
        <p class="section-description">
          公開済みの図版コレクションです。キーワードやフィルターで検索できます。
        </p>
      </div>

      <%!-- 使用方法ガイド --%>
      <div class="text-center mb-4 text-gray-400 text-sm">
        <span class="inline-flex items-center gap-2">
          <.icon name="hero-cursor-arrow-rays" class="w-4 h-4 text-[#E6B422]" /> 図版をクリックして拡大表示
          <span class="mx-2 text-gray-600">|</span>
          <kbd class="px-2 py-0.5 rounded bg-gray-800 border border-gray-700 text-xs font-mono text-gray-300">
            Esc
          </kbd>
          キーで閉じる
        </span>
      </div>

      <%!-- 検索バー --%>
      <div class="search-bar">
        <span class="search-icon">🔍</span>
        <input
          type="search"
          id="gallery-search-input"
          class="search-input"
          placeholder={DomainProfiles.ui_text([:search, :placeholder])}
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
              ✕ フィルターをクリア
            </button>
          <% end %>
        <% end %>
      </div>

      <%!-- 検索結果 --%>
      <div class="results-count">
        {result_text(@match_count)}
      </div>

      <%= if @match_count == 0 do %>
        <div class="no-results-container">
          <div class="no-results-card">
            <div class="no-results-icon-box">
              <.icon name="hero-magnifying-glass" class="w-16 h-16 text-[#A0AEC0] opacity-40" />
            </div>
            <h2 class="no-results-title">条件に一致する図版はありませんでした。</h2>
            <p class="section-description">
              <%= if @query != "" || @filters != %{} do %>
                検索キーワードやフィルターを変更してみてください。
              <% else %>
                まだ公開済みの図版がありません。
              <% end %>
            </p>
            <%= if @query != "" || @filters != %{} do %>
              <button
                type="button"
                class="btn-reset-filters"
                phx-click="clear_filters"
              >
                <.icon name="hero-arrow-path" class="w-5 h-5" /> 検索条件をリセット
              </button>
            <% end %>
          </div>
        </div>
      <% else %>
        <div class="results-grid columns-1 sm:columns-2 md:columns-3 lg:columns-4 gap-4 space-y-4">
          <%= for image <- @results do %>
            <div
              class="result-card break-inside-avoid mb-4 group relative border-2 border-transparent hover:border-[#E6B422] transition-colors duration-300 will-change-transform cursor-pointer"
              phx-click="select_image"
              phx-value-id={image.id}
            >
              <div class="result-card-link">
                <%= if image.geometry do %>
                  <% {orig_w, orig_h, poly_pts, card_bbox} =
                    Map.get(@preview_map, image.id, {0, 0, nil, nil}) %>
                  <%= if card_bbox do %>
                    <div class="relative w-full bg-[#0F1923] flex items-center justify-center rounded-t-lg overflow-hidden">
                      <svg
                        viewBox={"#{card_bbox.x} #{card_bbox.y} #{card_bbox.width} #{card_bbox.height}"}
                        class="w-full h-auto"
                        preserveAspectRatio="xMidYMid meet"
                      >
                        <%!-- 白背景: clipPath 外の透過領域を白で塗りつぶし --%>
                        <rect
                          x={card_bbox.x}
                          y={card_bbox.y}
                          width={card_bbox.width}
                          height={card_bbox.height}
                          fill="white"
                        />
                        <%= if poly_pts do %>
                          <%!-- ポリゴンデータ: clipPath でマスク --%>
                          <defs>
                            <clipPath id={"gallery-polygon-clip-#{image.id}"}>
                              <polygon points={poly_pts} />
                            </clipPath>
                          </defs>
                          <image
                            href={image_thumbnail_url(image)}
                            width={orig_w}
                            height={orig_h}
                            clip-path={"url(#gallery-polygon-clip-#{image.id})"}
                          />
                        <% else %>
                          <%!-- 旧矩形データ: クリップなし --%>
                          <image
                            href={image_thumbnail_url(image)}
                            width={orig_w}
                            height={orig_h}
                          />
                        <% end %>
                      </svg>
                    </div>
                  <% end %>
                <% else %>
                  <img
                    src={image_thumbnail_url(image)}
                    alt={image.caption || "図版"}
                    class="result-card-image"
                    loading="lazy"
                  />
                <% end %>
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
              </div>
              <%!-- ダウンロードボタン --%>
              <a
                href={~p"/download/#{image}"}
                class="download-btn"
                title="高解像度画像をダウンロード"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="download-icon"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                  />
                </svg>
                ダウンロード
              </a>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- 画像拡大モーダル --%>
      <%= if @selected_image do %>
        <div
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/90 backdrop-blur-sm p-4 transition-opacity"
          phx-click="close_modal"
        >
          <div
            class="relative w-full max-w-6xl h-full flex flex-col items-center justify-center"
            phx-click={JS.dispatch("phx:noop")}
          >
            <%!-- 画像ラベル --%>
            <div class="mb-2 text-center">
              <h3 class="text-white text-lg font-semibold">
                {@selected_image.label || "名称未設定"}
              </h3>
              <%= if @selected_image.caption do %>
                <p class="text-gray-400 text-sm">{@selected_image.caption}</p>
              <% end %>
            </div>

            <%!-- OpenSeadragon Deep Zoom ビューア（IIIF manifest がある場合） --%>
            <%= if @iiif_image_info_url do %>
              <div
                id="osd-viewer"
                phx-hook="OpenSeadragonViewer"
                phx-update="ignore"
                data-info-url={@iiif_image_info_url}
                class="w-full min-h-[70vh] bg-black relative z-[9999] pointer-events-auto touch-none"
              >
              </div>
            <% else %>
              <%!-- フォールバック: 従来の静止画表示（PTIFF 未生成時） --%>
              <div class="relative w-full h-full flex items-center justify-center">
                <%= if @selected_image.geometry && @selected_bbox do %>
                  <% {orig_w, orig_h} = @selected_dims %>
                  <svg
                    viewBox={"#{@selected_bbox.x} #{@selected_bbox.y} #{@selected_bbox.width} #{@selected_bbox.height}"}
                    class="max-w-full max-h-[90vh] shadow-2xl"
                    preserveAspectRatio="xMidYMid meet"
                  >
                    <%!-- 白背景: clipPath 外の透過領域を白で塗りつぶし --%>
                    <rect
                      x={@selected_bbox.x}
                      y={@selected_bbox.y}
                      width={@selected_bbox.width}
                      height={@selected_bbox.height}
                      fill="white"
                    />
                    <%= if @selected_polygon_points do %>
                      <defs>
                        <clipPath id={"gallery-modal-clip-#{@selected_image.id}"}>
                          <polygon points={@selected_polygon_points} />
                        </clipPath>
                      </defs>
                      <image
                        href={image_thumbnail_url(@selected_image)}
                        width={orig_w}
                        height={orig_h}
                        clip-path={"url(#gallery-modal-clip-#{@selected_image.id})"}
                      />
                    <% else %>
                      <image
                        href={image_thumbnail_url(@selected_image)}
                        width={orig_w}
                        height={orig_h}
                      />
                    <% end %>
                  </svg>
                <% else %>
                  <img
                    src={image_thumbnail_url(@selected_image)}
                    alt={@selected_image.caption || "図版"}
                    class="max-w-full max-h-[90vh] object-contain shadow-2xl"
                  />
                <% end %>
              </div>
            <% end %>

            <%!-- 閉じるボタン --%>
            <button
              type="button"
              class="absolute top-2 right-2 text-white/70 hover:text-white bg-black/50 hover:bg-black/80 rounded-full w-10 h-10 flex items-center justify-center transition-colors z-10"
              phx-click="close_modal"
              aria-label="閉じる"
            >
              ✕
            </button>
          </div>
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
  defp result_text(0), do: "結果なし"
  defp result_text(count), do: "#{count} 件の図版が見つかりました"
  defp metadata_value(image, field), do: ExtractedImageMetadata.read(image, field)
  defp metadata_display_fields, do: ExtractedImageMetadata.metadata_fields()
  defp facet_options(filter_options, facet), do: Map.get(filter_options, facet.field, [])

  defp metadata_icon(:site), do: "📍"
  defp metadata_icon(:period), do: "⏳"
  defp metadata_icon(:artifact_type), do: "🏺"
  defp metadata_icon(_field), do: "•"

  # 画像プレビューマップの構築（SVGカードクロップ + ポリゴン表示用）
  # 各画像IDに対し {dims_w, dims_h, polygon_points_str, bbox} を保持
  defp build_preview_map(images) do
    Map.new(images, fn image ->
      {orig_w, orig_h} = read_source_dimensions(image.image_path)
      {polygon_points, bbox} = extract_preview_data(image.geometry)
      {image.id, {orig_w, orig_h, polygon_points, bbox}}
    end)
  end

  # 元画像の寸法を Vix で読み取る（ヘッダーのみ遅延読み込みなので軽量）
  defp read_source_dimensions(image_path) do
    case ImageProcessor.get_image_dimensions(image_path) do
      {:ok, %{width: w, height: h}} -> {w, h}
      _error -> {0, 0}
    end
  end

  # ジオメトリデータからプレビュー用のポリゴン頂点とバウンディングボックスを抽出
  defp extract_preview_data(%{"points" => points}) when is_list(points) and length(points) >= 3 do
    xs = Enum.map(points, fn p -> safe_int(p["x"]) end)
    ys = Enum.map(points, fn p -> safe_int(p["y"]) end)

    min_x = Enum.min(xs)
    min_y = Enum.min(ys)
    max_x = Enum.max(xs)
    max_y = Enum.max(ys)

    bbox = %{
      x: min_x,
      y: min_y,
      width: max_x - min_x,
      height: max_y - min_y
    }

    # SVG polygon points 文字列を事前生成
    polygon_points_str =
      points
      |> Enum.map(fn p -> "#{safe_int(p["x"])},#{safe_int(p["y"])}" end)
      |> Enum.join(" ")

    {polygon_points_str, bbox}
  end

  # 旧矩形データの場合（後方互換性）
  defp extract_preview_data(%{"x" => x, "y" => y, "width" => w, "height" => h}) do
    bbox = %{x: safe_int(x), y: safe_int(y), width: safe_int(w), height: safe_int(h)}
    {nil, bbox}
  end

  defp extract_preview_data(_), do: {nil, nil}

  # 安全な整数変換
  defp safe_int(val) when is_integer(val), do: val
  defp safe_int(val) when is_float(val), do: round(val)

  defp safe_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp safe_int(_), do: 0

  # サムネイル URL の生成
  # サムネイルは常に元画像の静的パスを使用する。
  # SVG viewBox クロップは元画像のピクセル座標系で動作するため、
  # IIIF 経由のリサイズ済み画像では座標が合わなくなる。
  # IIIF Image API は OpenSeadragon Deep Zoom（モーダル）でのみ使用する。
  defp image_thumbnail_url(image) do
    image.image_path
    |> String.replace_leading("priv/static/", "/")
  end

  # IIIF Image API info.json URL の構築
  defp build_iiif_info_url(image) do
    case image.iiif_manifest do
      nil -> nil
      manifest -> "/iiif/image/#{manifest.identifier}/info.json"
    end
  end
end
