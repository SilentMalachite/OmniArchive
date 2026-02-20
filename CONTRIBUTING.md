# 開発参加ガイドライン (Contributing)

AlchemIIIF への貢献をご検討いただきありがとうございます！

---

## 🏁 はじめに

### 開発環境のセットアップ

1. リポジトリをフォークしてクローン

```bash
git clone https://github.com/SilentMalachite/AlchemIIIF.git
cd AlchemIIIF
```

2. 依存パッケージをインストール

```bash
mix setup
```

3. 開発サーバーを起動

```bash
mix phx.server
```

4. テストを実行

```bash
mix test
```

4. 品質チェックを実行

```bash
mix review
```

---

## 📋 開発プロセス

### ブランチ戦略

- `main` — 安定版（直接プッシュ禁止）
- `develop` — 開発統合ブランチ
- `feature/*` — 新機能
- `fix/*` — バグ修正
- `docs/*` — ドキュメント更新

### ワークフロー

1. Issue を確認または作成
2. ブランチを作成 (`feature/issue-番号-概要`)
3. 変更を実装
4. テストを追加・実行
5. Pull Request を作成

---

## ✅ コーディング規約

### Elixir

- **フォーマッタ**: `mix format` を必ず実行
- **警告ゼロ**: `mix compile --warnings-as-errors` でコンパイルが通ること
- **ドキュメント**: 公開関数には `@doc` を記述
- **モジュールドキュメント**: `@moduledoc` を記述
- **コメント**: 日本語で記述

### JavaScript

- **ES6+ 構文**: `const`/`let`、アロー関数、テンプレートリテラル
- **コメント**: 日本語で記述

### CSS

- **CSS 変数**: ハードコードを避け、`:root` の変数を使用
- **アクセシビリティ**: ボタンは最小 60×60px、WCAG AA 以上のコントラスト比

---

## ♿ アクセシビリティ要件

このプロジェクトでは**認知アクセシビリティ**を最優先しています。
Pull Request を作成する際は、以下を確認してください：

- [ ] ボタンサイズが最小 60×60px であること
- [ ] カラーコントラストが WCAG AA 基準を満たすこと
- [ ] 全ての操作要素に `aria-label` が設定されていること
- [ ] 破壊的操作には確認ダイアログがあること
- [ ] エラーメッセージが明確で具体的であること
- [ ] 隠しメニューやジェスチャーのみの操作がないこと

---

## 🧪 テスト

### テストの実行

```bash
# 全テスト
mix test

# 特定のファイル
mix test test/alchem_iiif/ingestion_test.exs
mix test test/alchem_iiif/search_test.exs

# LiveView テスト
mix test test/alchem_iiif_web/live/

# コントローラーテスト
mix test test/alchem_iiif_web/controllers/

# 特定のテスト (行番号指定)
mix test test/alchem_iiif/ingestion_test.exs:42
```

### テスト作成のガイドライン

- 新機能には必ずテストを追加
- Ecto スキーマのバリデーションテスト
- コンテキストモジュールのビジネスロジックテスト
- コントローラーの統合テスト
- LiveView のレンダリング・イベントテスト
- テストデータは `test/support/factory.ex` のファクトリを使用
- エッジケースのカバー

---

## 📝 コミットメッセージ

[Conventional Commits](https://www.conventionalcommits.org/) に準拠してください：

```
<type>(<scope>): <description>

[本文]

[フッター]
```

### タイプ

| タイプ | 説明 |
|:---|:---|
| `feat` | 新機能 |
| `fix` | バグ修正 |
| `docs` | ドキュメント |
| `style` | 書式の変更 (コードの意味に影響しない) |
| `refactor` | リファクタリング |
| `test` | テストの追加・修正 |
| `chore` | ビルドプロセスや補助ツールの変更 |

### 例

```
feat(inspector): Nudge コントロールの感度設定を追加

ユーザーが Nudge ボタンの移動量 (px) を調整できる
設定パネルを追加しました。デフォルトは 5px です。

Closes #123
```

---

## 🐛 バグ報告

Issue を作成する際は、以下の情報を含めてください：

1. **環境**: OS、ブラウザ、Elixir/Phoenix バージョン
2. **再現手順**: 問題を再現するための具体的な手順
3. **期待される動作**: 本来どう動作すべきか
4. **実際の動作**: 何が起きたか
5. **スクリーンショット**: 可能であれば添付

---

## 📬 Pull Request

### 作成前チェックリスト

```bash
# 以下のコマンドで品質チェックが可能です
mix review       # 推奨: compile + credo + sobelow + dialyzer を一括実行
mix precommit    # compile + deps + format + test を一括実行
```

- [ ] `mix review` が通る（コンパイル, Credo, Sobelow, Dialyzer）
- [ ] `mix precommit` が通る（compile, deps, format, test）
- [ ] 必要に応じてドキュメントを更新した
- [ ] アクセシビリティ要件を満たしている

### レビュープロセス

1. CI チェックが全て通ること
2. 最低 1 名のレビュー承認
3. コンフリクトが解消されていること

---

## 📜 ライセンス

貢献されたコードは [MIT License](LICENSE) のもとで公開されます。
