# Step 4 進捗: Settings 画面にビルドナンバー YYYYMMDDA 形式を表示

**タスクID**: 20260425-1942-s9l9
**現在のステップ**: Step 4 計画完了

---

## ステップ別進捗

### Step 1-3（完了）
- [x] Step 1: 要件定義
- [x] Step 2: スコープ確定
- [x] Step 3: 調査（ミカン）— investigation.md 完成

### Step 4: 計画（メロン）
- [x] investigation.md を Read
- [x] シア指定の方針（採用案 A、.fok-target 新設、文言日本語統一、xcodegen 再生成必須）を反映
- [x] todo.md 作成（Task 1 + Task 2 の 2 タスク構成）
- [x] progress.md 作成（本ファイル）
- **完了日時**: 2026-04-25

### Step 5: 計画レビュー（未実施）
- [ ] todo.md をレビュー小人ちゃんが検証
- [ ] OK なら Step 6 へ、NG なら Step 4 へ差し戻し

### Step 6: 実装（完了）
- [x] Task 1: `.fok-target` 新設 + `project.yml` `CURRENT_PROJECT_VERSION: "20260425A"` 文字列化 + xcodegen 再生成成功
- [x] Task 2: `SettingsView.swift` を `appVersionLine` / `appBuildLine` に分割。VStack(alignment: .trailing, spacing: 2) で 2行表示化

### Step 7: 検証（完了）
- [x] xcodebuild BUILD SUCCEEDED
- [x] ビルド成果物 Info.plist の CFBundleVersion = "20260425A" 確認
- [x] appVersionText 残存ゼロ確認
- [x] 品質セルフチェック OK（optional 取り扱い適切、フォールバック明示）

### Step 8: バージョン更新（実施済み）
- 今回サイクルで CURRENT_PROJECT_VERSION="20260425A" を新規セット（基盤整備）
- 次サイクル以降は .fok-target を読んで Step 8 でバージョン更新する流れ
- 実機確認: ズンジー側で Settings 右下の「バージョン 0.1.0」「ビルド 20260425A」2行表示を目視

### Step 9: コミット
- メッセージ案: `[フォK] feat: ビルドナンバー YYYYMMDDA 形式を Settings に表示`

---

## 採用方針サマリー

| 項目 | 採用内容 |
|------|----------|
| 案 | A（Info.plist + Bundle.main） |
| project.yml 変更 | `CURRENT_PROJECT_VERSION: "20260425A"`（文字列化） |
| Info.plist 変更 | なし（既存 `$(CURRENT_PROJECT_VERSION)` 置換のまま） |
| Settings 画面 | 2行表示（`バージョン x.x.x` / `ビルド YYYYMMDDA`） |
| 文言 | 日本語統一（既存 Settings ラベルに合わせる） |
| .fok-target | 新規作成（VERSION_FILE_1_PATH=project.yml） |
| xcodegen | project.yml 変更後に必ず実行 |
| App Store リスク | 無視（リリース前ローカルアプリ） |

---

## ファイル変更一覧（予定）

| ファイル | 操作 | 内容 |
|----------|------|------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/.fok-target` | 新規 | フォK Step 8 の対象登録（7 項目） |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/project.yml` | 編集 | L13 `CURRENT_PROJECT_VERSION: 1` → `"20260425A"` |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift` | 編集 | `appVersionText` を `appVersionLine` + `appBuildLine` に分割、HStack 内を VStack で 2行構成に変更 |

xcodeproj は `xcodegen generate` で再生成されるため、コミット対象から外すか、リポ運用に従う（不確か — 実装小人ちゃんが既存 .gitignore を確認）。

---

## 不確か事項（Step 5 レビューで再確認）

1. xcodegen が文字列形式 `CURRENT_PROJECT_VERSION` を受け付けるか（要実証）
2. DerivedData ハッシュ部のマシン依存性（.fok-target の DEPLOY_COMMAND が他Macで動くか不明）

これらは Step 6/7 で実証されるため、Step 4 時点では「方針として採用、実証で破綻したら Step 5 差し戻し」とする。
