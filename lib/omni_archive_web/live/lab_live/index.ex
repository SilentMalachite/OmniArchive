defmodule OmniArchiveWeb.LabLive.Index do
  @moduledoc """
  Lab トップページ: プロジェクト（PdfSource）一覧を表示。
  各プロジェクトのカードにファイル名、ページ数、画像数、ステータスを表示し、
  詳細画面への遷移と削除機能を提供します。
  """
  use OmniArchiveWeb, :live_view

  alias OmniArchive.Ingestion

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    projects =
      current_user
      |> Ingestion.list_user_pdf_sources()
      |> Enum.map(fn p -> Map.put(p, :published?, Ingestion.published?(p)) end)

    {:ok,
     socket
     |> assign(:page_title, "プロジェクト一覧")
     |> assign(:projects, projects)}
  end

  @impl true
  def handle_event("delete_project", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user

    case Ingestion.get_pdf_source(id, current_user) do
      nil ->
        {:noreply, put_flash(socket, :error, "プロジェクトが見つかりません。")}

      pdf_source ->
        case Ingestion.soft_delete_pdf_source(pdf_source) do
          {:ok, _} ->
            # ローカルステートから削除
            projects = Enum.reject(socket.assigns.projects, &(&1.id == pdf_source.id))

            {:noreply,
             socket
             |> assign(:projects, projects)
             |> put_flash(:info, "プロジェクト「#{pdf_source.filename}」をゴミ箱に移動しました。")}

          {:error, :published_project} ->
            {:noreply, put_flash(socket, :error, "公開中のプロジェクトは削除できません。")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "ゴミ箱への移動に失敗しました。")}
        end
    end
  end

  @impl true
  def handle_event("submit_project", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user

    case Ingestion.get_pdf_source(id, current_user) do
      nil ->
        {:noreply, put_flash(socket, :error, "プロジェクトが見つかりません。")}

      pdf_source ->
        case Ingestion.submit_project(pdf_source) do
          {:ok, updated} ->
            # ローカルステートを更新
            projects =
              Enum.map(socket.assigns.projects, fn p ->
                if p.id == updated.id,
                  do: %{p | workflow_status: updated.workflow_status, return_message: nil},
                  else: p
              end)

            {:noreply,
             socket
             |> assign(:projects, projects)
             |> put_flash(:info, "プロジェクト「#{pdf_source.filename}」を作業完了として提出しました。")}

          {:error, :invalid_status_transition} ->
            {:noreply, put_flash(socket, :error, "このステータスからは提出できません。")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "提出に失敗しました。")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lab-container">
      <div class="lab-header">
        <h1 class="lab-title">📁 プロジェクト一覧</h1>
        <.link navigate={~p"/lab/upload"} class="btn-primary">
          📤 新規アップロード
        </.link>
      </div>

      <%= if @projects == [] do %>
        <div class="lab-empty-state">
          <span class="lab-empty-icon">📭</span>
          <p class="lab-empty-text">プロジェクトがまだありません。</p>
          <p class="lab-empty-hint">PDFをアップロードして最初のプロジェクトを作成しましょう。</p>
          <.link navigate={~p"/lab/upload"} class="btn-primary btn-large">
            📤 PDFをアップロード
          </.link>
        </div>
      <% else %>
        <div class="project-grid">
          <%= for project <- @projects do %>
            <div class="project-card" id={"project-#{project.id}"}>
              <.link navigate={~p"/lab/projects/#{project.id}"} class="project-card-link">
                <div class="project-card-header">
                  <span class="project-card-icon">📄</span>
                  <div class="project-card-badges">
                    <%= cond do %>
                      <% project.published? -> %>
                        <span class="project-status-badge project-status-published">🔒 公開中</span>
                      <% project.workflow_status == "pending_review" -> %>
                        <span class="workflow-status-badge workflow-status-pending_review">審査待ち</span>
                      <% project.workflow_status == "returned" -> %>
                        <span class="workflow-status-badge workflow-status-returned">⚠️ 差し戻しあり</span>
                      <% project.workflow_status == "approved" -> %>
                        <span class="workflow-status-badge workflow-status-approved">承認済み</span>
                      <% true -> %>
                        <span class="workflow-status-badge workflow-status-wip">作業中</span>
                    <% end %>
                  </div>
                </div>
                <h3 class="project-card-title">{project.filename}</h3>
                <div class="project-card-meta">
                  <%= if project.page_count do %>
                    <span class="meta-tag">📃 {project.page_count} ページ</span>
                  <% end %>
                  <span class="meta-tag">🖼️ {project.image_count} 画像</span>
                </div>
                <%= if @current_user.role == "admin" && project.owner_email do %>
                  <div class="project-card-owner">
                    <span class="owner-email">👤 {project.owner_email}</span>
                  </div>
                <% end %>
                <div class="project-card-date">
                  {Calendar.strftime(project.inserted_at, "%Y/%m/%d %H:%M")}
                </div>
              </.link>

              <%!-- 差し戻しメッセージ --%>
              <%= if project.workflow_status == "returned" && project.return_message do %>
                <div class="return-message-alert">
                  <span class="return-message-icon">⚠️</span>
                  <div class="return-message-content">
                    <strong>差し戻しメッセージ:</strong>
                    <p>{project.return_message}</p>
                  </div>
                </div>
              <% end %>

              <div class="project-card-actions">
                <%!-- ワークフロー提出ボタン --%>
                <%= if project.workflow_status in ["wip", "returned"] do %>
                  <button
                    type="button"
                    class="btn-submit-workflow"
                    phx-click="submit_project"
                    phx-value-id={project.id}
                    data-confirm="プロジェクト「#{project.filename}」を作業完了として提出しますか？"
                  >
                    ✅ 作業完了として提出
                  </button>
                <% end %>

                <%!-- 削除/ロック --%>
                <%= if project.published? do %>
                  <span class="lock-badge" title="ギャラリー公開中のため削除ロック">
                    🔒 公開中
                  </span>
                <% else %>
                  <button
                    type="button"
                    class="btn-danger-sm"
                    phx-click="delete_project"
                    phx-value-id={project.id}
                    data-confirm={"プロジェクト「#{project.filename}」をゴミ箱に移動しますか？\n管理者が復元・完全削除できます。"}
                  >
                    🗑️ 削除
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
