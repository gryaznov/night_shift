import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.

worktree_suffix =
  case System.cmd("git", ["rev-parse", "--absolute-git-dir"], stderr_to_stdout: true) do
    {dir, 0} ->
      dir = String.trim(dir)

      if Path.basename(Path.dirname(dir)) == "worktrees",
        do: "_" <> String.replace(Path.basename(dir), ~r/\D/, ""),
        else: ""

    _ ->
      ""
  end

config :night_shift, NightShift.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "night_shift_test#{worktree_suffix}#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :night_shift, NightShiftWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "FOz+sBKj4rYu9U5t+cdWrZPwnjWyq7c8hT94+ZTSSuztgIHC+gVzZKbrHBjABZR8",
  server: false

# In test we don't send emails
config :night_shift, NightShift.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
