defmodule OmniArchive.DomainProfiles.YamlTest do
  use ExUnit.Case
  alias OmniArchive.DomainProfiles.{Yaml, YamlCache}

  @fixture Path.expand("../../support/yaml_fixtures/valid_minimal.yaml", __DIR__)

  setup do
    Application.put_env(:omni_archive, :domain_profile_yaml_path, @fixture)
    start_supervised!(YamlCache)

    on_exit(fn ->
      Application.delete_env(:omni_archive, :domain_profile_yaml_path)
    end)

    :ok
  end

  test "implements DomainProfile behaviour" do
    assert [_ | _] = Yaml.metadata_fields()
    assert is_map(Yaml.validation_rules())
    assert is_list(Yaml.search_facets())
    assert %{search: _, inspector_label: _} = Yaml.ui_texts()
    assert %{profile_key: "test_yaml"} = Yaml.duplicate_identity()
  end
end
