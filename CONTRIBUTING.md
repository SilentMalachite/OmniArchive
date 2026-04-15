# Contributing to OmniArchive / 開発参加ガイドライン

We welcome contributions from digital humanities researchers, archivists, and developers.
OmniArchive prioritizes cognitive accessibility — if you are new to open source contribution,
you are especially welcome. Issues labeled `good first issue` are maintained in both English
and Japanese to lower the barrier to participation.

デジタル人文学の研究者・アーキビスト・開発者からの貢献を歓迎します。
このプロジェクトは認知アクセシビリティを最優先にしています。
`good first issue` ラベルの付いた Issue は英日両語で記述されており、
初めてオープンソースに参加する方でも取り組みやすくなっています。

---

## 🏁 Getting Started / はじめに

### Setting Up the Development Environment / 開発環境のセットアップ

Fork and clone the repository, then follow these steps:

1. Clone the repository / リポジトリをフォークしてクローン

```bash
git clone https://github.com/SilentMalachite/OmniArchive.git
cd OmniArchive
```

2. Install dependencies / 依存パッケージをインストール

```bash
mix setup
```

3. Start the development server / 開発サーバーを起動

```bash
mix phx.server
```

4. Run the tests / テストを実行

```bash
mix test
```

5. Run quality checks / 品質チェックを実行

```bash
mix review
```

6. Before starting work, read `AGENTS.md` / 作業前に `AGENTS.md` を確認

Domain-specific metadata, validation rules, facet labels, and UI copy must not be
hardcoded in shared modules. Place them in `OmniArchive.DomainProfiles.*`.

ドメイン依存の metadata・validation・facet・UI 文言は shared module に直書きせず、
`OmniArchive.DomainProfiles.*` に集約してください。

---

## 📋 Development Process / 開発プロセス

### Branch Strategy / ブランチ戦略

- `main` — stable release (no direct push) / 安定版（直接プッシュ禁止）
- `develop` — integration branch / 開発統合ブランチ
- `feature/*` — new features / 新機能
- `fix/*` — bug fixes / バグ修正
- `docs/*` — documentation updates / ドキュメント更新

### Workflow / ワークフロー

1. Check or create an Issue / Issue を確認または作成
2. Create a branch (`feature/issue-number-summary`) / ブランチを作成 (`feature/issue-番号-概要`)
3. Implement your changes / 変更を実装
4. Add and run tests / テストを追加・実行
5. Open a Pull Request / Pull Request を作成

---

## 🧩 Adding a New Domain Profile / ドメインプロファイルの追加

OmniArchive supports multiple domain profiles through a behavior module. You can add a
new domain — for example, manuscripts, maps, photographs, or architectural drawings —
by following these steps:

OmniArchive はビヘイビアモジュールによる複数のドメインプロファイルをサポートしています。
古文書・地図・写真・建築図面など、新しいドメインを追加するには以下の手順に従ってください。

#### Option A: Elixir module / Elixir モジュールで追加

1. Create `lib/omni_archive/domain_profiles/your_domain.ex`
2. Implement the `OmniArchive.DomainProfile` behavior
3. Define metadata fields, validation rules, and facet labels
4. Register in `config/config.exs`:

```elixir
config :omni_archive, domain_profile: OmniArchive.DomainProfiles.YourDomain
```

1. `lib/omni_archive/domain_profiles/your_domain.ex` を作成します
2. `OmniArchive.DomainProfile` ビヘイビアを実装します
3. メタデータフィールド・バリデーションルール・ファセットラベルを定義します
4. `config/config.exs` に登録します

#### Option B: YAML profile (v0.2.23+) / YAML プロファイル（v0.2.23 以降）

Create a YAML file based on the template at `priv/profiles/example_profile.yaml`,
then set the environment variable before starting the server:

`priv/profiles/example_profile.yaml` のテンプレートを参考に YAML ファイルを作成し、
起動前に環境変数を設定します：

```bash
OMNI_ARCHIVE_PROFILE_YAML=/path/to/your_profile.yaml mix phx.server
```

For the full YAML schema reference, see [PROFILES.md](PROFILES.md).

YAML スキーマの詳細は [PROFILES.md](PROFILES.md) を参照してください。

---

## ✅ Coding Standards / コーディング規約

### Elixir

- **Formatter**: always run `mix format` before committing / コミット前に必ず `mix format` を実行
- **Zero warnings**: code must pass `mix compile --warnings-as-errors` / `mix compile --warnings-as-errors` でコンパイルが通ること
- **Documentation**: add `@doc` to all public functions / 公開関数には `@doc` を記述
- **Module docs**: add `@moduledoc` to all modules / `@moduledoc` を記述
- **Comments**: write in Japanese / コメントは日本語で記述

### JavaScript

- **ES6+ syntax**: use `const`/`let`, arrow functions, and template literals / `const`/`let`、アロー関数、テンプレートリテラルを使用
- **Comments**: write in Japanese / コメントは日本語で記述

### CSS

- **CSS variables**: avoid hardcoded values; use `:root` variables / ハードコードを避け、`:root` の変数を使用
- **Accessibility**: buttons must be at least 60×60px with WCAG AA contrast / ボタンは最小 60×60px、WCAG AA 以上のコントラスト比

---

## ♿ Accessibility Requirements / アクセシビリティ要件

Cognitive accessibility is a core design principle of OmniArchive. Before opening a
Pull Request, confirm all of the following:

このプロジェクトでは**認知アクセシビリティ**を最優先しています。
Pull Request を作成する際は、以下を確認してください：

- [ ] Button size is at least 60×60px / ボタンサイズが最小 60×60px であること
- [ ] Color contrast meets WCAG AA / カラーコントラストが WCAG AA 基準を満たすこと
- [ ] All interactive elements have `aria-label` / 全ての操作要素に `aria-label` が設定されていること
- [ ] Destructive actions have a confirmation dialog / 破壊的操作には確認ダイアログがあること
- [ ] Error messages are clear and specific / エラーメッセージが明確で具体的であること
- [ ] No hidden menus or gesture-only interactions / 隠しメニューやジェスチャーのみの操作がないこと

---

## 🧪 Testing / テスト

### Running Tests / テストの実行

```bash
# Run all tests / 全テスト
mix test

# Specific file / 特定のファイル
mix test test/omni_archive/ingestion_test.exs
mix test test/omni_archive/search_test.exs

# LiveView tests / LiveView テスト
mix test test/omni_archive_web/live/

# Controller tests / コントローラーテスト
mix test test/omni_archive_web/controllers/

# Specific line / 特定のテスト (行番号指定)
mix test test/omni_archive/ingestion_test.exs:42
```

### Test Guidelines / テスト作成のガイドライン

- Add tests for every new feature / 新機能には必ずテストを追加
- Test Ecto schema validations / Ecto スキーマのバリデーションテスト
- Test business logic in context modules / コンテキストモジュールのビジネスロジックテスト
- Write controller integration tests / コントローラーの統合テスト
- Write LiveView render and event tests / LiveView のレンダリング・イベントテスト
- Use factories in `test/support/factory.ex` for test data / テストデータは `test/support/factory.ex` のファクトリを使用
- Cover edge cases / エッジケースのカバー

---

## 📝 Commit Messages / コミットメッセージ

Follow the [Conventional Commits](https://www.conventionalcommits.org/) format:

[Conventional Commits](https://www.conventionalcommits.org/) に準拠してください：

```
<type>(<scope>): <description>

[body]

[footer]
```

### Types / タイプ

| Type | Description / 説明 |
|:---|:---|
| `feat` | New feature / 新機能 |
| `fix` | Bug fix / バグ修正 |
| `docs` | Documentation / ドキュメント |
| `style` | Formatting only (no logic change) / 書式の変更 (コードの意味に影響しない) |
| `refactor` | Refactoring / リファクタリング |
| `test` | Add or update tests / テストの追加・修正 |
| `chore` | Build process or tooling changes / ビルドプロセスや補助ツールの変更 |

### Example / 例

```
feat(inspector): add sensitivity setting for Nudge control

Adds a settings panel allowing users to adjust the Nudge button
move distance (px). Default is 5px.

Closes #123
```

---

## 🐛 Bug Reports / バグ報告

When opening an Issue, please include:

Issue を作成する際は、以下の情報を含めてください：

1. **Environment / 環境**: OS, browser, Elixir/Phoenix version
2. **Steps to reproduce / 再現手順**: specific steps to trigger the problem
3. **Expected behavior / 期待される動作**: what should happen
4. **Actual behavior / 実際の動作**: what happened instead
5. **Screenshots / スクリーンショット**: attach if possible / 可能であれば添付

---

## 📬 Pull Request

### Pre-submission Checklist / 作成前チェックリスト

```bash
mix review     # compile + credo + sobelow + dialyzer
mix precommit  # compile + deps + format + test
```

- [ ] `mix review` passes (compile, Credo, Sobelow, Dialyzer) / `mix review` が通る
- [ ] `mix precommit` passes (compile, deps, format, test) / `mix precommit` が通る
- [ ] Documentation updated where needed / 必要に応じてドキュメントを更新した
- [ ] Accessibility requirements met / アクセシビリティ要件を満たしている

### Review Process / レビュープロセス

1. All CI checks must pass / CI チェックが全て通ること
2. At least one reviewer approval / 最低 1 名のレビュー承認
3. Conflicts resolved / コンフリクトが解消されていること

---

## 💬 Community / コミュニティ

- **IIIF Slack**: `#iiif` channel — for IIIF-specific discussion
- **GitHub Issues**: bug reports and feature requests (English or Japanese / 英語・日本語どちらでも可)

---

## 📜 License / ライセンス

Contributions are accepted under the **Apache License 2.0**.
See [LICENSE](LICENSE) for details.

貢献されたコードは **Apache License 2.0** のもとで公開されます。
詳細は [LICENSE](LICENSE) を参照してください。
