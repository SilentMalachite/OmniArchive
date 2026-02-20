defmodule AlchemIiif.Repo do
  use Ecto.Repo,
    otp_app: :alchem_iiif,
    adapter: Ecto.Adapters.Postgres
end
