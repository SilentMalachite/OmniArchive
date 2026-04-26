defmodule OmniArchive.DomainProfiles.GeneralArchiveTest do
  use ExUnit.Case, async: false

  alias OmniArchive.DomainMetadataValidation
  alias OmniArchive.DomainProfiles
  alias OmniArchive.DomainProfiles.Archaeology
  alias OmniArchive.DomainProfiles.GeneralArchive

  import OmniArchive.DomainProfileTestHelper

  setup do
    put_domain_profile(GeneralArchive)
    :ok
  end

  test "GeneralArchive の metadata fields と search facets を返す" do
    assert DomainProfiles.current() == GeneralArchive

    assert Enum.map(DomainProfiles.metadata_fields(), & &1.field) == [
             :summary,
             :label,
             :collection,
             :item_type,
             :date_note
           ]

    assert DomainProfiles.search_facets() == [
             %{field: :collection, param: "collection", label: "🗂️ コレクション"},
             %{field: :item_type, param: "item_type", label: "📁 資料種別"},
             %{field: :date_note, param: "date_note", label: "📅 年代メモ"}
           ]

    assert DomainProfiles.profile_key() == "general_archive"
    assert DomainProfiles.duplicate_scope_field() == :collection
  end

  test "GeneralArchive の validation と UI text を返す" do
    assert DomainMetadataValidation.duplicate_scope_field() == :collection
    assert DomainMetadataValidation.duplicate_label_error() == "このコレクションでそのラベルは既に登録されています"
    assert DomainProfiles.ui_text([:search, :placeholder]) == "サマリー、ラベル、コレクション名で検索..."

    assert DomainMetadataValidation.validate_field(:label, "photo-001") == nil

    assert DomainMetadataValidation.validate_field(:label, "fig-1-1") ==
             "半角小文字・数字・ハイフンのみの slug 形式で入力してください（例: photo-001）"
  end

  test "デフォルトは GeneralArchive" do
    restore = Application.get_env(:omni_archive, :domain_profile)
    Application.delete_env(:omni_archive, :domain_profile)

    try do
      assert DomainProfiles.current() == GeneralArchive
    after
      if restore do
        Application.put_env(:omni_archive, :domain_profile, restore)
      else
        Application.delete_env(:omni_archive, :domain_profile)
      end
    end
  end

  test "put_domain_profile(Archaeology) で Archaeology にオプトインできる" do
    put_domain_profile(Archaeology)
    assert DomainProfiles.current() == Archaeology
    assert DomainProfiles.profile_key() == "archaeology"
    assert DomainProfiles.duplicate_scope_field() == :site
  end
end
