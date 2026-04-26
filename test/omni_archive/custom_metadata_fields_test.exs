defmodule OmniArchive.CustomMetadataFieldsTest do
  use OmniArchive.DataCase, async: true

  alias OmniArchive.CustomMetadataFields
  alias OmniArchive.CustomMetadataFields.CustomMetadataField

  test "profile conversion rejects invalid field keys before profile exposure" do
    field = %CustomMetadataField{
      field_key: "Invalid-Key",
      label: "Invalid",
      placeholder: "",
      validation_rules: %{}
    }

    assert_raise ArgumentError, ~r/invalid metadata field key/, fn ->
      CustomMetadataFields.to_profile_format(field)
    end
  end

  test "profile conversion accepts validated runtime field keys" do
    field = %CustomMetadataField{
      field_key: "runtime_field",
      label: "Runtime field",
      placeholder: "",
      validation_rules: %{"max_length" => 20}
    }

    assert %{field: "runtime_field", storage: :metadata} =
             CustomMetadataFields.to_profile_format(field)

    assert {"runtime_field", %{max_length: 20}} =
             CustomMetadataFields.to_validation_rule(field)

    assert %{field: "runtime_field", param: "runtime_field"} =
             CustomMetadataFields.to_search_facet(field)
  end
end
