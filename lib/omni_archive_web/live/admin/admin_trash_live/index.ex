defmodule OmniArchiveWeb.Admin.AdminTrashLive.Index do
  @moduledoc """
  Admin ゴミ箱ページ: ソフトデリート済みの PdfSource 一覧を表示。
  復元（restore）と完全削除（hard delete）のアクションを提供します。

  ## アクセス制御
  - `on_mount(:ensure_admin)` により Admin ロール以外はリダイレクトされます。
  """
  use OmniArchiveWeb, :live_view

  alias OmniArchive.Ingestion

  @impl true
  def mount(_params, _session, socket) do
    projects = Ingestion.list_deleted_pdf_sources()

    {:ok,
     socket
     |> assign(:page_title, "🗑️ ゴミ箱")
     |> assign(:projects, projects)}
  end

  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    case Ingestion.restore_pdf_source(id) do
      {:ok, restored} ->
        projects = Enum.reject(socket.assigns.projects, &(&1.id == restored.id))

        {:noreply,
         socket
         |> assign(:projects, projects)
         |> put_flash(:info, "「#{restored.filename}」を復元しました。")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "復元に失敗しました。")}
    end
  end

  @impl true
  def handle_event("destroy", %{"id" => id}, socket) do
    case Ingestion.get_pdf_source(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "完全削除に失敗しました。")}

      pdf_source ->
        case Ingestion.hard_delete_pdf_source(pdf_source) do
          {:ok, _} ->
            projects = Enum.reject(socket.assigns.projects, &(&1.id == pdf_source.id))

            {:noreply,
             socket
             |> assign(:projects, projects)
             |> put_flash(:info, "「#{pdf_source.filename}」を完全に削除しました。")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "完全削除に失敗しました。")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <%!-- ヘッダー --%>
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-100 flex items-center gap-2">
          🗑️ ゴミ箱
        </h1>
        <p class="mt-2 text-sm text-gray-400">
          ソフトデリート済みのプロジェクト一覧（{length(@projects)} 件）
        </p>
      </div>

      <%!-- テーブル --%>
      <div :if={@projects != []} class="overflow-x-auto rounded-lg border border-gray-700 shadow-lg">
        <table class="min-w-full divide-y divide-gray-700">
          <thead class="bg-gray-800">
            <tr>
              <th
                scope="col"
                class="px-4 py-3 text-left text-xs font-semibold text-gray-300 uppercase tracking-wider"
              >
                ID
              </th>
              <th
                scope="col"
                class="px-4 py-3 text-left text-xs font-semibold text-gray-300 uppercase tracking-wider"
              >
                ファイル名
              </th>
              <th
                scope="col"
                class="px-4 py-3 text-left text-xs font-semibold text-gray-300 uppercase tracking-wider"
              >
                画像数
              </th>
              <th
                scope="col"
                class="px-4 py-3 text-left text-xs font-semibold text-gray-300 uppercase tracking-wider"
              >
                削除日時
              </th>
              <th
                scope="col"
                class="px-4 py-3 text-left text-xs font-semibold text-gray-300 uppercase tracking-wider"
              >
                操作
              </th>
            </tr>
          </thead>
          <tbody id="trash-table-body" class="bg-gray-900 divide-y divide-gray-800">
            <%= for project <- @projects do %>
              <tr
                id={"trash-row-#{project.id}"}
                class="hover:bg-gray-800/60 transition-colors duration-150"
              >
                <%!-- ID --%>
                <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-300 font-mono">
                  {project.id}
                </td>

                <%!-- ファイル名 --%>
                <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-300">
                  📄 {project.filename}
                </td>

                <%!-- 画像数 --%>
                <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-300">
                  {project.image_count}
                </td>

                <%!-- 削除日時 --%>
                <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-400">
                  {Calendar.strftime(project.deleted_at, "%Y-%m-%d %H:%M")}
                </td>

                <%!-- 操作ボタン --%>
                <td class="px-4 py-3 whitespace-nowrap text-sm flex gap-2">
                  <button
                    phx-click="restore"
                    phx-value-id={project.id}
                    class="inline-flex items-center gap-1 px-3 py-1.5 rounded-md text-emerald-400 hover:text-emerald-300 hover:bg-emerald-900/30 transition-colors duration-150 text-xs font-medium border border-emerald-800/50 hover:border-emerald-700"
                  >
                    ♻️ 復元
                  </button>
                  <button
                    phx-click="destroy"
                    phx-value-id={project.id}
                    data-confirm={"「#{project.filename}」を完全に削除しますか？\n関連する全ての画像ファイルも削除されます。この操作は元に戻せません。"}
                    class="inline-flex items-center gap-1 px-3 py-1.5 rounded-md text-red-400 hover:text-red-300 hover:bg-red-900/30 transition-colors duration-150 text-xs font-medium border border-red-800/50 hover:border-red-700"
                  >
                    💀 完全削除
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%!-- 空の場合 --%>
      <div :if={@projects == []} class="mt-8 text-center py-12">
        <span class="text-4xl">✨</span>
        <p class="mt-4 text-gray-400">ゴミ箱は空です。</p>
      </div>
    </div>
    """
  end
end
