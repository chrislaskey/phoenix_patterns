import Config
import Dotenvy

source!([".env", System.get_env()])

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/app start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if config_env() != :test do
  if env!("PHX_SERVER", :boolean, false) do
    config :app, App.Web.Endpoint, server: true
  end

  config :app, App.Web.Endpoint, http: [port: env!("PORT", :integer, 4000)]

  config :app, api_socket: env!("API_SOCKET", :boolean, false)
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :app, App.Web.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/app/router\.ex$"E,
        ~r"lib/app/web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  config :app, App.Repo,
    database: env!("DATABASE_PATH", :string!),
    pool_size: env!("POOL_SIZE", :integer, 5)

  config :app, :dns_cluster_query, env!("DNS_CLUSTER_QUERY", :string?, nil)

  # Generate SECRET_KEY_BASE with `mix phx.gen.secret`
  config :app, App.Web.Endpoint,
    url: [host: env!("PHX_HOST", :string!, "example.com"), port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: env!("SECRET_KEY_BASE", :string!)

  # Burrito sets __BURRITO=1 when the app runs from a standalone binary
  # (`mix release app_standalone`). The binary is meant to be started by a
  # desktop app on the same machine, so it always serves, listens on the
  # loopback interface only, and builds plain http URLs for its own port.
  if env!("__BURRITO", :boolean, false) do
    config :app, App.Web.Endpoint,
      server: true,
      url: [
        host: env!("PHX_HOST", :string!, "localhost"),
        port: env!("PORT", :integer, 4000),
        scheme: "http"
      ],
      http: [ip: {127, 0, 0, 1}]

    config :app, :exit_on_stdin_close, env!("EXIT_ON_STDIN_CLOSE", :boolean, false)
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :app, App.Web.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: env!("SOME_APP_SSL_KEY_PATH", :string!),
  #         certfile: env!("SOME_APP_SSL_CERT_PATH", :string!)
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :app, App.Web.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :app, App.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: env!("MAILGUN_API_KEY", :string!),
  #       domain: env!("MAILGUN_DOMAIN", :string!)
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
