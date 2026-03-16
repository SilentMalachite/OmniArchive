defmodule OmniArchiveWeb.Admin.DashboardLive do
  @moduledoc """
  Admin Dashboard LiveView。
  全ユーザーのアップロード画像を一覧表示する管理画面です。
  チェックボックスによる複数選択と一括削除機能を備えています。

  ## アクセス制御
  - `on_mount(:ensure_admin)` により Admin ロール以外はリダイレクトされます。
  - `Ingestion.list_extracted_images/1` が Admin の場合は全件を返します。
  """
  use OmniArchiveWeb, :live_view

  alias OmniArchive.Ingestion

  @impl true
  def mount(_params, _session, socket) do
    # 即座に空リストで表示 → バックグラウンドでデータロード
    send(self(), :load_images)

    {:ok,
     socket
     |> assign(:page_title, "Admin Dashboard")
     |> assign(:images, [])
     |> assign(:loading, true)
     |> assign(:selected_ids, MapSet.new())}
  end

  # --- イベントハンドラ ---

  @impl true
  def handle_event("toggle_selection", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    selected = socket.assigns.selected_ids

    updated =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected_ids, updated)}
  end

  @impl true
  def handle_event("toggle_all", _params, socket) do
    all_ids = MapSet.new(socket.assigns.images, & &1.id)
    selected = socket.assigns.selected_ids

    # 全選択済みなら解除、そうでなければ全選択
    updated =
      if MapSet.equal?(selected, all_ids),
        do: MapSet.new(),
        else: all_ids

    {:noreply, assign(socket, :selected_ids, updated)}
  end

  @impl true
  def handle_event("delete_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    # 公開済み画像を除外
    images_to_check = Enum.filter(socket.assigns.images, &(&1.id in ids))
    {published, deletable} = Enum.split_with(images_to_check, &(&1.status == "published"))
    deletable_ids = Enum.map(deletable, & &1.id)

    case Ingestion.delete_multiple_extracted_images(deletable_ids) do
      {:ok, count} ->
        id_set = MapSet.new(deletable_ids)
        updated_images = Enum.reject(socket.assigns.images, &MapSet.member?(id_set, &1.id))

        msg =
          if published != [],
            do: "#{count} 件削除（公開済み #{length(published)} 件はスキップ）",
            else: "#{count} 件の画像を削除しました"

        {:noreply,
         socket
         |> put_flash(:info, msg)
         |> assign(:images, updated_images)
         |> assign(:selected_ids, MapSet.new())}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "一括削除に失敗しました")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    image = Ingestion.get_extracted_image!(id)

    # 公開済み画像は通常削除不可（force_delete を使用）
    if image.status == "published" do
      {:noreply, put_flash(socket, :error, "公開済みの画像は削除できません")}
    else
      do_delete_image(image, id, socket)
    end
  end

  @impl true
  def handle_event("force_delete", %{"id" => id}, socket) do
    image = Ingestion.get_extracted_image!(id)
    do_delete_image(image, id, socket)
  end

  # --- 削除共通ヘルパー ---

  defp do_delete_image(image, id, socket) do
    case Ingestion.delete_extracted_image(image) do
      {:ok, _} ->
        image_id = String.to_integer(id)
        updated_images = Enum.reject(socket.assigns.images, &(&1.id == image_id))

        {:noreply,
         socket
         |> put_flash(:info, "画像を削除しました")
         |> assign(:images, updated_images)
         |> assign(:selected_ids, MapSet.delete(socket.assigns.selected_ids, image_id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "削除に失敗しました")}
    end
  end

  # --- 非同期データロード ---

  @impl true
  def handle_info(:load_images, socket) do
    images = Ingestion.list_extracted_images(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(:images, images)
     |> assign(:loading, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <%!-- ヘッダー --%>
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-100 flex items-center gap-2">
          📊 Admin Dashboard
        </h1>
        <p class="mt-2 text-sm text-gray-400">
          全ユーザーのアップロード画像一覧（{length(@images)} 件）
        </p>
      </div>

      <%!-- ローディング表示 --%>
      <div :if={@loading} class="flex items-center justify-center py-16">
        <div class="flex items-center gap-3 text-gray-400">
          <svg
            class="animate-spin h-6 w-6 text-indigo-400"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
          >
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4">
            </circle>
            <path
              class="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            >
            </path>
          </svg>
          <span class="text-sm">データを読み込み中...</span>
        </div>
      </div>

      <%!-- 一括操作バー --%>
      <div
        :if={MapSet.size(@selected_ids) > 0}
        class="mb-4 flex items-center gap-4 rounded-lg bg-indigo-900/40 border border-indigo-700/50 px-4 py-3"
      >
        <span class="text-sm text-indigo-300 font-medium">
          ✅ {MapSet.size(@selected_ids)} 件選択中
        </span>
        <button
          phx-click="delete_selected"
          class="inline-flex items-center gap-1.5 px-4 py-2 rounded-md bg-red-600 hover:bg-red-500 text-white text-sm font-medium transition-colors duration-150 shadow-sm"
        >
          🗑️ 一括削除
        </button>
        <button
          phx-click="toggle_all"
          class="text-sm text-gray-400 hover:text-gray-200 transition-colors duration-150"
        >
          選択解除
        </button>
      </div>

      <%!-- テーブル --%>
      <div class="overflow-x-auto rounded-lg border border-gray-700 shadow-lg">
        <table class="min-w-full divide-y divide-gray-700">
          <thead class="bg-gray-800">
            <tr>
              <%!-- 全選択チェックボックス --%>
              <th scope="col" class="px-4 py-3 text-center w-12">
                <input
                  type="checkbox"
                  checked={
                    MapSet.size(@selected_ids) > 0 and MapSet.size(@selected_ids) == length(@images)
                  }
                  phx-click="toggle_all"
                  class="h-4 w-4 rounded border-gray-500 bg-gray-700 text-indigo-500 focus:ring-indigo-500 focus:ring-offset-gray-800 cursor-pointer"
                />
              </th>
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
                サムネイル
              </th>
              <th
                scope="col"
                class="px-4 py-3 text-left text-xs font-semibold text-gray-300 uppercase tracking-wider"
              >
                Owner
              </th>
              <th
                scope="col"
                class="px-4 py-3 text-left text-xs font-semibold text-gray-300 uppercase tracking-wider"
              >
                Page
              </th>
              <th
                scope="col"
                class="px-4 py-3 text-left text-xs font-semibold text-gray-300 uppercase tracking-wider"
              >
                Inserted At
              </th>
              <th
                scope="col"
                class="px-4 py-3 text-left text-xs font-semibold text-gray-300 uppercase tracking-wider"
              >
                操作
              </th>
            </tr>
          </thead>
          <tbody id="images-table-body" class="bg-gray-900 divide-y divide-gray-800">
            <%= for image <- @images do %>
              <tr
                id={"image-row-#{image.id}"}
                class={"hover:bg-gray-800/60 transition-colors duration-150 #{if MapSet.member?(@selected_ids, image.id), do: "bg-indigo-900/20 border-l-2 border-l-indigo-500", else: ""}"}
              >
                <%!-- チェックボックス --%>
                <td class="px-4 py-3 whitespace-nowrap text-center">
                  <%= if image.status == "published" do %>
                    <input
                      type="checkbox"
                      disabled
                      title="公開済みのため選択不可"
                      class="h-4 w-4 rounded border-gray-600 bg-gray-800 text-gray-600 cursor-not-allowed opacity-30"
                    />
                  <% else %>
                    <input
                      type="checkbox"
                      checked={MapSet.member?(@selected_ids, image.id)}
                      phx-click="toggle_selection"
                      phx-value-id={image.id}
                      class="h-4 w-4 rounded border-gray-500 bg-gray-700 text-indigo-500 focus:ring-indigo-500 focus:ring-offset-gray-800 cursor-pointer"
                    />
                  <% end %>
                </td>

                <%!-- ID --%>
                <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-300 font-mono">
                  {image.id}
                </td>

                <%!-- サムネイル --%>
                <td class="px-4 py-3 whitespace-nowrap">
                  <%= if thumbnail_url(image.image_path) do %>
                    <img
                      src={thumbnail_url(image.image_path)}
                      alt={"Image #{image.id}"}
                      class="h-10 w-10 rounded object-cover border border-gray-600"
                      loading="lazy"
                      onerror="this.style.display='none';this.nextElementSibling.style.display='inline-flex'"
                    />
                    <span
                      class="items-center justify-center h-10 w-10 rounded bg-gray-700 text-gray-500 text-xs"
                      style="display:none"
                    >
                      N/A
                    </span>
                  <% else %>
                    <span class="inline-flex items-center justify-center h-10 w-10 rounded bg-gray-700 text-gray-500 text-xs">
                      N/A
                    </span>
                  <% end %>
                </td>

                <%!-- Owner --%>
                <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-300">
                  <%= if image.owner do %>
                    <span class="inline-flex items-center gap-1">
                      <span class="text-xs">👤</span>
                      {image.owner.email}
                    </span>
                  <% else %>
                    <span class="text-gray-500 italic">不明</span>
                  <% end %>
                </td>

                <%!-- Page Number --%>
                <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-300">
                  P.{image.page_number}
                </td>

                <%!-- Inserted At --%>
                <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-400">
                  {Calendar.strftime(image.inserted_at, "%Y-%m-%d %H:%M")}
                </td>

                <%!-- 削除ボタン --%>
                <td class="px-4 py-3 whitespace-nowrap text-sm">
                  <%= if image.status == "published" do %>
                    <span
                      class="inline-flex items-center gap-1 px-3 py-1.5 rounded-md text-emerald-400 text-xs font-medium border border-emerald-800/50 cursor-default"
                      title="公開済みのため削除ロック"
                    >
                      🔒 公開中
                    </span>
                    <button
                      phx-click="force_delete"
                      phx-value-id={image.id}
                      data-confirm="⚠️ 公開済みの画像を強制削除します。\nギャラリーからも削除されます。よろしいですか？"
                      class="inline-flex items-center gap-1 px-3 py-1.5 rounded-md text-amber-400 hover:text-amber-300 hover:bg-amber-900/20 transition-colors duration-150 text-xs font-medium border border-amber-800/50 hover:border-amber-700 ml-2"
                    >
                      ⚠️ 強制削除
                    </button>
                  <% else %>
                    <button
                      phx-click="delete"
                      phx-value-id={image.id}
                      class="inline-flex items-center gap-1 px-3 py-1.5 rounded-md text-red-400 hover:text-red-300 hover:bg-red-900/30 transition-colors duration-150 text-xs font-medium border border-red-800/50 hover:border-red-700"
                    >
                      🗑️ 削除
                    </button>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%!-- 空の場合 --%>
      <%= if @images == [] do %>
        <div class="mt-8 text-center py-12">
          <span class="text-4xl">📭</span>
          <p class="mt-4 text-gray-400">アップロードされた画像はまだありません。</p>
        </div>
      <% end %>

      <%!-- フッターナビゲーション --%>
      <div class="mt-8 flex gap-4">
        <.link navigate={~p"/admin/review"} class="btn-secondary btn-large">
          🛡️ Review Dashboard
        </.link>
        <.link navigate={~p"/lab"} class="btn-secondary btn-large">
          ← Lab に戻る
        </.link>
      </div>
    </div>
    """
  end

  # --- プライベート関数 ---

  # サムネイル URL の生成（priv/static/ プレフィックスを除去）
  defp thumbnail_url(nil), do: nil
  defp thumbnail_url(""), do: nil

  defp thumbnail_url(image_path) do
    String.replace_leading(image_path, "priv/static/", "/")
  end
end
