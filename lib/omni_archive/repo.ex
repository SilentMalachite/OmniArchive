defmodule OmniArchive.Repo do
  use Ecto.Repo,
    otp_app: :omni_archive,
    adapter: Ecto.Adapters.Postgres
end
