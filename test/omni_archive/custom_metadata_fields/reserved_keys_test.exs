defmodule OmniArchive.CustomMetadataFields.ReservedKeysTest do
  use OmniArchive.DataCase, async: false
  alias OmniArchive.CustomMetadataFields.CustomMetadataField
  alias OmniArchive.DomainProfiles.YamlCache

  @fixture Path.expand("../../support/yaml_fixtures/valid_reserved_keys.yaml", __DIR__)

  describe "with built-in profile active" do
    test "rejects keys that are statically reserved (e.g. caption)" do
      attrs = %{field_key: "caption", label: "x", profile_key: "whatever"}
      changeset = CustomMetadataField.changeset(%CustomMetadataField{}, attrs)
      refute changeset.valid?
      assert {"予約済みのフィールドキーです", _} = changeset.errors[:field_key]
    end
  end

  describe "with YAML profile active" do
    setup do
      prev = Application.get_env(:omni_archive, :domain_profile)
      Application.put_env(:omni_archive, :domain_profile_yaml_path, @fixture)
      Application.put_env(:omni_archive, :domain_profile, OmniArchive.DomainProfiles.Yaml)
      start_supervised!(YamlCache)

      on_exit(fn ->
        Application.delete_env(:omni_archive, :domain_profile_yaml_path)

        if prev,
          do: Application.put_env(:omni_archive, :domain_profile, prev),
          else: Application.delete_env(:omni_archive, :domain_profile)
      end)

      :ok
    end

    test "rejects field_key that matches a YAML-defined metadata field" do
      # `survey_id` is defined in valid_reserved_keys.yaml and is NOT in the
      # static @reserved_keys list, so this test exercises the dynamic check.
      attrs = %{field_key: "survey_id", label: "x", profile_key: "whatever"}
      changeset = CustomMetadataField.changeset(%CustomMetadataField{}, attrs)
      refute changeset.valid?
      assert {"予約済みのフィールドキーです", _} = changeset.errors[:field_key]
    end
  end
end
