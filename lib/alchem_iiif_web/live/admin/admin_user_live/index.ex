defmodule AlchemIiifWeb.Admin.AdminUserLive.Index do
  @moduledoc """
  ユーザー管理 LiveView。
  全ユーザーの一覧表示・削除・新規作成を行う管理画面です。

  ## アクセス制御
  - `on_mount(:ensure_admin)` により Admin ロール以外はリダイレクトされます。
  """
  use AlchemIiifWeb, :live_view

  alias AlchemIiif.Accounts
  alias AlchemIiif.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    users = Accounts.list_users()
    changeset = Accounts.change_user_registration(%User{})

    {:ok,
     socket
     |> assign(:page_title, "ユーザー管理")
     |> assign(:users, users)
     |> assign(:show_modal, false)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("open_modal", _params, socket) do
    {:noreply, assign(socket, :show_modal, true)}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    changeset = Accounts.change_user_registration(%User{})

    {:noreply,
     socket
     |> assign(:show_modal, false)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.admin_register_user(user_params) do
      {:ok, user} ->
        users = Accounts.list_users()
        changeset = Accounts.change_user_registration(%User{})

        {:noreply,
         socket
         |> put_flash(:info, "ユーザー #{user.email} を作成しました。")
         |> assign(:users, users)
         |> assign(:show_modal, false)
         |> assign(:form, to_form(changeset))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    current_user = socket.assigns.current_user
    user = Accounts.get_user!(id)

    # 自分自身の削除を防止
    if user.id == current_user.id do
      {:noreply, put_flash(socket, :error, "自分自身を削除することはできません。")}
    else
      case Accounts.delete_user(user) do
        {:ok, _} ->
          users = Accounts.list_users()

          {:noreply,
           socket
           |> put_flash(:info, "ユーザー #{user.email} を削除しました。")
           |> assign(:users, users)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "ユーザーの削除に失敗しました。")}
      end
    end
  end
end
