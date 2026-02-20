# 変更履歴 (Changelog)

このプロジェクトは [Semantic Versioning](https://semver.org/lang/ja/) に準拠しています。

---

## [0.2.11] - 2026-02-20

### 🔐 権限管理 (RBAC) & アクセス制御の強化
- **`PdfSource` のオーナーシップ管理とマルチユーザーデータ隔離**
  - `pdf_sources` テーブルに `user_id` カラムを追加し、プロジェクトの「所有者」を明確化。
  - `Ingestion` コンテキストにおけるフェッチ処理（`get_pdf_source!/2`、`list_pdf_sources/1`）をすべて `user_id` による厳密なスコーピングに移行。
  - Lab 全面（一覧、閲覧、クロップ、ラベリング、アップロード）で、Admin は全データ、一般ユーザーは「自身のプロジェクト」のみアクセス・編集可能に制限。
  - 不正なアクセス（他人のプロジェクトを開こうとする等）に対し `Ecto.NoResultsError` を返し、404 Not Found として安全に処理されるよう改修。
  - マイグレーション: `add_user_id_to_pdf_sources`

---

## [0.2.10] - 2026-02-19

### 📋 プロジェクト ワークフローステータス管理
- **`PdfSource` にワークフローステータスを追加**
  - `workflow_status` カラム（`wip` / `pending_review` / `returned` / `approved`）を追加。プロジェクト単位で作業進捗を管理。
  - `return_message` カラム（`text`）を追加。管理者が差し戻し時にプロジェクト全体へのメッセージを記録可能に。
  - マイグレーション: `add_workflow_status_to_pdf_sources`
- **ワークフロー遷移関数の実装**
  - `Ingestion.submit_project/1` — `wip` / `returned` → `pending_review`。提出時に `return_message` を自動クリア。
  - `Ingestion.return_project/2` — `pending_review` → `returned`。差し戻しメッセージを保存。
  - `Ingestion.approve_project/1` — `pending_review` → `approved`。
  - 不正な遷移は `{:error, :invalid_status_transition}` を返却。
- **Lab UI のワークフロー表示**
  - プロジェクトカードにワークフローステータスバッジを追加（作業中 / 作業完了/審査待ち / ⚠️ 差し戻しあり / 承認済み）。
  - `wip` / `returned` ステータス時に「✅ 作業完了として提出」ボタンを表示。
  - 差し戻しメッセージをプロジェクトカード内にアラートとして表示。

### 🔔 差し戻し理由の表示改善
- **ラベリング画面 (`/lab/label/:image_id`) の改善**
  - プロジェクトレベルの差し戻し（`workflow_status == "returned"`）でも差し戻しアラートを表示するよう拡張。
  - 管理者からの全体コメント（`return_message`）と個別画像コメント（`review_comment`）を分離表示。
  - 差し戻し理由ボックスの視覚的スタイリング（赤色左ボーダー・背景色）を追加。
- **Inspector 画面での差し戻し理由表示**
  - Browse 画面でプロジェクトレベル・画像レベルの差し戻し理由を確認可能に。

### 👤 オーナーメール表示（Admin 向け）
- **Lab プロジェクト一覧にオーナーメールアドレスを表示**
  - `list_pdf_sources/1` クエリに所有者情報を結合。`owner_email` バーチャルフィールドとして取得。
  - Admin ロールの場合のみ、プロジェクトカードにオーナーのメールアドレスを表示。

### 🔀 ルーティング改善
- **`/admin` → `/admin/review` リダイレクト**
  - `/admin` 直接アクセス時にデフォルトの Phoenix "Available routes" ページが表示されないよう、`/admin/review` へリダイレクトする `PageController.redirect_admin` アクションを追加。

### ✅ テスト
- **ワークフロー遷移テストの追加**
  - `submit_project/1`、`return_project/2`、`approve_project/1` の正常遷移・不正遷移テストを網羅的に追加（13テストケース）。

---

## [0.2.9] - 2026-02-18

### 🗑️ ソフトデリート & ゴミ箱管理
- **ソフトデリート機能の実装**
  - `PdfSource` スキーマに `deleted_at` カラム（`utc_datetime`）を追加。`nil` = アクティブ、値あり = ゴミ箱内。
  - `soft_delete_pdf_source/1` — `deleted_at` を現在時刻に設定し、物理ファイルは保持。
  - `restore_pdf_source/1` — `deleted_at` を `nil` に戻してプロジェクトを復元。
  - `hard_delete_pdf_source/1` — 既存の `delete_pdf_source/1` をリネーム。物理ファイル・DB レコードを完全削除。
  - `list_deleted_pdf_sources/0` — ソフトデリート済みプロジェクト一覧を取得（Admin ゴミ箱用）。
  - `list_pdf_sources/1` — ソフトデリート済みレコードを自動除外するフィルタを追加。
  - マイグレーション: `add_deleted_at_to_pdf_sources`
- **Admin ゴミ箱画面 (`/admin/trash`) の新設**
  - ソフトデリート済みプロジェクトをテーブル形式で一覧表示。
  - ♻️ 復元ボタン: プロジェクトを Lab 一覧に戻す。
  - 💀 完全削除ボタン: 確認ダイアログ付きの物理ファイル・DB レコード完全削除。
  - ローカルステート更新による即時 UI 反映。
  - 管理者タブレイアウトにゴミ箱タブを追加。

### 🔒 公開済みプロジェクトの削除防止
- **`is_published?/1` ヘルパーの追加**
  - PdfSource に紐づく `ExtractedImage` に `published` ステータスが存在するか判定。
- **ソフトデリートの安全ガード**
  - 公開済み画像を含むプロジェクトの削除を `{:error, :published_project}` で拒否。
- **Lab UI の保護表示**
  - 公開済みプロジェクトに 🔒 ロックアイコンを表示。
  - 削除ボタンを無効化し、ツールチップで理由を表示。

### 🐛 Lab 画面の改善
- **Draft 選択時のナビゲーション修正**
  - 「Draft」ボタンクリック時にラベリング画面ではなくクロップ画面へ遷移するよう修正。
- **Lab ステータス表示の修正**
  - `/lab` ディレクトリ内のステータス表示を「作業完了」から「取り込み完了」に変更。

---

## [0.2.8] - 2026-02-18

### 📁 Lab プロジェクト管理
- **プロジェクト一覧画面 (`/lab`) の新設**
  - PdfSource をカード形式で一覧表示。ファイル名、ページ数、画像数、ステータスを視覚的に表示。
  - RBAC 対応: Admin は全プロジェクト、一般ユーザーは自分の画像があるプロジェクトのみ表示。
  - カード UI にステータスバッジ（uploading / converting / ready / error）を表示。
  - プロジェクト削除機能（物理ファイル・関連画像ごとカスケード削除）。
- **プロジェクト詳細画面 (`/lab/projects/:id`) の新設**
  - PdfSource に紐づく画像をサムネイルグリッドで表示。各画像のラベル・ステータスを表示。
  - 画像がない場合の再処理（Re-process）ボタンを提供。
  - 所有権チェック付き PdfSource 取得（一般ユーザーは自分のプロジェクトのみ閲覧可能）。
- **`Ingestion` コンテキスト拡張**
  - `list_pdf_sources/1` — RBAC 対応の PdfSource 一覧（画像数を `select_merge` で集計）。
  - `get_pdf_source!/2` — 所有権チェック付き取得。
  - `reprocess_pdf_source/2` — PDF 再抽出の非同期実行。
  - `delete_pdf_source/1` — `Ecto.Multi` トランザクションによるカスケード削除。
- **`PdfSource` スキーマ変更**
  - `image_count` バーチャルフィールドを追加。
- **Lab 専用 CSS (`lab.css`) の追加**
  - プロジェクトカード・画像グリッド・ステータスバッジ・ボタン等のスタイルを定義。
  - Harvest Gold アクセントカラーによるホバーエフェクト。
  - モバイルレスポンシブ対応。
- **ルーター変更**
  - `/lab` → `LabLive.Index`（プロジェクト一覧）に変更。
  - `/lab/upload` → `InspectorLive.Upload`（アップロード画面の URL 変更）。
  - `/lab/projects/:id` → `LabLive.Show`（新規）。

### ⚡ パフォーマンス改善
- **Admin Dashboard の非同期データロード**
  - `mount/3` で空リストを即返却し、`handle_info(:load_images, ...)` でバックグラウンドロード。ローディングスピナー UI を追加。
- **削除操作のローカルステート更新**
  - 単体削除・一括削除後に全件 `list_extracted_images/1` を再取得する処理を廃止。`Enum.reject` によるローカルフィルタリングに置換し、レスポンスを高速化。
- **`list_extracted_images/1` のクエリ最適化**
  - `Repo.preload(:owner)` を後処理から Ecto クエリ内の `preload:` オプションに移動し、N+1 問題を解消。

### 🔐 権限管理 (RBAC) & ユーザー管理
- **ロールベースアクセス制御 (RBAC) の導入**
  - `User` スキーマに `role` カラム (`admin` / `user`) を追加。
  - `Ingestion` コンテキストにおいて、ロールに応じたデータフィルタリングを実装（Admin は全件、一般ユーザーは自身のデータのみ）。
  - 管理者専用の権限チェックプラグをルーターに適用。
- **ユーザー登録モデルの刷新**
  - 公開ユーザー登録を廃止し、管理者による招待/作成モデルへ移行。
  - 管理者専用のユーザー管理画面 (`/admin/users`) を実装。
  - ユーザー削除機能の実装（自分自身の削除防止ロジック付き）。
- **認証体験の改善**
  - メール確認ステップをスキップし、即時ログインを許可するよう調整。

### 🛠️ 管理者機能 & UI
- **Admin Dashboard の強化**
  - 全ユーザーがアップロードした画像の一覧表示・管理に対応。
  - **一括削除（Bulk Delete）機能**の実装。複数項目を選択して DB レコードと物理ファイルを一括削除可能に。
  - 共通の管理者用タブレイアウト (`AdminLayout`) を導入し、ダッシュボード・ユーザー管理・レビュー画面間のナビゲーションを統合。
- **UI コンポーネントのクリーンアップ**
  - デフォルトの Phoenix ヘッダーを廃止し、アプリ固有のミニマルなナビゲーションへ移行。
  - モダルウィンドウの安定性向上（LiveView の DOM パッチによる意図しないクローズを防止）。

---

## [0.2.7] - 2026-02-17

### 🔐 認証システム (phx.gen.auth)
- **ユーザー認証基盤の全面導入**
  - `phx.gen.auth` によるセッションベース認証を実装（`bcrypt_elixir`）。
  - `User` / `UserToken` スキーマ、`Accounts` コンテキストを追加。
  - ログイン (`/users/log-in`)、ユーザー登録 (`/users/register`)、設定 (`/users/settings`) の各画面を実装。
  - マイグレーション: `create_users_auth_tables`
- **ルーター保護**
  - `/lab/*` および `/admin/*` スコープに `require_authenticated_user` プラグを適用。
  - 未ログインユーザーはログイン画面にリダイレクト。
- **グローバルナビゲーションバー**
  - `root.html.heex` にアプリ共通のナビバーを追加（Deep Indigo & Harvest Gold テーマ）。
  - ログイン状態に応じてメールアドレス・設定・ログアウト / 登録・ログインを動的に表示。
- **シードデータ**
  - `seeds.exs` にデフォルト管理者ユーザー (`admin@example.com` / `password1234`) の自動作成処理を追加。

### 👥 所有者/作業者モデル
- **`ExtractedImage` に所有権カラムを追加**
  - `owner_id` — アップロードした人（所有者）
  - `worker_id` — 現在編集中の人（作業者）
  - `list_all_images_for_lab/1` が `owner_id` / `worker_id` によるフィルタに対応。
  - マイグレーション: `add_ownership_to_extracted_images`

### ⚙️ Pipeline 並行安全性の改善
- **ジョブ固有一時ディレクトリの導入**
  - PDF 変換時にジョブごとのユニーク一時ディレクトリ (`alchemiiif_job_{uuid}`) を使用。
  - `try/after` パターンで一時ディレクトリの確実なクリーンアップを保証。
  - 並行実行される複数パイプラインジョブ間でのファイル衝突を防止。

### 🐛 バグ修正 & 安定性向上
- **抽出画像の並び順を保証**
  - `Ingestion.list_extracted_images/1` に `page_number` 昇順のソート条件を追加。
  - データベースの挿入順序に依存せず、常にページ順で画像が取得されるよう修正。
- **テストデータの整合性向上**
  - `ingestion_test.exs` において、ラベル形式（`fig-{number}-{number}`）とユニーク制約を遵守するようテストデータを修正。


### 🛡️ データ整合性 & 排他制御
- **楽観的ロック (Optimistic Locking) の導入**
  - `extracted_images` テーブルに `lock_version` カラムを追加。
  - 同時編集時の競合を検知し、`StaleEntryError` をハンドリング。
  - 競合発生時はユーザーにアラートを表示し、上書きを防止 ("Someone else has updated this image...")。
  - マイグレーション: `add_lock_version_to_extracted_images`

### 🎨 UI 改善
- **却下（Rejected）リストの視認性向上**
  - "Fix Required" タブのリストレイアウトを刷新。
  - レビューコメントを独立した行（2行目）に表示し、長いコメントも全文表示可能に。
  - 視覚的な分離（背景色・ボーダー）により、修正理由を明確化。


### 🖼️ IIIF Presentation API 3.0 — PdfSource 単位 Manifest
- **PdfSource（資料）単位の IIIF Manifest 生成を実装**
  - エンドポイント: `GET /iiif/presentation/:source_id/manifest`
  - PdfSource に紐づく公開済み（`published`）画像を page_number 昇順で Canvas に集約
  - Canvas のサイズは `geometry` の `width`/`height` から取得（フォールバック: 1000×1000）
  - CORS ヘッダー・`application/ld+json` Content-Type に対応
  - Mirador 等の標準 IIIF ビューアで閲覧可能

### 🔄 Fix & Resubmit ワークフロー
- **差し戻し・再提出フローを実装**
  - `rejected` ステータスを `extracted_images.status` に追加（`draft` / `pending_review` / **`rejected`** / `published` / `deleted`）
  - `review_comment` カラムを追加（差し戻し理由の専用保存。従来の caption 追記方式を廃止）
  - `Ingestion.resubmit_image/1` — 再提出（`rejected` → `pending_review`、`review_comment` クリア）
  - `Ingestion.list_rejected_images/0` — 差し戻し済み画像一覧
  - Upload 画面（Step 1）に「要修正（差し戻し）」タブを追加
  - Label 画面（Step 4）に差し戻しアラートと「再提出する」ボタンを実装
  - マイグレーション: `add_review_comment_and_rejected_status`

### 📁 ファイルバージョニング
- **アップロードファイル名にタイムスタンプを付与**
  - `filename-{unix_timestamp}.ext` 形式でブラウザキャッシュ衝突を防止
  - 同名ファイルの再アップロード時にも一意性を保証

### 🧹 開発環境: アップロードディレクトリの自動クリーンアップ
- `seeds.exs` に `priv/static/uploads` の自動削除・再作成処理を追加
  - `Mix.env() == :dev` の場合のみ実行
  - DB リセット時の「ゴーストデータ」（孤立ファイル）を防止

### 🛠️ コンテキスト追加
- `Ingestion.list_published_images_by_source/1` を追加（IIIF Manifest 用）
- `Ingestion.resubmit_image/1` を追加（再提出用）
- `Ingestion.list_rejected_images/0` を追加（要修正タブ用）

---

## [0.2.5] - 2026-02-14

### 🖼️ ギャラリー画像拡大モーダル
- **クリックで拡大表示モーダルを実装**
  - ギャラリーカードをクリックすると、SVG `viewBox` を使用した高精度な拡大表示モーダルを表示。
  - `Esc` キーまたは背景クリックでモーダルを閉じる操作に統一（閉じるボタンは廃止）。
  - 検索バー上に使用方法ガイド（「図版をクリックして拡大表示 | Esc キーで閉じる」）を追加。

### 🐛 UI 安定化: カードホバーちらつき修正
- **ギャラリー (`gallery.css`) および管理画面 (`admin-review.css`) のカードホバーエフェクトを安定化**
  - `transform: translateY()` や `scale()` によるちらつきを解消。
  - ホバー時は `border-color` の変更のみに簡素化。
  - `will-change: transform` を追加し GPU レンダリングヒントを付与。
  - 画像の `transform: scale(1.05)` ホバーエフェクトを撤廃し、安定した表示を確保。
- **Masonry レイアウト (Pinterest 風グリッド)**
  - CSS Multi-column を採用し、アスペクト比の異なる画像を隙間なく自然に配置。
  - `break-inside: avoid` によりカードの途切れを防止。

---

## [0.2.4] - 2026-02-14

### 🐛 重大バグ修正: ゴーストレコード & データ消失
- **Write-on-Action ポリシーの導入**
  - Browse（Step 2）でページ選択時に `ExtractedImage` レコードを自動作成していた問題を修正。
  - レコードは Crop（Step 3）でユーザーがダブルクリックでクロップを保存した時に初めて作成されるように変更。
- **Crop ルーティングの変更**
  - `/lab/crop/:image_id` → `/lab/crop/:pdf_source_id/:page_number` に変更。
  - Crop 画面は既存レコードがあればロードし、なければ `save_crop` 時に新規作成。
- **Label での geometry バリデーション追加**
  - geometry（クロップ範囲）が未設定の場合、保存をブロックするバリデーションを追加。
- **Admin Review の壊れたレコードフィルタリング**
  - `list_pending_review_images` クエリに `image_path`/`geometry` の nil チェックを追加。

### ⚠️ 破壊的変更
- Crop 画面の URL パターンが変更されました（`/lab/crop/:image_id` → `/lab/crop/:pdf_source_id/:page_number`）。

---

## [0.2.3] - 2026-02-14

### 🎨 UI & レンダリング改善
- **SVG `viewBox` 方式による精密なクロップ表示を採用**
  - 公開ギャラリー (`/gallery`) および管理画面 (`/admin/review`) のカードにおいて、アスペクト比を維持した精密なプレビューを実現。
  - 背景をダークネイビーに統一し、余白が発生した場合も視覚的な整合性を維持。
- **ナッジコントロール（D-Pad）のスタイル刷新**
  - ゴールド枠＋透明背景のデザインに変更し、視認性とモダンな操作感を向上。
  - ホバー時にゴールドで塗りつぶされるインタラクティブなフィードバックを追加。

### 🛠️ 機能追加
- **管理画面での図版削除機能の実装**
  - `/admin/review` に「削除（ソフトデリート）」ボタンを追加。誤登録エントリの論理削除が可能に。
- **PTIF 生成の自動化プロセス改善**
  - ラベリング完了（Step 4: Save & Finish）時に、PTIF 生成ジョブをバックグラウンドで自動開始するよう改善。
- **ラベルのユニーク制約バリデーションの実装**
  - 同一 PDF 内でのラベル（図番号等）の重複をリアルタイムで検出し、警告を表示。
  - 重複がある場合は既存レコードへの編集リンクを表示し、データの整合性をサポート。
- **高解像度クロップ画像のダウンロード機能**
  - 公開ギャラリーに「ダウンロード」ボタンを追加。
  - 遺跡名とラベルを組み合わせたセマンティックな日本語ファイル名で保存可能。

### 🎮 操作性向上
- **クロップ保存のダブルクリック操作を導入**
  - クロップ範囲の決定（Step 3）において、選択範囲のダブルクリック（またはダブルタップ）による明示的な保存操作を導入。
  - 意図しない座標の保存を防止し、より確実な操作体験を提供。

---

## [0.2.2] - 2026-02-13

### 🎨 UI & テーマ
- **Admin Review Dashboard (`/admin/review`) を「新潟インディゴ＆ハーベストゴールド」テーマに対応**
  - 公開ギャラリーと視覚的に統一されたダークテーマ環境
  - ステータスに応じたカードボーダー（Pending: Gold, Approved: Green）
  - 高コントラストな Approve/Reject ボタン（60×60px）
  - ダークテーマに最適化された Inspector Panel とモーダル

### 🎮 操作性改善 (D-Pad)
- **Nudge コントロールを D-Pad (Directional Pad) レイアウトに刷新**
  - 3×3 CSS Grid による直感的な配置
  - ボタンサイズを 64×64px に拡大し、誤操作を防止
  - ナッジ量を 5px → 10px に変更
  - キーボードの矢印キーによる操作に対応（`phx-window-keydown`）
  - Undo ボタンを D-Pad 中央に統合

### ✂️ クロップ & レンダリング改善
- **Label 画面でのクロップ表示を SVG 方式に移行**
  - CSS スケールに依存しない、より精密なクロッププレビューを実現
- **提出プロセスの改善**
  - 保存・提出時にアイテムのステータスを自動的に `pending_review` へ更新

### 🛡️ セキュリティ & 品質
- **セキュリティ脆弱性の修正 (Sobelow)**
  - `pdf_processor`, `pipeline`, `image_controller`, `upload` におけるディレクトリトラバーサルおよび XSS リスクの低減
- **`mix review` パイプラインのパス**
  - 全チェック（Compile, Credo, Sobelow, Dialyzer）を通過

---

## [0.2.1] - 2026-02-13 (Retrospective)

### ✂️ クロップ機能の基礎改善

#### 変更

- **Cropper.js を廃止し、オリジナルの JavaScript Hook (`ImageSelection`) に移行**
  - CSS スケール（`object-fit: contain`）を考慮した正確な座標計算の実装
  - SVG オーバーレイの表示制御を JS 側に移行し、LiveView 更新時のチラつきや座標の跳びを解消
  - Harvest Gold テーマに合わせた選択範囲の視覚的フィードバックの強化

---

## [0.2.0] - 2026-02-11

### 🏛️ ランディングページ刷新 — デジタルミュージアムの入口

#### 追加

- **ランディングページ（`/`）を「新潟インディゴ＆ハーベストゴールド」テーマに全面刷新**
  - Deep Navy/Indigo (`#001f3f`) 背景 + Harvest Gold (`#d4af37`) アクセント
  - CTA ボタン「Enter the Digital Gallery」→ `/gallery` への一本道ナビゲーション
  - 最小 60×60px タッチターゲット（WM 70 認知アクセシビリティ対応）
  - ミニマリストフッターに `/lab`・`/admin` リンクを控えめ配置

#### 変更

- **ルーター構成の整理**
  - 公開スコープ（`/`, `/gallery`）と 内部スコープ（`/lab/*`）を分離
  - 将来の認証プラグ追加に備えた構造化
- **Tailwind CSS v4 `@source` ディレクティブ追加**
  - `.heex` テンプレートの自動スキャン対応

---

## [0.1.2] - 2026-02-10

### 🛡️ Admin Review Dashboard

#### 追加

- **管理者レビュー機能 (`/admin/review`)**
  - 公開前の最終品質ゲートとして機能
  - Nudge Inspector による詳細確認とクロップ微調整
  - Validation Badge による自動チェック結果表示
  - 承認 (`published`) / 差し戻し (`draft`) のステータス管理
  - Optimistic UI によるスムーズな操作体験

## [0.1.1] - 2026-02-10

### 🎨 UI テーマ更新

#### 追加

- **公開ギャラリーテーマ: 新潟インディゴ＆ハーベストゴールド**
  - Deep Sea Indigo (`#1A2C42`) 背景によるダークテーマ化
  - Harvest Gold (`#E6B422`) アクセントカラーで操作フィードバック
  - Mist Grey (`#E0E0E0`) テキストで WCAG AAA 準拠のコントラスト比 (≈ 10.4:1)
  - ギャラリー専用カード・検索バー・フィルターチップスのダークスタイル適用
  - フィルターチップの `min-height` を 48px → 60px に引き上げ (WM 70 対応)
  - Hover/Active に Gold パレットの非言語フィードバック実装
  - CSS 変数 + `.gallery-container` スコープで Lab/Admin 画面に影響なし (Zero-Regression)

---

## [0.1.0] - 2026-02-09

### 🎉 初回リリース

#### 追加

- **Manual Inspector ウィザード（全5ステップ）**
  - Step 1: PDF アップロード + 自動 PNG 変換 (pdftoppm 300 DPI)
  - Step 2: サムネイルグリッドによるページ選択
  - Step 3: Cropper.js によるマニュアルクロップ + Nudge コントロール
  - Step 4: ラベリング（キャプション・ラベル・遺跡名・時代・遺物種別の手入力）
  - Step 5: レビュー提出（PTIF 自動生成 + IIIF Manifest 登録）
  - 共通ウィザードコンポーネント (`wizard_components.ex`)

- **IIIF サーバー**
  - Image API v3.0 (`/iiif/image/:identifier/...`)
  - Presentation API v3.0 (`/iiif/manifest/:identifier`)
  - info.json エンドポイント
  - タイルキャッシュ機構

- **検索機能**
  - 全文検索コンテキスト (`AlchemIiif.Search`)
  - 検索用 LiveView (`SearchLive`)
  - `extracted_images` への検索フィールド追加マイグレーション

- **Stage-Gate ワークフロー**
  - Lab (内部) / Gallery (公開) の分離
  - 承認ワークフロー LiveView (`ApprovalLive`)
  - ギャラリー LiveView (`GalleryLive`)
  - `extracted_images` へのステータスカラム追加マイグレーション

- **データベース**
  - PostgreSQL + JSONB メタデータ
  - `pdf_sources`, `extracted_images`, `iiif_manifests` テーブル

- **認知アクセシビリティ**
  - 最小 60×60px のタッチターゲット
  - 高コントラストカラーパレット
  - ウィザードパターンによる線形フロー
  - 即時フィードバック

- **テスト**
  - コンテキスト・スキーマ・コントローラ・LiveView のテスト
  - テスト用ファクトリ (`test/support/factory.ex`)

- **並列処理パイプライン**
  - リソース適応型並列処理 (`AlchemIiif.Pipeline`)
  - CPU/メモリ自動検出・動的並列度調整 (`AlchemIiif.Pipeline.ResourceMonitor`)
  - メモリガード（空きメモリ 20% 未満で並列度縮小）
  - PubSub リアルタイム進捗通知

- **品質チェック (`mix review`)**
  - Credo コードスタイル検査 (`--strict`)
  - Sobelow セキュリティ解析
  - Dialyzer 型チェック
  - PASS/FAIL サマリータスク (`mix review.summary`)

- **デプロイ**
  - マルチステージ Dockerfile (libvips + poppler-utils)
  - OTP リリースサポート
  - ヘルスチェックエンドポイント (`/api/health`)
