# 進捗ログ (progress.md)

**task_id**: 20260425-1910-7mif
**Step 4 プランナー**: はっさく小人ちゃん（土佐弁担当）

---

## 2026-04-25 Step 4: プランニング完了

### 入力
- investigation.md（Step 3 成果物）を Read 済み
- 根本原因確定: `WhisperManager.statusText` が計算型プロパティ + `@Published` 無し → Coordinator 経由参照のメインウインドウに伝播しない

### 採用方針
- **オプション A**: `WhisperManager.statusText` を `@Published private(set) var` に昇格し、状態遷移ごとに手動セット
- **理由**: 既存の BonsaiManager.statusMessage と同じパターンで一貫性◎、WhisperManager 単体で完結し影響範囲最小

### 不採用オプション
- オプション B（Coordinator 中継）: Combine の sink 管理コスト + 責務漏れ
- オプション C（直接監視）: 既存の Coordinator 集約アーキテクチャを崩す

### TODO 構成
1. WhisperManager のステータス更新点を全列挙（実装前リサーチ）
2. WhisperManager.swift を修正（@Published 化 + refreshStatusText() ヘルパー + didSet）
3. ビルド検証
4. 動作確認（initial / 再読込 / 読込中 / 完了 / モデル切替 の 5 シナリオ）
5. 副作用チェック（Bonsai / 失敗ケース / フルフロー）

### 成果物
- `tasks/fok/20260425-1910-7mif/todo.md`（本計画書）
- `tasks/fok/20260425-1910-7mif/progress.md`（本ファイル）

### 次の Step
- Step 5（実装小人ちゃん）が todo.md の TODO-1 〜 TODO-5 を順に実行

### メモ / 不確かな点
- なし（investigation.md が十分詳細で、修正方針は一意に定まる）

---

## 2026-04-25 Step 6/7: 実装・検証完了

### T1 状態: 完了

### 実装内容（WhisperManager.swift）
- 旧計算型 `statusText` を `@Published private(set) var statusText: String = "未読込"` に変更
- `refreshStatusText()` ヘルパー新設（旧 switch ロジックを完全移植、文言一切変更なし）
- 依存プロパティの didSet で `refreshStatusText()` を呼ぶ網羅化:
  - `whisperKit` / `loadState` / `loadingStatusText` / `loadedModelID`
- `init` 末尾で初期値確定

### 検証結果
- `xcodebuild ... build` で BUILD SUCCEEDED
- 確認ポイント全項目 PASS（@Published 定義、ヘルパー存在、文言保持）
- 品質セルフチェック: 本番で困るレベルの問題なし
- 実機確認: ズンジー側で起動し、メインウインドウのステータス表示が「準備完了」に追従することを目視確認予定
