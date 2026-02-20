defmodule AlchemIiifWeb.InspectorLive.Browse do
  @moduledoc """
  ウィザード Step 2: ページ閲覧・選択画面。
  PDFから変換されたページのサムネイルをグリッド表示し、
  ユーザーが図版を含むページを手動で選択します。
  """
  use AlchemIiifWeb, :live_view

  import AlchemIiifWeb.WizardComponents

  alias AlchemIiif.Ingestion

  @impl true
  def mount(%{"pdf_source_id" => pdf_source_id}, _session, socket) do
    pdf_source =
      try do
        Ingestion.get_pdf_source!(pdf_source_id, socket.assigns.current_user)
      rescue
        Ecto.NoResultsError -> nil
      end

    if is_nil(pdf_source) do
      {:ok,
       socket
       |> put_flash(:error, "指定されたPDFソースが見つかりません（ID: #{pdf_source_id}）")
       |> push_navigate(to: ~p"/lab")}
    else
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])

      # ページ画像のリストを取得
      page_images =
        if File.dir?(pages_dir) do
          pages_dir
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".png"))
          |> Enum.sort()
          |> Enum.with_index(1)
          |> Enum.map(fn {filename, index} ->
            %{
              filename: filename,
              page_number: index,
              # 静的ファイルとして配信するパス
              url: "/uploads/pages/#{pdf_source.id}/#{filename}"
            }
          end)
        else
          []
        end

      {:ok,
       socket
       |> assign(:page_title, "ページを選択")
       |> assign(:current_step, 2)
       |> assign(:pdf_source, pdf_source)
       |> assign(:page_images, page_images)}
    end
  end

  @impl true
  def handle_event("select_page", %{"page" => page_str}, socket) do
    case Integer.parse(to_string(page_str)) do
      {page_number, _} ->
        # ページの存在確認のみ行い、レコードは作成しない（Write-on-Action）
        page_image =
          Enum.find(socket.assigns.page_images, &(&1.page_number == page_number))

        if page_image do
          # ダイレクトに Crop 画面へ遷移（Lazy Creation ルート）
          pdf_id = socket.assigns.pdf_source.id

          {:noreply, push_navigate(socket, to: ~p"/lab/inspector/#{pdf_id}/page/#{page_number}")}
        else
          {:noreply, put_flash(socket, :error, "指定されたページが見つかりません")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "無効なページ番号です")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-container">
      <.wizard_header current_step={@current_step} />

      <div class="browse-area">
        <%= cond do %>
          <% @pdf_source.status == "error" -> %>
            <div class="error-state">
              <div class="error-icon-large">❌</div>
              <h2 class="error-title">PDFの処理中にエラーが発生しました</h2>
              <p class="error-description">
                申し訳ありませんが、PDFファイルの変換に失敗しました。<br /> ログを確認するか、別のファイルをお試しください。
              </p>
              <div class="action-bar-center">
                <.link navigate={~p"/lab"} class="btn-primary btn-large">
                  最初に戻る
                </.link>
              </div>
            </div>
          <% @pdf_source.status == "ready" and Enum.empty?(@page_images) -> %>
            <div class="warning-state">
              <div class="warning-icon-large">⚠️</div>
              <h2 class="warning-title">画像が見つかりませんでした</h2>
              <p class="warning-description">
                処理は完了しましたが、ページ画像が生成されませんでした。<br /> PDFファイルが破損しているか、ページが含まれていない可能性があります。
              </p>
              <div class="action-bar-center">
                <.link navigate={~p"/lab"} class="btn-secondary btn-large">
                  戻る
                </.link>
              </div>
            </div>
          <% true -> %>
            <h2 class="section-title">ページを選択してください</h2>
            <p class="section-description">
              「{@pdf_source.filename}」のページ一覧です。<br /> 図版や挿絵が含まれているページをクリックするとクロップ画面へ進みます。
            </p>

            <div class="page-grid">
              <%= for page <- @page_images do %>
                <button
                  type="button"
                  class="page-thumbnail"
                  phx-click="select_page"
                  phx-value-page={page.page_number}
                  aria-label={"ページ #{page.page_number}"}
                >
                  <img
                    src={page.url}
                    alt={"ページ #{page.page_number}"}
                    loading="lazy"
                  />
                  <span class="page-label">ページ {page.page_number}</span>
                </button>
              <% end %>
            </div>

            <div class="action-bar">
              <.link navigate={~p"/lab"} class="btn-secondary btn-large">
                ← 戻る
              </.link>
            </div>
        <% end %>
      </div>
    </div>

    <style>
      .error-state, .warning-state {
        text-align: center;
        padding: 3rem 1rem;
        background: #fdf2f8;
        border-radius: 12px;
        margin-top: 2rem;
      }
      .warning-state {
        background: #fffbeb;
      }
      .error-icon-large, .warning-icon-large {
        font-size: 4rem;
        margin-bottom: 1rem;
      }
      .error-title, .warning-title {
        font-size: 1.5rem;
        font-weight: bold;
        color: #be123c;
        margin-bottom: 0.5rem;
      }
      .warning-title {
        color: #b45309;
      }
      .error-description, .warning-description {
        color: #374151;
        margin-bottom: 2rem;
      }
      .action-bar-center {
        display: flex;
        justify-content: center;
      }
    </style>
    """
  end
end
