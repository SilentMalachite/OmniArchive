defmodule OmniArchive.CustomMetadataFields.CustomMetadataField do
  @moduledoc """
  ランタイムで追加可能なカスタムメタデータフィールドの定義。
  """
  use Ecto.Schema
  import Ecto.Changeset

  @field_key_format ~r/^[a-z][a-z0-9_]{0,49}$/
  @max_fields_per_profile 20

  # コンパイル時プロファイルで使用済みのフィールドキー（重複防止）
  @reserved_keys ~w(caption label site period artifact_type collection item_type date_note)

  schema "custom_metadata_fields" do
    field :field_key, :string
    field :label, :string
    field :placeholder, :string, default: ""
    field :sort_order, :integer, default: 0
    field :searchable, :boolean, default: false
    field :validation_rules, :map, default: %{}
    field :active, :boolean, default: true
    field :profile_key, :string

    timestamps()
  end

  def changeset(field, attrs) do
    field
    |> cast(attrs, [
      :field_key,
      :label,
      :placeholder,
      :sort_order,
      :searchable,
      :validation_rules,
      :active,
      :profile_key
    ])
    |> validate_required([:field_key, :label, :profile_key])
    |> validate_format(:field_key, @field_key_format, message: "半角小文字・数字・アンダースコアのみ（先頭は小文字）")
    |> validate_not_reserved()
    |> validate_length(:label, max: 100)
    |> validate_length(:placeholder, max: 200)
    |> validate_validation_rules()
    |> unique_constraint([:profile_key, :field_key],
      message: "このプロファイルでそのフィールドキーは既に使用されています"
    )
  end

  def max_fields_per_profile, do: @max_fields_per_profile

  defp validate_not_reserved(changeset) do
    case get_change(changeset, :field_key) do
      nil ->
        changeset

      key ->
        if key in reserved_keys() do
          add_error(changeset, :field_key, "予約済みのフィールドキーです")
        else
          changeset
        end
    end
  end

  defp reserved_keys do
    Enum.uniq(@reserved_keys ++ active_profile_keys())
  end

  defp active_profile_keys do
    profile =
      Application.get_env(
        :omni_archive,
        :domain_profile,
        OmniArchive.DomainProfiles.Archaeology
      )

    try do
      profile.metadata_fields()
      |> Enum.map(& &1.field)
      |> Enum.map(&Atom.to_string/1)
    rescue
      _ -> []
    end
  end

  defp validate_validation_rules(changeset) do
    case get_change(changeset, :validation_rules) do
      nil ->
        changeset

      rules when is_map(rules) ->
        if valid_rules?(rules),
          do: changeset,
          else: add_error(changeset, :validation_rules, "不正なバリデーションルールです")

      _ ->
        add_error(changeset, :validation_rules, "マップ形式で入力してください")
    end
  end

  defp valid_rules?(rules) do
    allowed_keys = MapSet.new(["max_length", "max_length_error"])
    rule_keys = rules |> Map.keys() |> MapSet.new()
    MapSet.subset?(rule_keys, allowed_keys) and valid_max_length?(rules)
  end

  defp valid_max_length?(%{"max_length" => max}) when is_integer(max) and max > 0, do: true
  defp valid_max_length?(%{"max_length" => _}), do: false
  defp valid_max_length?(_), do: true
end
