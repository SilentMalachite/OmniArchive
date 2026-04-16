defmodule OmniArchiveWeb.Admin.CustomFieldsLive do
  @moduledoc """
  カスタムメタデータフィールドの管理画面。
  管理者がランタイムでメタデータフィールドを追加・編集・並び替え・無効化できます。
  """
  use OmniArchiveWeb, :live_view

  alias OmniArchive.CustomMetadataFields
  alias OmniArchive.CustomMetadataFields.CustomMetadataField
  alias OmniArchive.DomainProfiles

  @impl true
  def mount(_params, _session, socket) do
    profile_key = DomainProfiles.profile_key()
    fields = CustomMetadataFields.list_all_fields(profile_key)

    {:ok,
     socket
     |> assign(:page_title, "カスタムフィールド管理")
     |> assign(:profile_key, profile_key)
     |> assign(:fields, fields)
     |> assign(:show_form, false)
     |> assign(:editing_field, nil)
     |> assign(:changeset, new_changeset(profile_key))}
  end

  @impl true
  def handle_event("show_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_field, nil)
     |> assign(:changeset, new_changeset(socket.assigns.profile_key))}
  end

  @impl true
  def handle_event("cancel_form", _params, socket) do
    {:noreply, assign(socket, show_form: false, editing_field: nil)}
  end

  @impl true
  def handle_event("edit_field", %{"id" => id}, socket) do
    field = CustomMetadataFields.get_field!(id)

    changeset =
      CustomMetadataField.changeset(field, %{})

    {:noreply,
     socket
     |> assign(:show_form, true)
     |> assign(:editing_field, field)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"custom_metadata_field" => params}, socket) do
    target =
      socket.assigns.editing_field ||
        %CustomMetadataField{profile_key: socket.assigns.profile_key}

    changeset =
      target
      |> CustomMetadataField.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"custom_metadata_field" => params}, socket) do
    params = Map.put(params, "profile_key", socket.assigns.profile_key)
    params = normalize_validation_rules(params)

    result =
      case socket.assigns.editing_field do
        nil -> CustomMetadataFields.create_field(params)
        field -> CustomMetadataFields.update_field(field, params)
      end

    case result do
      {:ok, _field} ->
        fields = CustomMetadataFields.list_all_fields(socket.assigns.profile_key)
        action = if socket.assigns.editing_field, do: "更新", else: "追加"

        {:noreply,
         socket
         |> assign(:fields, fields)
         |> assign(:show_form, false)
         |> assign(:editing_field, nil)
         |> put_flash(:info, "フィールドを#{action}しました")}

      {:error, :max_fields_reached} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "フィールド数が上限（#{CustomMetadataField.max_fields_per_profile()}）に達しています"
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    field = CustomMetadataFields.get_field!(id)

    result =
      if field.active,
        do: CustomMetadataFields.deactivate_field(field),
        else: CustomMetadataFields.activate_field(field)

    case result do
      {:ok, _} ->
        fields = CustomMetadataFields.list_all_fields(socket.assigns.profile_key)
        {:noreply, assign(socket, :fields, fields)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "更新に失敗しました")}
    end
  end

  @impl true
  def handle_event("move_up", %{"id" => id}, socket) do
    field = CustomMetadataFields.get_field!(id)
    CustomMetadataFields.move_field_up(field)
    fields = CustomMetadataFields.list_all_fields(socket.assigns.profile_key)
    {:noreply, assign(socket, :fields, fields)}
  end

  @impl true
  def handle_event("move_down", %{"id" => id}, socket) do
    field = CustomMetadataFields.get_field!(id)
    CustomMetadataFields.move_field_down(field)
    fields = CustomMetadataFields.list_all_fields(socket.assigns.profile_key)
    {:noreply, assign(socket, :fields, fields)}
  end

  @impl true
  def handle_event("delete_field", %{"id" => id}, socket) do
    field = CustomMetadataFields.get_field!(id)

    case CustomMetadataFields.delete_field(field) do
      {:ok, _} ->
        fields = CustomMetadataFields.list_all_fields(socket.assigns.profile_key)

        {:noreply,
         socket
         |> assign(:fields, fields)
         |> put_flash(:info, "フィールドを削除しました")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "削除に失敗しました")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-[#e8d5a3]">🏷️ カスタムフィールド管理</h1>
          <p class="text-gray-400 text-sm mt-1">
            プロファイル: <span class="text-[#d4a844]">{@profile_key}</span> ・ランタイムで追加したメタデータフィールドを管理します
          </p>
        </div>
        <button
          :if={!@show_form}
          phx-click="show_form"
          class="px-4 py-2 bg-[#d4a844] text-[#12121f] font-medium rounded-lg hover:bg-[#e8d5a3] transition-colors"
        >
          + フィールド追加
        </button>
      </div>

      <%!-- 追加/編集フォーム --%>
      <%= if @show_form do %>
        <div class="bg-[#1a1a2e] border border-gray-700/50 rounded-lg p-6 mb-6">
          <h2 class="text-lg font-medium text-[#e8d5a3] mb-4">
            {if @editing_field, do: "フィールドを編集", else: "新しいフィールドを追加"}
          </h2>
          <.form
            for={@changeset}
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">フィールドキー</label>
                <input
                  type="text"
                  name="custom_metadata_field[field_key]"
                  value={Ecto.Changeset.get_field(@changeset, :field_key)}
                  placeholder="例: donor_name"
                  class={[
                    "w-full px-3 py-2 bg-[#12121f] border rounded-lg text-gray-200 focus:outline-none focus:border-[#d4a844]",
                    if(@changeset.action && @changeset.errors[:field_key],
                      do: "border-red-500",
                      else: "border-gray-600"
                    )
                  ]}
                  {if @editing_field, do: [disabled: true], else: []}
                />
                <%= if @changeset.action && @changeset.errors[:field_key] do %>
                  <p class="text-red-400 text-xs mt-1">
                    {elem(hd(@changeset.errors[:field_key] || [{"", []}]), 0)}
                  </p>
                <% end %>
                <p class="text-gray-500 text-xs mt-1">半角小文字・数字・アンダースコア（例: donor_name）</p>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">表示ラベル</label>
                <input
                  type="text"
                  name="custom_metadata_field[label]"
                  value={Ecto.Changeset.get_field(@changeset, :label)}
                  placeholder="例: 🎁 寄贈者名"
                  class="w-full px-3 py-2 bg-[#12121f] border border-gray-600 rounded-lg text-gray-200 focus:outline-none focus:border-[#d4a844]"
                />
                <%= if @changeset.action && @changeset.errors[:label] do %>
                  <p class="text-red-400 text-xs mt-1">
                    {elem(hd(@changeset.errors[:label] || [{"", []}]), 0)}
                  </p>
                <% end %>
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">プレースホルダー</label>
              <input
                type="text"
                name="custom_metadata_field[placeholder]"
                value={Ecto.Changeset.get_field(@changeset, :placeholder)}
                placeholder="例: 寄贈者の氏名を入力"
                class="w-full px-3 py-2 bg-[#12121f] border border-gray-600 rounded-lg text-gray-200 focus:outline-none focus:border-[#d4a844]"
              />
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">最大文字数（空欄=制限なし）</label>
                <input
                  type="number"
                  name="custom_metadata_field[max_length]"
                  value={get_max_length(@changeset)}
                  min="1"
                  max="10000"
                  placeholder="例: 100"
                  class="w-full px-3 py-2 bg-[#12121f] border border-gray-600 rounded-lg text-gray-200 focus:outline-none focus:border-[#d4a844]"
                />
              </div>

              <div class="flex items-end">
                <label class="flex items-center space-x-2 cursor-pointer">
                  <input
                    type="hidden"
                    name="custom_metadata_field[searchable]"
                    value="false"
                  />
                  <input
                    type="checkbox"
                    name="custom_metadata_field[searchable]"
                    value="true"
                    checked={Ecto.Changeset.get_field(@changeset, :searchable)}
                    class="w-4 h-4 rounded border-gray-600 text-[#d4a844] focus:ring-[#d4a844] bg-[#12121f]"
                  />
                  <span class="text-sm text-gray-300">検索フィルターに表示する</span>
                </label>
              </div>
            </div>

            <div class="flex justify-end space-x-3 pt-2">
              <button
                type="button"
                phx-click="cancel_form"
                class="px-4 py-2 text-gray-400 hover:text-gray-200 transition-colors"
              >
                キャンセル
              </button>
              <button
                type="submit"
                class="px-4 py-2 bg-[#d4a844] text-[#12121f] font-medium rounded-lg hover:bg-[#e8d5a3] transition-colors"
              >
                {if @editing_field, do: "更新", else: "追加"}
              </button>
            </div>
          </.form>
        </div>
      <% end %>

      <%!-- コンパイル時フィールド一覧（参考表示） --%>
      <div class="mb-6">
        <h2 class="text-sm font-medium text-gray-400 mb-2 uppercase tracking-wider">
          固定フィールド（プロファイル定義）
        </h2>
        <div class="bg-[#1a1a2e]/50 border border-gray-700/30 rounded-lg divide-y divide-gray-700/30">
          <%= for field <- compile_time_fields() do %>
            <div class="px-4 py-3 flex items-center justify-between">
              <div>
                <span class="text-gray-300 text-sm font-medium">{field.label}</span>
                <span class="text-gray-500 text-xs ml-2">({field.field})</span>
              </div>
              <span class="text-gray-500 text-xs">固定</span>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- カスタムフィールド一覧 --%>
      <div>
        <h2 class="text-sm font-medium text-gray-400 mb-2 uppercase tracking-wider">カスタムフィールド</h2>
        <%= if @fields == [] do %>
          <div class="bg-[#1a1a2e]/50 border border-gray-700/30 rounded-lg p-8 text-center">
            <p class="text-gray-400">カスタムフィールドはまだ追加されていません。</p>
            <p class="text-gray-500 text-sm mt-1">「+ フィールド追加」ボタンから追加できます。</p>
          </div>
        <% else %>
          <div class="bg-[#1a1a2e] border border-gray-700/50 rounded-lg divide-y divide-gray-700/50">
            <%= for {field, idx} <- Enum.with_index(@fields) do %>
              <div class={[
                "px-4 py-3 flex items-center justify-between",
                !field.active && "opacity-50"
              ]}>
                <div class="flex-1">
                  <span class="text-gray-200 text-sm font-medium">{field.label}</span>
                  <span class="text-gray-500 text-xs ml-2">({field.field_key})</span>
                  <%= if field.searchable do %>
                    <span class="ml-2 text-xs px-1.5 py-0.5 bg-[#d4a844]/20 text-[#d4a844] rounded">
                      検索可
                    </span>
                  <% end %>
                  <%= if !field.active do %>
                    <span class="ml-2 text-xs px-1.5 py-0.5 bg-red-500/20 text-red-400 rounded">
                      無効
                    </span>
                  <% end %>
                  <%= if max_len = get_in(field.validation_rules, ["max_length"]) do %>
                    <span class="ml-2 text-gray-500 text-xs">最大{max_len}文字</span>
                  <% end %>
                </div>

                <div class="flex items-center space-x-1">
                  <button
                    :if={idx > 0}
                    phx-click="move_up"
                    phx-value-id={field.id}
                    class="p-1 text-gray-400 hover:text-gray-200"
                    title="上に移動"
                  >
                    ▲
                  </button>
                  <button
                    :if={idx < length(@fields) - 1}
                    phx-click="move_down"
                    phx-value-id={field.id}
                    class="p-1 text-gray-400 hover:text-gray-200"
                    title="下に移動"
                  >
                    ▼
                  </button>
                  <button
                    phx-click="edit_field"
                    phx-value-id={field.id}
                    class="p-1 text-gray-400 hover:text-[#d4a844]"
                    title="編集"
                  >
                    ✏️
                  </button>
                  <button
                    phx-click="toggle_active"
                    phx-value-id={field.id}
                    class={[
                      "p-1",
                      if(field.active,
                        do: "text-green-400 hover:text-red-400",
                        else: "text-red-400 hover:text-green-400"
                      )
                    ]}
                    title={if field.active, do: "無効にする", else: "有効にする"}
                  >
                    {if field.active, do: "🟢", else: "🔴"}
                  </button>
                  <button
                    phx-click="delete_field"
                    phx-value-id={field.id}
                    data-confirm="このフィールドを削除しますか？既存データは保持されますが、UIから非表示になります。"
                    class="p-1 text-gray-400 hover:text-red-400"
                    title="削除"
                  >
                    🗑️
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- Private ---

  defp new_changeset(profile_key) do
    CustomMetadataField.changeset(
      %CustomMetadataField{profile_key: profile_key},
      %{}
    )
  end

  defp compile_time_fields do
    DomainProfiles.current().metadata_fields()
  end

  defp get_max_length(changeset) do
    rules = Ecto.Changeset.get_field(changeset, :validation_rules) || %{}
    rules["max_length"] || Map.get(rules, :max_length)
  end

  defp normalize_validation_rules(params) do
    case params["max_length"] do
      nil ->
        params

      "" ->
        Map.put(params, "validation_rules", %{})

      value ->
        case Integer.parse(value) do
          {max, _} when max > 0 ->
            Map.put(params, "validation_rules", %{"max_length" => max})

          _ ->
            Map.put(params, "validation_rules", %{})
        end
    end
  end
end
