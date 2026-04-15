defmodule OmniArchive.DomainProfiles.YamlLoaderTest do
  use ExUnit.Case, async: true
  alias OmniArchive.DomainProfiles.YamlLoader

  @fixtures Path.expand("../../support/yaml_fixtures", __DIR__)

  defp fixture(name), do: Path.join(@fixtures, name)

  test "loads a valid minimal profile" do
    assert {:ok, profile} = YamlLoader.load(fixture("valid_minimal.yaml"))
    assert is_list(profile.metadata_fields)
    assert Enum.any?(profile.metadata_fields, &(&1.field == :caption))
    assert Enum.any?(profile.metadata_fields, &(&1.field == :label))
    assert profile.duplicate_identity.profile_key == "test_yaml"
    assert profile.duplicate_identity.scope_field == :collection
  end
end
