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

  @error_cases [
    {"bad_invalid_field_key.yaml", ~r/invalid field key/},
    {"bad_duplicate_fields.yaml", ~r/duplicate/},
    {"bad_missing_caption.yaml", ~r/caption|missing/},
    {"bad_missing_label.yaml", ~r/label|missing/},
    {"bad_caption_metadata_storage.yaml", ~r/storage: core/},
    {"bad_core_on_other_field.yaml", ~r/storage: core/}
  ]

  for {name, pattern} <- @error_cases do
    test "rejects #{name}" do
      assert {:error, reason} = YamlLoader.load(fixture(unquote(name)))
      assert reason =~ unquote(Macro.escape(pattern))
    end
  end
end
