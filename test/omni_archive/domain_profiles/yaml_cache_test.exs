defmodule OmniArchive.DomainProfiles.YamlCacheTest do
  use ExUnit.Case
  alias OmniArchive.DomainProfiles.YamlCache

  @fixture Path.expand("../../support/yaml_fixtures/valid_minimal.yaml", __DIR__)

  setup do
    Application.put_env(:omni_archive, :domain_profile_yaml_path, @fixture)

    on_exit(fn ->
      Application.delete_env(:omni_archive, :domain_profile_yaml_path)
    end)

    :ok
  end

  test "loads profile on init and exposes accessors" do
    start_supervised!(YamlCache)
    assert [%{field: :summary} | _] = YamlCache.metadata_fields()
    assert %{profile_key: "test_yaml"} = YamlCache.duplicate_identity()
    assert is_map(YamlCache.ui_texts())
    assert is_list(YamlCache.search_facets())
    assert is_map(YamlCache.validation_rules())
  end

  test "fails to start when path is missing" do
    Application.put_env(:omni_archive, :domain_profile_yaml_path, "/nonexistent/path.yaml")
    Process.flag(:trap_exit, true)
    assert {:error, _reason} = start_supervised(YamlCache)
  end
end
