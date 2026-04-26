defmodule OmniArchive.CustomMetadataFields do
  @moduledoc """
  カスタムメタデータフィールドの CRUD とプロファイル形式への変換。
  """

  import Ecto.Query
  alias OmniArchive.CustomMetadataFields.Cache
  alias OmniArchive.CustomMetadataFields.CustomMetadataField
  alias OmniArchive.Repo

  @field_key_format ~r/^[a-z][a-z0-9_]{0,49}$/

  # --- CRUD ---

  def list_active_fields(profile_key) do
    CustomMetadataField
    |> where([f], f.profile_key == ^profile_key and f.active == true)
    |> order_by([f], asc: f.sort_order, asc: f.id)
    |> Repo.all()
  end

  def list_all_fields(profile_key) do
    CustomMetadataField
    |> where([f], f.profile_key == ^profile_key)
    |> order_by([f], asc: f.sort_order, asc: f.id)
    |> Repo.all()
  end

  def get_field!(id), do: Repo.get!(CustomMetadataField, id)

  def get_field(id) do
    with {:ok, id} <- normalize_id(id) do
      Repo.get(CustomMetadataField, id)
    else
      :error -> nil
    end
  end

  def create_field(attrs) do
    count =
      CustomMetadataField
      |> where(
        [f],
        f.profile_key == ^(attrs[:profile_key] || attrs["profile_key"]) and f.active == true
      )
      |> Repo.aggregate(:count)

    if count >= CustomMetadataField.max_fields_per_profile() do
      {:error, :max_fields_reached}
    else
      result =
        %CustomMetadataField{}
        |> CustomMetadataField.changeset(attrs)
        |> Repo.insert()

      with {:ok, _} <- result, do: Cache.invalidate()
      result
    end
  end

  def update_field(%CustomMetadataField{} = field, attrs) do
    result =
      field
      |> CustomMetadataField.changeset(attrs)
      |> Repo.update()

    with {:ok, _} <- result, do: Cache.invalidate()
    result
  end

  def deactivate_field(%CustomMetadataField{} = field) do
    update_field(field, %{active: false})
  end

  def activate_field(%CustomMetadataField{} = field) do
    update_field(field, %{active: true})
  end

  def delete_field(%CustomMetadataField{} = field) do
    result = Repo.delete(field)
    with {:ok, _} <- result, do: Cache.invalidate()
    result
  end

  def move_field_up(%CustomMetadataField{} = field) do
    fields = list_all_fields(field.profile_key)
    reorder_fields(fields, field.id, :up)
  end

  def move_field_down(%CustomMetadataField{} = field) do
    fields = list_all_fields(field.profile_key)
    reorder_fields(fields, field.id, :down)
  end

  defp reorder_fields(fields, target_id, direction) do
    idx = Enum.find_index(fields, &(&1.id == target_id))

    swap_idx =
      case direction do
        :up -> if idx && idx > 0, do: idx - 1
        :down -> if idx && idx < length(fields) - 1, do: idx + 1
      end

    if swap_idx do
      fields
      |> List.update_at(idx, fn f -> %{f | sort_order: swap_idx} end)
      |> List.update_at(swap_idx, fn f -> %{f | sort_order: idx} end)
      |> Enum.each(fn f ->
        Repo.update_all(
          from(c in CustomMetadataField, where: c.id == ^f.id),
          set: [sort_order: f.sort_order]
        )
      end)

      Cache.invalidate()
      :ok
    else
      :noop
    end
  end

  # --- プロファイル形式への変換 ---

  def to_profile_format(%CustomMetadataField{} = f) do
    field_key = field_key!(f)

    %{
      field: field_key,
      label: f.label,
      placeholder: f.placeholder || "",
      storage: :metadata
    }
  end

  def to_validation_rule(%CustomMetadataField{} = f) do
    rules = f.validation_rules || %{}
    field_key = field_key!(f)

    rule =
      case rules do
        %{"max_length" => max} when is_integer(max) ->
          %{
            max_length: max,
            max_length_error: Map.get(rules, "max_length_error", "#{max}文字以内で入力してください")
          }

        _ ->
          %{}
      end

    {field_key, rule}
  end

  def to_search_facet(%CustomMetadataField{} = f) do
    field_key = field_key!(f)

    %{
      field: field_key,
      param: field_key,
      label: f.label
    }
  end

  defp field_key!(%CustomMetadataField{field_key: key}) when is_binary(key) do
    if Regex.match?(@field_key_format, key) do
      key
    else
      raise ArgumentError, "invalid metadata field key: #{inspect(key)}"
    end
  end

  defp field_key!(%CustomMetadataField{field_key: key}) do
    raise ArgumentError, "invalid metadata field key: #{inspect(key)}"
  end

  defp normalize_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp normalize_id(_id), do: :error
end
