import Config

db_username =
  System.get_env("DB_USERNAME") ||
    System.get_env("PGUSER") ||
    System.get_env("USER") ||
    "postgres"

db_password =
  System.get_env("DB_PASSWORD") ||
    System.get_env("PGPASSWORD") ||
    ""

db_hostname =
  System.get_env("DB_HOST") ||
    System.get_env("PGHOST") ||
    "localhost"

db_port =
  System.get_env("DB_PORT") ||
    System.get_env("PGPORT") ||
    "5432"

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :omni_archive, OmniArchive.Repo,
  username: db_username,
  password: db_password,
  hostname: db_hostname,
  port: String.to_integer(db_port),
  database:
    System.get_env("DB_TEST_DATABASE") ||
      System.get_env("DB_DATABASE") ||
      "omni_archive_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :omni_archive, OmniArchiveWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "2WWtXaMW7SdAfmdVYfeGiJsKw/od530WD2As0wngLIK++GxYbcSb+8kKFQdFKODJ",
  server: false

# In test we don't send emails
config :omni_archive, OmniArchive.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# PTIFF 生成をモックに差し替え（テスト時はファイル I/O を回避）
config :omni_archive, :ptiff_generator, OmniArchive.Iiif.PtiffGeneratorMock
