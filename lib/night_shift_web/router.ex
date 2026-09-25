defmodule NightShiftWeb.Router do
  use NightShiftWeb, :router

  import NightShiftWeb.UserAuth

  # `frame-src` admits the live_reload iframe in dev only. `style-src` needs
  # `'unsafe-inline'` because Phoenix.LiveView.JS.show/hide sets inline display.
  @frame_src if Application.compile_env(:night_shift, :dev_routes),
               do: "'self'",
               else: "'none'"

  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "script-src 'self'",
                               "style-src 'self' 'unsafe-inline'",
                               "img-src 'self' data:",
                               "font-src 'self' data:",
                               "connect-src 'self'",
                               "frame-src #{@frame_src}",
                               "frame-ancestors 'none'",
                               "base-uri 'self'",
                               "form-action 'self'",
                               "object-src 'none'"
                             ],
                             "; "
                           )

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NightShiftWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers,
         %{"content-security-policy" => @content_security_policy}

    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", NightShiftWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", NightShiftWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:night_shift, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: NightShiftWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", NightShiftWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    # No registration, password reset or email confirmation: `## Out of scope` of
    # plan 0001 puts sign-up and password reset outside the product, and members
    # come from seeds.
    live_session :redirect_if_user_is_authenticated,
      on_mount: [{NightShiftWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/log_in", UserLoginLive, :new
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", NightShiftWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{NightShiftWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
      live "/no-access", NoAccessLive, :show
    end

    # No route carries a tenant. The tenant and the acting member come from the
    # session, through `TenantAuth`, and nowhere else.
    live_session :require_active_member,
      on_mount: [
        {NightShiftWeb.UserAuth, :ensure_authenticated},
        {NightShiftWeb.TenantAuth, :require_active_member}
      ] do
      live "/workspace", WorkspaceLive, :show

      live "/chat", ChatLive, :index
      live "/chat/:id", GroupLive, :show

      # Reserved by 0001, built by 0003.
      live "/announcements", AnnouncementsLive, :index
    end
  end

  scope "/", NightShiftWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete
  end
end
