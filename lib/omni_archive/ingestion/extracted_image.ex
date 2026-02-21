defmodule OmniArchive.Ingestion.ExtractedImage do
  @moduledoc """
  抽出画像を管理する Ecto スキーマ。
  クロップデータ(JSONB)、キャプション、ラベル、PTIFパスを保持します。

  ## なぜこの設計か

  - **geometry を JSONB で保持**: クロップ領域 `{x, y, width, height}` を
    マップとして保存することで、将来的に矩形以外のクロップ形状（多角形や
    円形）にも拡張可能です。専用カラムに分離するよりスキーマ変更が不要です。
  - **status フィールド**: Stage-Gate ワークフローに対応し、
    `draft / pending_review / published` の3状態を文字列で管理します。
    Enum 型ではなく文字列を使うことで、マイグレーションなしに新しい
    ステータスを追加できる柔軟性を確保しています。
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "extracted_images" do
    # 抽出元のページ番号
    field :page_number, :integer
    # 抽出画像のファイルパス
    field :image_path, :string
    # クロップデータ (x, y, width, height) — JSONB
    field :geometry, :map
    # キャプション (手動入力)
    field :caption, :string
    # ラベル (手動入力)
    field :label, :string
    # 生成された PTIF のパス
    field :ptif_path, :string

    # ステータス (draft / pending_review / rejected / published)
    field :status, :string, default: "draft"
    # 動的メタデータ (Key-Value) — JSONB
    field :custom_metadata, :map, default: %{}
    # レビュアーによる差し戻し理由
    field :review_comment, :string
    # 楽観的ロック用バージョンカウンター
    field :lock_version, :integer, default: 1

    belongs_to :pdf_source, OmniArchive.Ingestion.PdfSource
    has_one :iiif_manifest, OmniArchive.IIIF.Manifest
    # 所有者（アップロードした人）
    belongs_to :owner, OmniArchive.Accounts.User
    # 作業者（現在編集中の人）
    belongs_to :worker, OmniArchive.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "バリデーション用 changeset"
  def changeset(extracted_image, attrs) do
    attrs = transform_metadata(attrs)

    extracted_image
    |> cast(attrs, [
      :pdf_source_id,
      :page_number,
      :image_path,
      :geometry,
      :caption,
      :label,
      :ptif_path,
      :custom_metadata,
      :status,
      :review_comment,
      :lock_version,
      :owner_id,
      :worker_id
    ])
    |> validate_required([:pdf_source_id, :page_number])
    |> validate_inclusion(:status, ~w(draft pending_review rejected published deleted))
    |> validate_label_format()
    |> foreign_key_constraint(:pdf_source_id)
    |> optimistic_lock(:lock_version)
  end

  # --- カスタムバリデーション ---

  # ラベル形式チェック: 値が入力済みの場合のみ適用
  defp validate_label_format(changeset) do
    label = get_field(changeset, :label)

    if label && label != "" do
      validate_format(changeset, :label, ~r/^fig-\d+-\d+$/,
        message: "形式は 'fig-番号-番号' にしてください（例: fig-1-1）"
      )
    else
      changeset
    end
  end

  # 動的メタデータ変換: リスト（またはマップ）構造をJSONB登録用のMapに変換。空のKeyは除外
  defp transform_metadata(attrs) do
    has_str_key = Map.has_key?(attrs, "custom_metadata_list")
    has_atom_key = Map.has_key?(attrs, :custom_metadata_list)

    if not has_str_key and not has_atom_key do
      attrs
    else
      raw_list =
        Map.get(attrs, "custom_metadata_list") || Map.get(attrs, :custom_metadata_list) || %{}

      list =
        cond do
          is_map(raw_list) ->
            # LiveView フォームからの送信時 (%{"0" => %{...}, "1" => %{...}})
            raw_list
            |> Enum.sort_by(fn {idx, _} -> String.to_integer(to_string(idx)) end)
            |> Enum.map(fn {_idx, data} -> data end)

          is_list(raw_list) ->
            raw_list

          true ->
            []
        end

      map_data =
        list
        |> Enum.reject(fn data ->
          key = Map.get(data, "key", Map.get(data, :key, ""))
          is_nil(key) or String.trim(to_string(key)) == ""
        end)
        |> Enum.into(%{}, fn data ->
          key = Map.get(data, "key", Map.get(data, :key, ""))
          val = Map.get(data, "value", Map.get(data, :value, ""))
          {String.trim(to_string(key)), to_string(val)}
        end)

      if has_str_key do
        Map.put(attrs, "custom_metadata", map_data)
      else
        Map.put(attrs, :custom_metadata, map_data)
      end
    end
  end
end
