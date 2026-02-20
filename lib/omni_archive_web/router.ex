defmodule OmniArchiveWeb.Router do
  use OmniArchiveWeb, :router

  import OmniArchiveWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OmniArchiveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ── 公開スコープ (Public) ───────────────────────────────
  scope "/", OmniArchiveWeb do
    pipe_through :browser

    get "/", PageController, :home

    live_session :public,
      on_mount: [{OmniArchiveWeb.UserAuth, :mount_current_user}] do
      live "/gallery", GalleryLive, :index
    end

    get "/download/:id", DownloadController, :show
  end

  # ── 内部スコープ (Lab) ─────────────────────────────────
  # 認証必須: 未ログイン時はログイン画面にリダイレクト
  scope "/lab", OmniArchiveWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated_lab,
      on_mount: [{OmniArchiveWeb.UserAuth, :ensure_authenticated}] do
      live "/", LabLive.Index, :index
      live "/projects/:id", LabLive.Show, :show
      live "/upload", InspectorLive.Upload, :index
      live "/browse/:pdf_source_id", InspectorLive.Browse, :browse
      live "/crop/:pdf_source_id/:page_number", InspectorLive.Crop, :crop
      live "/inspector/:pdf_source_id/page/:page_number", InspectorLive.Crop, :new
      live "/label/:image_id", InspectorLive.Label, :label
      live "/finalize/:image_id", InspectorLive.Finalize, :finalize
      live "/search", SearchLive, :index
      live "/approval", ApprovalLive, :index
      live "/pipeline/:pipeline_id", PipelineLive, :show
    end
  end

  # /admin → /admin/review へリダイレクト
  scope "/", OmniArchiveWeb do
    pipe_through [:browser, :require_authenticated_user]
    get "/admin", PageController, :redirect_admin
  end

  # Admin 名前空間（Admin ロール必須・共通タブレイアウト）
  live_session :admin,
    on_mount: [{OmniArchiveWeb.UserAuth, :ensure_admin}],
    layout: {OmniArchiveWeb.Layouts, :admin} do
    scope "/admin", OmniArchiveWeb.Admin do
      pipe_through [:browser, :require_authenticated_user]

      live "/dashboard", DashboardLive, :index
      live "/users", AdminUserLive.Index, :index
      live "/review", ReviewLive, :index
      live "/trash", AdminTrashLive.Index, :index
    end
  end

  # IIIF API エンドポイント
  scope "/iiif", OmniArchiveWeb.IIIF do
    pipe_through :api

    # Image API v3.0
    get "/image/:identifier/info.json", ImageController, :info
    get "/image/:identifier/:region/:size/:rotation/:quality", ImageController, :show

    # Presentation API v3.0 (個別画像 Manifest)
    get "/manifest/:identifier", ManifestController, :show
    # Presentation API v3.0 (PdfSource 単位 Manifest)
    get "/presentation/:source_id/manifest", PresentationController, :manifest
  end

  # ヘルスチェック用 API
  scope "/api", OmniArchiveWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:omni_archive, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: OmniArchiveWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  # 招待制モデルのため、公開登録ルートを無効化
  # scope "/", OmniArchiveWeb do
  #   pipe_through [:browser, :redirect_if_user_is_authenticated]
  #
  #   get "/users/register", UserRegistrationController, :new
  #   post "/users/register", UserRegistrationController, :create
  # end

  scope "/", OmniArchiveWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", OmniArchiveWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
