defmodule OmniArchive.DomainProfiles.GeneralArchive do
  @moduledoc """
  汎用アーカイブ向けのメタデータ定義。
  """

  @behaviour OmniArchive.DomainProfile

  @impl true
  def metadata_fields do
    [
      %{
        field: :caption,
        storage: :core,
        label: "📝 キャプション",
        placeholder: "例: 収蔵資料の見出しや内容説明"
      },
      %{
        field: :label,
        storage: :core,
        label: "🏷️ ラベル",
        placeholder: "例: photo-001, doc-2024-05"
      },
      %{
        field: :collection,
        storage: :metadata,
        label: "🗂️ コレクション",
        placeholder: "例: 広報写真アーカイブ"
      },
      %{
        field: :item_type,
        storage: :metadata,
        label: "📁 資料種別",
        placeholder: "例: 写真, 書簡, ポスター"
      },
      %{
        field: :date_note,
        storage: :metadata,
        label: "📅 年代メモ",
        placeholder: "例: 1960年代後半ごろ"
      }
    ]
  end

  @impl true
  def validation_rules do
    %{
      caption: %{
        max_length: 1000,
        max_length_error: "1000文字以内で入力してください"
      },
      label: %{
        max_length: 100,
        max_length_error: "100文字以内で入力してください",
        format: ~r/^(?!fig-\d+-\d+$)[a-z0-9]+(?:-[a-z0-9]+)*$/,
        format_error: "半角小文字・数字・ハイフンのみの slug 形式で入力してください（例: photo-001）"
      },
      collection: %{
        max_length: 120,
        max_length_error: "120文字以内で入力してください"
      },
      item_type: %{
        max_length: 60,
        max_length_error: "60文字以内で入力してください"
      },
      date_note: %{
        max_length: 80,
        max_length_error: "80文字以内で入力してください"
      },
      duplicate_scope_field: :collection,
      duplicate_label_error: "このコレクションでそのラベルは既に登録されています"
    }
  end

  @impl true
  def search_facets do
    [
      %{field: :collection, param: "collection", label: "🗂️ コレクション"},
      %{field: :item_type, param: "item_type", label: "📁 資料種別"},
      %{field: :date_note, param: "date_note", label: "📅 年代メモ"}
    ]
  end

  @impl true
  def ui_texts do
    %{
      search: %{
        page_title: "画像を検索",
        heading: "🔍 画像を検索",
        description: "キーワードやフィルターで、登録済みの図版を検索できます。",
        placeholder: "キャプション、ラベル、コレクション名で検索...",
        empty_filtered: "条件に一致する図版が見つかりませんでした。",
        empty_filtered_hint: "検索キーワードやフィルターを変更してみてください。",
        empty_initial: "まだ図版が登録されていません。",
        empty_initial_hint: "Inspector から PDF をアップロードして図版を登録してください。",
        result_none: "結果なし",
        result_suffix: "件の図版が見つかりました",
        clear_filters: "✕ フィルターをクリア"
      },
      inspector_label: %{
        heading: "🏷️ 図版の情報を入力してください",
        description: "各フィールドに情報を入力してください。入力内容は自動的に保存されます。",
        duplicate_warning: "このコレクションでそのラベルは既に登録されています",
        duplicate_blocked: "⚠️ 重複ラベルがあります。ラベルを変更するか、既存レコードを更新してください。",
        duplicate_title: "重複先:",
        duplicate_edit: "📝 既存レコードを更新"
      }
    }
  end

  @impl true
  def duplicate_identity do
    %{
      profile_key: "general_archive",
      scope_field: :collection,
      label_field: :label,
      duplicate_label_error: "このコレクションでそのラベルは既に登録されています"
    }
  end
end
