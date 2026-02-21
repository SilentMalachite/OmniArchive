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

  alias OmniArchive.Ingestion
  alias OmniArchive.Ingestion.ImageProcessor
  alias OmniArchive.Search

  @impl true
  def mount(_params, _session, socket) do
    # 公開済み画像のみ表示
    results = Search.search_published_images()
    match_count = Search.count_published_results()
    dims_map = build_dims_map(results)

    {:ok,
     socket
     |> assign(:page_title, "ギャラリー")
     |> assign(:query, "")
     |> assign(:filters, %{})
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:dims_map, dims_map)
     |> assign(:selected_image, nil)
     |> assign(:selected_dims, {0, 0})}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    results = Search.search_published_images(query, socket.assigns.filters)
    match_count = Search.count_published_results(query, socket.assigns.filters)
    dims_map = build_dims_map(results)

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:dims_map, dims_map)}
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
    dims_map = build_dims_map(results)

    {:noreply,
     socket
     |> assign(:filters, updated_filters)
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:dims_map, dims_map)}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    results = Search.search_published_images(socket.assigns.query, %{})
    match_count = Search.count_published_results(socket.assigns.query, %{})
    dims_map = build_dims_map(results)

    {:noreply,
     socket
     |> assign(:filters, %{})
     |> assign(:results, results)
     |> assign(:match_count, match_count)
     |> assign(:dims_map, dims_map)}
  end

  @impl true
  def handle_event("select_image", %{"id" => id}, socket) do
    case Ingestion.get_extracted_image_with_manifest(id) do
      nil ->
        {:noreply, socket}

      image ->
        dims = read_source_dimensions(image.image_path)

        {:noreply,
         socket
         |> assign(:selected_image, image)
         |> assign(:selected_dims, dims)}
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_image, nil)
     |> assign(:selected_dims, {0, 0})}
  end

  # Esc キーによるモーダル閉鎖（常時リッスン、モーダル開時のみ反応）
  @impl true
  def handle_event("handle_keydown", %{"key" => "Escape"}, socket) do
    if socket.assigns.selected_image do
      {:noreply,
       socket
       |> assign(:selected_image, nil)
       |> assign(:selected_dims, {0, 0})}
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
          id="gallery-search-input"
          class="search-input"
          placeholder="キャプション、ラベルで検索..."
          value={@query}
          phx-keyup="search"
          phx-value-query={@query}
          phx-debounce="300"
          name="query"
          autocomplete="off"
        />
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
                  <% geo = image.geometry %>
                  <% {orig_w, orig_h} = Map.get(@dims_map, image.id, {0, 0}) %>
                  <div class="relative w-full bg-[#0F1923] flex items-center justify-center rounded-t-lg overflow-hidden">
                    <svg
                      viewBox={"#{geo["x"]} #{geo["y"]} #{geo["width"]} #{geo["height"]}"}
                      class="w-full h-auto"
                      preserveAspectRatio="xMidYMid meet"
                    >
                      <image
                        href={image_thumbnail_url(image)}
                        width={orig_w}
                        height={orig_h}
                      />
                    </svg>
                  </div>
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
                  <div class="result-card-meta"></div>
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
            class="relative w-full max-w-6xl h-full flex items-center justify-center"
            phx-click={JS.dispatch("phx:noop")}
          >
            <%!-- 画像表示エリア --%>
            <div class="relative w-full h-full flex items-center justify-center pointer-events-none">
              <%= if @selected_image.geometry do %>
                <% geo = @selected_image.geometry %>
                <% {orig_w, orig_h} = @selected_dims %>
                <svg
                  viewBox={"#{geo["x"]} #{geo["y"]} #{geo["width"]} #{geo["height"]}"}
                  class="max-w-full max-h-[90vh] shadow-2xl"
                  preserveAspectRatio="xMidYMid meet"
                >
                  <image
                    href={image_thumbnail_url(@selected_image)}
                    width={orig_w}
                    height={orig_h}
                  />
                </svg>
              <% else %>
                <img
                  src={image_thumbnail_url(@selected_image)}
                  alt={@selected_image.caption || "図版"}
                  class="max-w-full max-h-[90vh] object-contain shadow-2xl"
                />
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # --- プライベート関数 ---

  # 結果件数のテキスト
  defp result_text(0), do: "結果なし"
  defp result_text(count), do: "#{count} 件の図版が見つかりました"

  # 画像寸法マップの構築（SVG viewBox クロップ表示用）
  defp build_dims_map(images) do
    Map.new(images, fn image ->
      dims = read_source_dimensions(image.image_path)
      {image.id, dims}
    end)
  end

  # 元画像の寸法を Vix で読み取る（ヘッダーのみ遅延読み込みなので軽量）
  defp read_source_dimensions(image_path) do
    case ImageProcessor.get_image_dimensions(image_path) do
      {:ok, %{width: w, height: h}} -> {w, h}
      _error -> {0, 0}
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
