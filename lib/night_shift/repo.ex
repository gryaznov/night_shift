defmodule NightShift.Repo do
  use Ecto.Repo,
    otp_app: :night_shift,
    adapter: Ecto.Adapters.Postgres
end
