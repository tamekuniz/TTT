# TODO — TypeToTalkMainView Text 削除

日時: 2026-04-25
作業ID: 20260425-2206-xjfd
ワークフロー: フォK Step 4（プランニング）
プランナー: みかんずら（甲州弁）

## 要件サマリ

`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` の L90–L93 にある下記ブロックを完全削除する。

```swift
Text("ショートカットで呼び出すと、このダイアログを前面に出します。")
    .font(.caption)
    .foregroundStyle(.secondary)
    .multilineTextAlignment(.center)
```

- 対象: Text 本体 1 行 + 修飾子 3 行（`.font(.caption)`, `.foregroundStyle(.secondary)`, `.multilineTextAlignment(.center)`）= 計 4 行
- 同文言の他箇所参照: なし（grep 結果 1 箇所のみ）
- ローカライズリソース: なし（リテラル定義）
- ビジネスロジック影響: なし（View のみ）

## タスク一覧

### Task 1: Text と修飾子3つを完全削除

- **ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`
- **削除行**: L90–L93（Text 本体 + 修飾子 3 行）
- **手段**: Edit ツール（old_string に L90–L93 の 4 行 + 周辺インデント文脈、new_string は空文字列）
- **削除後の構造**:
  - 親 `VStack(spacing: 18)` の子要素は変更なし
  - 内部 `VStack(spacing: 10)` の子要素は modelStatusRow × 2 のみ（3 → 2）
- **触ってはいけないもの**:
  - 親 VStack の `spacing: 18`、子 VStack の `spacing: 10`
  - `modelStatusRow(...)` 呼び出し（L80–L84, L85–L89）
  - `.padding(20)`, `.frame(width: 360, height: 300)`
  - その他の View 構造・修飾子チェーン

#### 自己検証（Step 5 で実施）

1. ビルド成功確認: `./scripts/build_app.sh`（コンパイルエラーなし）
2. grep 確認: 削除対象文言 `ショートカットで呼び出すと` がリポジトリ全体から消えていること
3. 構文確認: 削除後の VStack(spacing: 10) が modelStatusRow × 2 のみで閉じていること

#### Done 条件

- [ ] Text("ショートカットで呼び出すと、...") とその修飾子 3 つが TypeToTalkApp.swift から削除されている
- [ ] ビルド成功（warning/error なし）
- [ ] grep で同文言が 0 件
- [ ] 削除以外の行に変更なし（diff が L90–L93 の 4 行削除のみ）

## 制約・注意

- **削除以外触らない原則**: investigation.md §6 に明記。modelStatusRow や VStack 構造を変えない
- **修飾子チェーン**: Text と修飾子 3 つは一体として削除（Text を残して修飾子だけ消すのは不可）
- **インデント保持**: 周辺コードのインデント・整形を維持
- **テストファイル**: `ModelSelectionTests.swift`, `AudioRecorderTests.swift` は UI 非依存のため変更不要

## 想定影響

| 項目 | 影響 |
|------|------|
| ビジネスロジック | なし |
| ショートカット動作 | なし（Coordinator 側で定義） |
| ウインドウサイズ | 360×300 維持 |
| spacing | 親 18 / 子 10 ともに維持、要素削除のみ |
| ユニットテスト | 変更不要 |
| ローカライズリソース | 変更不要（リソース化されていない） |

## 次フェーズ予告

- **Step 5（実装＋自己検証）**: 上記 Task 1 を Edit で実行 → ビルド → grep 確認 → progress.md 更新
- **Step 6（レビュー）**: 別Claudeセッションで diff レビュー（削除以外の変更がないこと、構文破損がないことを確認）
- **Step 7（デプロイ）**: 実機 + シミュレータ両方に install（feedback_fok_dual_deploy 準拠）
