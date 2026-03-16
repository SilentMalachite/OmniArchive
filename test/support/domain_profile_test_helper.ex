defmodule OmniArchive.DomainProfileTestHelper do
  @moduledoc false

  def put_domain_profile(profile) do
    previous = Application.get_env(:omni_archive, :domain_profile)
    Application.put_env(:omni_archive, :domain_profile, profile)

    ExUnit.Callbacks.on_exit(fn ->
      restore_domain_profile(previous)
    end)

    :ok
  end

  defp restore_domain_profile(nil), do: Application.delete_env(:omni_archive, :domain_profile)

  defp restore_domain_profile(profile),
    do: Application.put_env(:omni_archive, :domain_profile, profile)
end
