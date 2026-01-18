defmodule TestProject.Repo do
  use Ecto.Repo,
    otp_app: :test_project,
    adapter: Ecto.Adapters.Postgres
end
