# progress - Bonsai 自動ロード不安定 + ステータス表示食い違い 修正

**サイクルID**: 20260425-2041-fgnx
**開始日時**: 2026-04-25 20:41

---

## Step 進行状況

| Step | 内容 | 状態 | 担当 | 完了日時 |
|------|------|------|------|---------|
| Step 1 | 要件確認 | 完了 | シア | 2026-04-25 |
| Step 2 | サイクル準備 | 完了 | シア | 2026-04-25 |
| Step 3 | 調査（investigation.md 作成） | 完了 | 小人ちゃん | 2026-04-25 |
| Step 4 | 計画（todo.md / progress.md 作成） | 進行中 | ぶどう小人ちゃん | 2026-04-25 |
| Step 5 | 実装 | 未着手 | - | - |
| Step 6 | 自己検証（ビルド + 実機） | 未着手 | - | - |
| Step 7 | デプロイ（実機 + シミュ両方） | 未着手 | - | - |
| Step 8 | コミット | 未着手 | - | - |
| Step 9 | 仕様ドキュメント更新 | 未着手 | - | - |

---

## タスク進捗

### Task 1: 問題B修正 — Coordinator.formatterStatusText を @Published 化

- [ ] `import Combine` 追加確認
- [ ] `@Published private(set) var formatterStatusText: String = "未読込"` 追加
- [ ] `private var cancellables = Set<AnyCancellable>()` 追加
- [ ] `refreshFormatterStatusText()` ヘルパー実装
- [ ] init で sink 購読登録（bonsai.$statusMessage, network.$isOnline, settings.$<provider>）
- [ ] init 末尾で `refreshFormatterStatusText()` 初回呼び出し
- [ ] 既存計算型 `activeFormatterStatusText` 削除（参照箇所を Grep で確認後）
- [ ] TypeToTalkMainView 行86 を `coordinator.formatterStatusText` に変更
- [ ] ビルド検証
- [ ] 実機検証: 設定画面とメインウインドウのステータス一致

### Task 2: 問題A修正 — Bonsai 自動ロード安定化

- [ ] 仮説検証 print を BonsaiManager.ensureSelectedModelLoaded に仕込む
- [ ] 実機で起動 → ログ確認して仮説1〜3を絞る
- [ ] modelsBaseDirectory の初期化パス検証（チルダ展開含む）
- [ ] isLocalModelAvailable() のロジック検証（.DS_Store 等の除外要否）
- [ ] WhisperManager.ensureSelectedModelLoaded を Read して比較
- [ ] 呼び出しタイミング健全化（TypeToTalkApp.synchronizeModelsForCurrentSettings）
- [ ] Whisper パターン揃え（loadState ガード等）
- [ ] print 除去 or `#if DEBUG` で囲む
- [ ] ビルド検証
- [ ] 実機検証: ローカルモデル存在で自動ロード成功
- [ ] 実機検証: ローカルモデル未存在でサイレント待機

---

## 不確かさ・要決定事項

- Task 2 の根本原因（仮説1〜3）は実機 print ログで絞る。実装方針は検証後に確定する
- Combine sink で監視する settings 側プロパティ名は実装時に確認（`activeFormatterProvider` の実体プロパティを Grep で特定）
- コミット粒度: 同一ファイル変更が重なるため **1コミット**で進める案を採用（実装時に再判断可）

---

## 完了報告

（Step 5 以降で随時更新）
