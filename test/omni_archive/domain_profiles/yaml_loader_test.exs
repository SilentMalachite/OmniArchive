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

  test "validation_rules: compiles format into Regex" do
    {:ok, profile} = YamlLoader.load(fixture("valid_with_validation.yaml"))
    assert %Regex{} = profile.validation_rules[:label][:format]
  end

  test "validation_rules: rejects invalid regex" do
    assert {:error, reason} = YamlLoader.load(fixture("bad_validation_regex.yaml"))
    assert reason =~ "format"
  end

  test "validation_rules: rejects unknown field" do
    assert {:error, reason} = YamlLoader.load(fixture("bad_validation_unknown_field.yaml"))
    assert reason =~ "unknown"
  end

  test "validation_rules: required_terms is parsed as list" do
    {:ok, profile} = YamlLoader.load(fixture("valid_with_validation.yaml"))
    assert is_list(profile.validation_rules[:collection][:required_terms])
  end

  test "search_facets: references defined fields" do
    {:ok, profile} = YamlLoader.load(fixture("valid_minimal.yaml"))
    assert [%{field: :collection, param: "collection"}] = profile.search_facets
  end

  test "search_facets: rejects unknown field reference" do
    assert {:error, reason} = YamlLoader.load(fixture("bad_facet_unknown_field.yaml"))
    assert reason =~ "unknown"
  end

  test "ui_texts: returns nested atom-keyed map" do
    {:ok, profile} = YamlLoader.load(fixture("valid_minimal.yaml"))
    assert %{search: %{page_title: _}, inspector_label: %{heading: _}} = profile.ui_texts
  end

  test "ui_texts: rejects missing required keys" do
    assert {:error, reason} = YamlLoader.load(fixture("bad_ui_texts_missing.yaml"))
    assert reason =~ "ui_texts"
  end

  test "duplicate_identity: scope_field must reference defined field" do
    assert {:error, reason} = YamlLoader.load(fixture("bad_duplicate_unknown_scope.yaml"))
    assert reason =~ "scope_field"
  end

  test "loads priv/profiles/example_profile.yaml" do
    path = Application.app_dir(:omni_archive, "priv/profiles/example_profile.yaml")
    assert {:ok, profile} = YamlLoader.load(path)
    assert Enum.any?(profile.metadata_fields, &(&1.field == :caption))
    assert %Regex{} = profile.validation_rules[:label][:format]
  end
end
