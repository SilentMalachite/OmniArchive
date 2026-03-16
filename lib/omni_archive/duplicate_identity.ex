defmodule OmniArchive.DuplicateIdentity do
  @moduledoc """
  active profile に基づく重複判定用 fingerprint を生成します。
  """

  import Ecto.Changeset
  import Ecto.Query

  alias OmniArchive.DomainProfiles
  alias OmniArchive.Ingestion.ExtractedImage
  alias OmniArchive.Ingestion.ExtractedImageMetadata
  alias OmniArchive.Repo

  @fingerprint_version "v1"

  def put_dedupe_fingerprint(changeset) do
    put_change(changeset, :dedupe_fingerprint, fingerprint_for_changeset(changeset))
  end

  def fingerprint_for_image(%ExtractedImage{} = image) do
    config = DomainProfiles.duplicate_identity()

    fingerprint_from_values(
      config.profile_key,
      ExtractedImageMetadata.read(image, config.scope_field),
      image.label
    )
  end

  def fingerprint_for_record(%ExtractedImage{} = image, attrs \\ %{}) when is_map(attrs) do
    config = DomainProfiles.duplicate_identity()
    normalized_attrs = ExtractedImageMetadata.normalize_attrs(image, attrs)
    metadata = normalized_metadata(normalized_attrs, image)

    fingerprint_from_values(
      config.profile_key,
      scope_value(config.scope_field, image, normalized_attrs, metadata),
      attribute_value(normalized_attrs, config.label_field || :label, image.label)
    )
  end

  def fingerprint_for_changeset(changeset) do
    config = DomainProfiles.duplicate_identity()
    metadata = get_field(changeset, :metadata) || %{}

    fingerprint_from_values(
      config.profile_key,
      changeset_scope_value(changeset, config.scope_field, metadata),
      get_field(changeset, config.label_field || :label)
    )
  end

  def fingerprint_from_values(profile_key, scope_value, label) do
    with {:ok, normalized_profile} <- normalize_component(profile_key),
         {:ok, normalized_scope} <- normalize_component(scope_value),
         {:ok, normalized_label} <- normalize_component(label) do
      Enum.join(
        [@fingerprint_version, normalized_profile, normalized_scope, normalized_label],
        "|"
      )
    else
      :error -> nil
    end
  end

  def backfill_missing_fingerprints(batch_size \\ 500)
      when is_integer(batch_size) and batch_size > 0 do
    Stream.unfold(nil, fn last_id ->
      batch = next_batch(last_id, batch_size)

      case batch do
        [] -> nil
        images -> {images, List.last(images).id}
      end
    end)
    |> Enum.reduce(0, fn images, total ->
      total +
        Enum.reduce(images, 0, fn image, count ->
          case fingerprint_for_image(image) do
            nil ->
              count

            fingerprint ->
              {updated, _} =
                Repo.update_all(
                  from(e in ExtractedImage, where: e.id == ^image.id),
                  set: [dedupe_fingerprint: fingerprint]
                )

              count + updated
          end
        end)
    end)
  end

  defp next_batch(last_id, batch_size) do
    ExtractedImage
    |> where([e], is_nil(e.dedupe_fingerprint) or e.dedupe_fingerprint == "")
    |> maybe_after_id(last_id)
    |> order_by([e], asc: e.id)
    |> limit(^batch_size)
    |> Repo.all()
  end

  defp maybe_after_id(query, nil), do: query
  defp maybe_after_id(query, last_id), do: where(query, [e], e.id > ^last_id)

  defp changeset_scope_value(changeset, scope_field, metadata) do
    metadata = normalize_map(metadata)
    metadata_key = Atom.to_string(scope_field)

    cond do
      Map.has_key?(metadata, metadata_key) ->
        Map.get(metadata, metadata_key)

      ExtractedImageMetadata.schema_field?(scope_field) ->
        get_field(changeset, scope_field)

      true ->
        nil
    end
  end

  defp scope_value(scope_field, image, attrs, metadata) do
    metadata_key = Atom.to_string(scope_field)

    if Map.has_key?(metadata, metadata_key) do
      Map.get(metadata, metadata_key)
    else
      attribute_value(attrs, scope_field, legacy_value(image, scope_field))
    end
  end

  defp normalized_metadata(attrs, image) do
    attrs
    |> Map.get(:metadata, Map.get(attrs, "metadata", image.metadata))
    |> normalize_map()
  end

  defp attribute_value(attrs, field, fallback) do
    cond do
      Map.has_key?(attrs, field) -> Map.get(attrs, field)
      Map.has_key?(attrs, Atom.to_string(field)) -> Map.get(attrs, Atom.to_string(field))
      true -> fallback
    end
  end

  defp legacy_value(image, field) do
    if ExtractedImageMetadata.schema_field?(field) do
      Map.get(image, field)
    else
      nil
    end
  end

  defp normalize_component(value) do
    value
    |> to_string_or_nil()
    |> case do
      nil ->
        :error

      normalized ->
        normalized =
          normalized
          |> String.trim()
          |> String.downcase()

        if normalized == "", do: :error, else: {:ok, normalized}
    end
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value) when is_binary(value), do: value
  defp to_string_or_nil(value), do: to_string(value)

  defp normalize_map(metadata) when is_map(metadata) do
    Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_map(_metadata), do: %{}
end
