# OmniArchive セキュリティレビュー報告書

更新日: 2026-04-27

## エグゼクティブサマリー

OmniArchive は Phoenix の基本的な CSRF 対策、セッション署名、Ecto のパラメータ化クエリ、公開 IIIF Manifest の `published` チェックなど、良い土台があります。初回レビューで重大として挙げた `/lab/approval` の一般ユーザー利用と `priv/static/uploads` の直接公開は、現状のコードでは対策済みです。

現時点で重大・高・中・低 / 要確認として分類する未解消項目はありません。

注意: 使用した `security-best-practices` スキルの公式リファレンスは Python / JavaScript / Go 向けで、Elixir/Phoenix 専用リファレンスはありませんでした。本報告はリポジトリ実装と一般的な Web/Phoenix セキュリティ観点に基づくレビューです。

## 現在の状態

- 解消済み: `SEC-001` `/lab/approval` はルートから削除され、ログイン済みユーザーでも 404 になります。
- 解消済み: `SEC-002` `uploads` は `Plug.Static` の対象から外れ、`/uploads/...` は直接配信されません。Lab ページ画像は認証・所有者確認付きの `/lab/uploads/pages/:pdf_source_id/:filename` から配信されます。
- 解消済み: `SEC-003` Gallery の `select_image` イベントは `published` 画像だけを取得するようになりました。
- 解消済み: `SEC-004` Finalize 画面は画像の `pdf_source_id` を現在ユーザーで取得できる場合だけ表示されます。
- 解消済み: `SEC-005` Lab 検索はログインユーザーがアクセスできる画像だけを検索し、フィルター候補も同じスコープから作ります。
- 解消済み: `SEC-006` IIIF Image API は `published` 画像だけを配信し、不正な画像リクエストは 400 で返します。
- 解消済み: `SEC-007` PDF 処理はページ数・生成画像サイズ・外部コマンド時間・ユーザー別投入量を制限します。
- 解消済み: `SEC-008` カスタム/YAML メタデータフィールドは外部入力由来の atom を生成せず、string key のまま扱います。
- 解消済み: `SEC-009` LiveView イベントのタブ名・ID は allowlist / 完全一致パースで検証し、不正値では flash を返します。
- 解消済み: `SEC-010` 公開 route param と Lab/Admin route/event ID は nil-safe getter と完全一致パースで扱い、不正 ID による 500 を防止します。
- 解消済み: `SEC-011` Crop LiveView の geometry は頂点数・座標範囲・矩形サイズ・面積をサーバー側で制限します。

## 解消済み

### SEC-001: `/lab/approval` から一般ログインユーザーが承認操作できる

初回影響: 一般ユーザーが他ユーザーのレビュー待ち画像を公開または差し戻しでき、Stage-Gate の管理者承認モデルが破られる可能性がありました。

対応状況:
- `lib/omni_archive_web/router.ex:41` 以降の Lab live session から `/approval` ルートが削除されています。
- `test/omni_archive_web/live/approval_live_test.exs` は、ログイン済みユーザーでも `GET /lab/approval` が 404 になることを確認します。

残リスク:
- `lib/omni_archive_web/live/approval_live.ex` 自体は残っています。ルートから到達できないため直接の攻撃面ではありませんが、完全に廃止する方針ならモジュールと関連 CSS/テストの整理も検討してください。

### SEC-002: `priv/static/uploads` が公開静的ファイルとして配信される

初回影響: 未ログインの利用者でも、URL を推測またはログ等から取得できれば、承認前の PDF やページ画像を直接取得できる可能性がありました。

対応状況:
- `lib/omni_archive_web.ex:20` の `static_paths` から `uploads` が削除されています。
- `lib/omni_archive_web/router.ex:39` に認証必須の `/lab/uploads/pages/:pdf_source_id/:filename` が追加されています。
- `lib/omni_archive_web/controllers/upload_asset_controller.ex:6` は `current_scope.user` と nil-safe な `Ingestion.get_pdf_source(pdf_source_id, user)` により所有者/admin を確認してから `send_file/3` します。
- `test/omni_archive_web/controllers/static_uploads_access_test.exs:7` は `/uploads/direct-access-test.txt` が 404 になることを確認します。
- `test/omni_archive_web/controllers/static_uploads_access_test.exs:33` と `:42` は、所有者のみページ画像を取得でき、他ユーザーは 404 になることを確認します。

残リスク:
- PDF 本体は引き続き `priv/static/uploads/pdfs` に保存されていますが、`uploads` が静的配信対象から外れたため直接 URL では見えません。将来的には保存先自体も `priv/static` 外の private storage に移すと、設定ミス時の防御が厚くなります。
- 公開用 Gallery / IIIF が元の page image に依存しないことを保つ必要があります。

### SEC-003: 公開 Gallery の LiveView イベントで任意 ID の非公開画像を選択できる

初回影響: 未ログイン利用者が LiveView イベントを直接送ることで、Gallery に表示されていない draft / pending_review / rejected 画像のラベルやサマリーを取得できる可能性がありました。

対応状況:
- `lib/omni_archive_web/live/gallery_live.ex` の `select_image` は、公開済み画像だけを返す `Ingestion.get_published_extracted_image_with_manifest/1` を使うようになっています。
- `lib/omni_archive/ingestion.ex` に `status == "published"` で絞る取得関数が追加されています。
- `test/omni_archive_web/live/gallery_live_test.exs` は、`draft` / `pending_review` / `rejected` の ID を直接指定してもモーダルに表示されないことを確認します。

残リスク:
- 公開済み画像については任意 ID で選択可能です。公開 Gallery の情報なので機密性の問題は限定的ですが、現在の検索結果に含まれる ID だけを許可すると UI 整合性はさらに高まります。

### SEC-004: Finalize 画面が画像 ID を所有者で検証していない

初回影響: ログイン済みユーザーが他ユーザーの画像 ID を指定して `/lab/finalize/:image_id` にアクセスし、Finalize 処理やレビュー提出を実行できる可能性がありました。

対応状況:
- `lib/omni_archive_web/live/inspector_live/finalize.ex` の `mount/3` は、nil-safe な画像取得後に `Ingestion.get_pdf_source(image.pdf_source_id, current_user)` を呼び、現在ユーザーがその `PdfSource` を取得できる場合だけ画面を表示します。
- 一般ユーザーが他ユーザーの画像 ID を指定した場合は `/lab` に戻し、「指定された画像が見つかりません」と表示します。
- `test/omni_archive_web/live/inspector_live/finalize_test.exs` は、他ユーザーの画像 ID でアクセスできないことを確認します。

残リスク:
- Admin は `Ingestion.get_pdf_source!/2` の既存仕様どおり任意の `PdfSource` を取得できます。これは管理者権限の期待動作です。

### SEC-005: Lab 検索が全ユーザー・全内部画像を返す

初回影響: ログイン済み一般ユーザーが他ユーザーの内部画像メタデータやサムネイルを検索・閲覧できる可能性がありました。

対応状況:
- `lib/omni_archive/search.ex:56` に Lab 用の `search_images_for_user/3` が追加され、一般ユーザーは `owner_id == current_user.id` の画像だけを検索します。Admin は既存の管理者権限に合わせて全件検索できます。
- `lib/omni_archive/search.ex:95` に `list_filter_options_for_user/1` が追加され、フィルター候補も同じユーザースコープから作られます。
- `lib/omni_archive_web/live/search_live.ex:23`、`:26`、`:43`、`:69`、`:85` は、既存のグローバル検索ではなく user-scoped API を使います。
- `test/omni_archive_web/live/search_live_test.exs:204` は、他ユーザーの非公開画像が初期表示・検索結果・フィルター候補に出ないことを確認します。

残リスク:
- Admin は Lab 検索でも全件を検索できます。これは他の Lab / Admin 一覧と同じ管理者権限の期待動作です。

### SEC-006: IIIF Image API が画像ステータスを確認せず、入力不正時に 500 を返し得る

初回影響: Manifest が残った非公開・削除相当画像のタイルが配信される可能性がありました。また、不正な `region` / `size` 値で例外が発生し、軽い DoS やログ汚染につながる状態でした。

対応状況:
- `lib/omni_archive_web/controllers/iiif/image_controller.ex:48` 以降で、`quality.format` / `region` / `size` / `rotation` を画像処理前に明示検証し、不正値は 400 を返します。
- `lib/omni_archive_web/controllers/iiif/image_controller.ex:129` 以降で Manifest と `ExtractedImage` を join し、`status == "published"` かつ PTIF パスがある画像だけを配信対象にしました。
- `lib/omni_archive_web/controllers/iiif/image_controller.ex:27` 以降で許可 format / quality / rotation と出力サイズ・region 上限を定義し、過大な明示リサイズや region を拒否します。
- `lib/omni_archive_web/controllers/iiif/image_controller.ex:238` はリクエスト文字列をそのままファイル名にせず、SHA-256 由来の cache key を使います。
- `test/omni_archive_web/controllers/iiif/image_controller_test.exs:19` と `:48` は非公開画像の info.json / tile が 404 になることを確認します。
- `test/omni_archive_web/controllers/iiif/image_controller_test.exs:57` 以降は、不正な `region` / `size` / `rotation` / `format` が 400 になることを確認します。

残リスク:
- `full` / `max` は IIIF ビューア互換性のため引き続き許可しています。極端に巨大な公開 PTIF を扱う場合は、生成時の画像サイズ制限や CDN / reverse proxy 側のレート制限も併用してください。

### SEC-007: PDF 処理ジョブに実行時間・ページ数・ユーザー別クォータが不足している

初回影響: 招待制でも、ログイン済みユーザーが巨大または処理負荷の高い PDF を投入すると、CPU・ディスク・ジョブ枠を長時間占有できる可能性がありました。

対応状況:
- `lib/omni_archive_web/live/inspector_live/upload.ex:15` で LiveView アップロード上限を 100MB に下げています。
- `lib/omni_archive_web/live/inspector_live/upload.ex:365` 以降で、同一ユーザーの処理中 PDF がある場合と、24時間あたり 20 件を超える場合は追加アップロードを拒否します。
- `lib/omni_archive/workers/user_worker.ex:45` 以降で、ユーザー単位 Worker が処理中ジョブを持つ間は追加 `process_pdf` を `{:error, :pdf_job_in_progress}` で拒否します。
- `lib/omni_archive/ingestion/pdf_processor.ex:22` 以降で、PDF ページ数上限 200、外部コマンド単位のタイムアウト 120 秒、生成 PNG 総量上限 1GB を設定しています。
- `lib/omni_archive/ingestion/pdf_processor.ex:104` 以降で `pdfinfo` / `pdftoppm` をタイムアウト付きで実行し、`Task.async_stream` の `timeout: :infinity` を廃止しました。
- `lib/omni_archive/ingestion/pdf_processor.ex:130` 以降で、生成 PNG の総サイズが上限を超えた場合はエラーにし、部分生成物を削除します。
- `test/omni_archive/ingestion/pdf_processor_test.exs:35` 以降は、ページ数上限、`pdfinfo` タイムアウト、`pdftoppm` タイムアウト、生成画像サイズ上限と掃除を確認します。
- `test/omni_archive_web/live/inspector_live/upload_test.exs:61` 以降は、処理中ジョブと 24時間アップロード上限で追加アップロードできないことを確認します。

残リスク:
- 制限値はコード定数です。運用環境ごとに調整したい場合は、将来的に runtime config 化してください。
- PDF 物理ファイルの保存先は引き続き `priv/static/uploads/pdfs` です。`SEC-002` で直接配信は止めていますが、保存先自体を private storage に移すと防御がさらに厚くなります。

### SEC-008: Sobelow が `String.to_atom` を低確度で検出

初回影響: 無制限の外部入力から atom を生成すると atom table 枯渇 DoS につながる可能性がありました。

対応状況:
- `lib/omni_archive/custom_metadata_fields.ex` は、カスタムフィールドの `field_key` を atom に変換せず、既存の形式検証後に string key のまま profile / validation rule / search facet へ渡します。
- `lib/omni_archive/domain_profiles/yaml_loader.ex` は、YAML の `metadata_fields.field`、`validation_rules`、`search_facets`、`duplicate_identity` の参照を定義済みフィールドの string key と照合し、動的 atom を生成しません。
- `lib/omni_archive/domain_profiles.ex`、`lib/omni_archive/ingestion/extracted_image_metadata.ex`、`lib/omni_archive/search.ex`、`lib/omni_archive/duplicate_identity.ex`、`lib/omni_archive/domain_metadata_validation.ex`、`lib/omni_archive_web/live/inspector_live/label.ex` は、フィールド識別子を atom / string のどちらでも同じ key として扱えるようになっています。
- `lib/omni_archive/safe_atom.ex` は削除され、`rg "String\\.to_atom|binary_to_atom|list_to_atom|SafeAtom" -n lib test` で該当がないことを確認しています。
- `test/omni_archive/custom_metadata_fields_test.exs` は、カスタムフィールド変換が string key を返し、不正 key を拒否することを確認します。
- `test/omni_archive/domain_profiles/yaml_loader_test.exs` は、YAML の validation rule / facet / duplicate identity が定義済みフィールド参照だけを受け付けることを確認します。

残リスク:
- compile-time profile は従来どおり atom フィールドを使います。外部入力由来の新規 atom 生成は避けつつ、境界では `to_string/1` による key 比較を継続してください。

### SEC-009: 一部イベントが不正入力で 500 を返し得る

初回影響: 攻撃者が LiveView イベントに想定外の値を送ると、プロセス例外による軽い DoS につながる可能性がありました。

対応状況:
- `lib/omni_archive_web/live/inspector_live/upload.ex` の `switch_tab` は、`upload` / `rejected` の明示 allowlist だけを受け付け、不正なタブ名では状態を変えません。
- `lib/omni_archive_web/live/admin/review_live.ex` は、`select_image` / `delete` / `approve` / `open_reject_modal` / `confirm_reject` の ID を完全一致の正整数として検証し、対象画像が存在しない場合も flash で戻します。
- `lib/omni_archive_web/live/admin/dashboard_live.ex` は、選択・通常削除・強制削除の ID を検証し、不正値や未存在 ID で例外を出しません。
- `lib/omni_archive_web/live/admin/custom_fields_live.ex` は、編集・有効化切替・並び替え・削除の ID を検証し、不正値や未存在 ID で例外を出しません。
- `lib/omni_archive/ingestion.ex` に nil-safe な `get_extracted_image/1`、`lib/omni_archive/custom_metadata_fields.ex` に nil-safe な `get_field/1` を追加し、event handler から bang 関数へ不正 ID を渡さないようにしました。
- `rg "String\\.to_integer\\(|String\\.to_existing_atom\\(" -n lib/omni_archive_web/live lib/omni_archive_web/controllers` で、Web の LiveView / controller event 境界に直接変換が残っていないことを確認しています。

残リスク:
- shell 出力など内部プロセス出力を整数変換する箇所は残っていますが、外部 LiveView イベント境界ではありません。

### SEC-010: 不正な route param / event ID が一部で 500 を返し得る

初回影響: `/download/:id`、IIIF Presentation、Lab/Admin の一部 LiveView で、不正な ID 文字列を route param または event payload として送ると `Ecto.Query.CastError` や bang getter 由来の例外が発生し、ログ汚染や軽い DoS につながる可能性がありました。

対応状況:
- `lib/omni_archive/ingestion.ex` に nil-safe な `get_pdf_source/1` と `get_pdf_source/2` を追加し、完全一致の正整数だけを DB に渡します。
- `lib/omni_archive/accounts.ex` に nil-safe な `get_user/1` を追加し、Admin user delete event が不正 ID で落ちないようにしました。
- `lib/omni_archive_web/controllers/download_controller.ex` は `Repo.get(ExtractedImage, id)` ではなく `Ingestion.get_extracted_image(id)` を使い、不正 ID を 404 にします。
- `lib/omni_archive_web/controllers/iiif/presentation_controller.ex` は `Ingestion.get_pdf_source(source_id)` を使い、不正 `source_id` を 404 JSON にします。
- `lib/omni_archive_web/controllers/upload_asset_controller.ex` は Lab ページ画像配信の `pdf_source_id` を nil-safe に取得し、不正 ID は 404 にします。
- `lib/omni_archive_web/live/lab_live/index.ex`、`lab_live/show.ex`、`inspector_live/browse.ex`、`inspector_live/crop.ex`、`inspector_live/label.ex`、`inspector_live/finalize.ex` は、不正 route/event ID を `/lab` への遷移または flash に変換します。
- `lib/omni_archive_web/live/admin/admin_trash_live/index.ex`、`admin_user_live/index.ex`、到達不能な旧 `approval_live.ex` も不正 ID を通常分岐で処理します。

残リスク:
- コンテキスト層には既存互換の bang getter が残っています。外部入力境界では nil-safe getter を使う運用を継続してください。

### SEC-011: Crop geometry が大きすぎる入力を制限していない

初回影響: ログイン済みユーザーが LiveView event を直接送り、巨大な polygon 配列や異常な矩形を保存すると、後段の `ImageProcessor` / libvips 処理で CPU・メモリ負荷を増やせる可能性がありました。

対応状況:
- `lib/omni_archive_web/live/inspector_live/crop.ex` は polygon 頂点数を最大 64 点、座標範囲を `0..20_000`、矩形辺を `1..20_000`、bbox / 矩形面積を最大 `100_000_000` px に制限します。
- `preview_crop`、`save_crop`、旧互換の `update_crop_data`、`proceed_to_label` 直前保存のすべてで同じサーバー側検証を通します。
- 不正 geometry では `put_flash(:error, "クロップ範囲が不正です")` を返し、DB へ保存しません。
- `test/omni_archive_web/live/inspector_live/crop_test.exs` は、頂点数過多、座標範囲外、巨大矩形が保存されないことを確認します。

残リスク:
- 制限値はコード定数です。扱う原稿サイズが環境ごとに大きく変わる場合は、将来的に runtime config 化してください。

## 重大

現時点で重大として分類する未解消項目はありません。初回レビュー時の重大 2 件は上記のとおり対策済みです。

## 高

現時点で高として分類する未解消項目はありません。初回レビュー時の高 1 件は上記のとおり対策済みです。

## 中

現時点で中として分類する未解消項目はありません。

## 低 / 要確認

現時点で低 / 要確認として分類する未解消項目はありません。

## 良かった点

- Browser pipeline に `protect_from_forgery` と `put_secure_browser_headers` が入っています。
- Search の SQL は Ecto の binding と fragment parameter を使っており、検索文字列を SQL 文字列結合していません。
- DownloadController は `status == "published"` を確認してからダウンロード処理をしています。
- Admin 名前空間の主要画面は `on_mount(:ensure_admin)` に置かれています。
- `/lab/approval` は到達不能になり、旧承認 UI からの公開操作はできません。
- `priv/static/uploads` は静的配信対象から外れ、Lab ページ画像は認証・所有者チェック付きコントローラー経由になっています。
- Gallery の `select_image` は公開済み画像のみを選択します。
- Finalize 画面は画像 ID から親 `PdfSource` の所有者を確認してから表示されます。
- Lab 検索は一般ユーザーに対して所有画像だけを返し、他ユーザーの facet 値も表示しません。
- IIIF Image API は公開済み画像だけを配信し、不正な画像リクエストを 400 で扱います。
- PDF 処理はページ数・実行時間・生成物サイズ・ユーザー別投入量を制限します。
- カスタム/YAML メタデータフィールドは外部入力由来の atom を生成せず、string key のまま処理します。
- LiveView イベント境界のタブ名・ID は明示 allowlist / 完全一致パースで検証します。
- 公開 route param と Lab/Admin の route/event ID は nil-safe getter で扱い、不正値を 404/flash に変換します。
- Crop geometry は頂点数・座標範囲・矩形サイズ・面積を保存前に制限します。
- `mix review` は compile / Credo / Sobelow / Dialyzer を通過しました。

## 検証

- `/lab/approval` 無効化後:
  - `mix test test/omni_archive_web/live/approval_live_test.exs`: PASS
  - `mix precommit`: PASS
  - `mix review`: PASS
- `priv/static/uploads` 非公開化後:
  - `mix test test/omni_archive_web/controllers/static_uploads_access_test.exs`: PASS
  - 関連テスト（Browse / Gallery / IIIF Presentation）: PASS
  - `mix precommit`: PASS (`399 tests, 0 failures, 4 skipped`)
  - `mix review`: PASS
- Gallery 非公開画像選択防止後:
  - `mix test test/omni_archive_web/live/gallery_live_test.exs`: PASS
- Finalize 所有者チェック追加後:
  - `mix test test/omni_archive_web/live/inspector_live/finalize_test.exs`: PASS
- Lab 検索所有者スコープ追加後:
  - `mix test test/omni_archive_web/live/search_live_test.exs`: PASS
  - `mix test test/omni_archive/search_test.exs`: PASS
- IIIF Image API ステータス確認・入力検証追加後:
  - `mix test test/omni_archive_web/controllers/iiif/image_controller_test.exs`: PASS
  - `mix test test/omni_archive_web/controllers/iiif/image_controller_test.exs test/omni_archive_web/controllers/iiif/manifest_controller_test.exs test/omni_archive_web/controllers/iiif/presentation_controller_test.exs test/omni_archive/iiif/manifest_test.exs`: PASS
- PDF 処理ジョブ制限追加後:
  - `mix test test/omni_archive/ingestion/pdf_processor_test.exs`: PASS
  - `mix test test/omni_archive/pipeline/pipeline_test.exs test/omni_archive_web/live/inspector_live/upload_test.exs test/omni_archive/ingestion/pdf_processor_test.exs`: PASS
- 動的 atom 生成廃止後:
  - `mix test test/omni_archive/domain_profiles/yaml_loader_test.exs test/omni_archive/domain_profiles/yaml_cache_test.exs test/omni_archive/domain_profiles/yaml_test.exs test/omni_archive/custom_metadata_fields_test.exs test/omni_archive/custom_metadata_fields/reserved_keys_test.exs test/omni_archive/search_test.exs test/omni_archive_web/live/inspector_live/label_test.exs`: PASS
  - `rg "String\\.to_atom|binary_to_atom|list_to_atom|SafeAtom" -n lib test`: 該当なし
- LiveView イベント入力検証追加後:
  - `mix test test/omni_archive_web/live/inspector_live/upload_test.exs test/omni_archive_web/live/admin/admin_review_live_test.exs test/omni_archive_web/live/admin/admin_dashboard_live_test.exs test/omni_archive_web/live/admin/custom_fields_live_test.exs`: PASS
  - `rg "String\\.to_integer\\(|String\\.to_existing_atom\\(" -n lib/omni_archive_web/live lib/omni_archive_web/controllers`: 該当なし
- route param / event ID nil-safe 化後:
  - `mix test test/omni_archive_web/controllers/download_controller_test.exs test/omni_archive_web/controllers/iiif/presentation_controller_test.exs test/omni_archive_web/controllers/static_uploads_access_test.exs test/omni_archive_web/live/inspector_live/browse_test.exs test/omni_archive_web/live/inspector_live/crop_test.exs test/omni_archive_web/live/inspector_live/finalize_test.exs test/omni_archive_web/live/inspector_live/label_test.exs test/omni_archive_web/live/lab_live/index_test.exs test/omni_archive_web/live/lab_live/show_test.exs test/omni_archive_web/live/admin/admin_trash_live_test.exs test/omni_archive_web/live/admin/admin_user_live_test.exs`: PASS
- Crop geometry 制限追加後:
  - `mix test test/omni_archive_web/live/inspector_live/crop_test.exs`: PASS
  - `mix test test/omni_archive_web/live/inspector_live`: PASS
- 最終確認:
  - `mix precommit`: PASS (`447 tests, 0 failures, 4 skipped`)
- `mix review`: PASS
  - PostgreSQL version check: PASS
  - compile --warnings-as-errors: PASS
  - credo --strict: PASS
  - sobelow --config: PASS。`SEC-008` の `DOS.StringToAtom` / `DOS.BinToAtom` は解消済み。静的 backfill SQL には低確度 `SQL.Query` 表示が残ります。
  - dialyzer: PASS
