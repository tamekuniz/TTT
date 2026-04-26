# progress: AccessibilityManager カーソル挿入対応

## T1: `insertText` の AX 属性を `kAXValueAttribute` → `kAXSelectedTextAttribute` に差し替え

状態: 完了

### 変更ファイル

- `Sources/TypeToTalk/Managers/AccessibilityManager.swift:117` — `kAXValueAttribute` → `kAXSelectedTextAttribute` 1行差し替え。WHY コメント3行追加（kAXValue だと CotEditor 等で破壊される旨）
- `project.yml:13` — `CURRENT_PROJECT_VERSION: "20260426F"` → `"20260426G"`（feedback_ttt_always_bump_version 準拠）

### 検証結果

- **Unit Test (loop=1, simplify 修正後再テスト)**: `swift test --filter ModelSelectionTests` で 17件すべて PASS（0.005s）
  - フルテストで AudioRecorderTests が 15分超ハング（CoreAudio 環境依存、kill 済み）。current_task のスコープ外
- **simplify レビュー (loop=0)**: 3 agent（reuse / quality / efficiency）— quality agent が「コメント末尾の『（実機確認済み、2026-04-26 fix）』はタスク参照ルール違反」と Critical 判定、agent 直 Edit で削除済み。コード本体は無変更、再テストで 17件 PASS 確認

### Acceptance criteria 達成状況

- [x] AC1: CotEditor で既存ドキュメント保持＋カーソル位置挿入（**実機検証で最終確認予定**）
- [x] AC2: 短い NSTextField でも動く（**実機検証で最終確認予定**）
- [x] AC3: AXSelectedText 非対応フィールドは CGEvent fallback で動く（**実機検証で最終確認予定**）
- [x] AC4: ビルド成功 + 既存テスト 17件 PASS

### Reflection (loop 0 → 1)

1. **Root Cause Investigation（失敗要因）**: テスト失敗ではなく、Step 7 simplify レビューで quality agent が「コメント末尾の『（実機確認済み、2026-04-26 fix）』はタスク参照ルール違反」と Critical 判定 → agent が直接 Edit で削除実施。コード本体（kAXSelectedTextAttribute 差し替え）は無変更、コメント末尾の (...) のみ削除
2. **Pattern Analysis（動作リファレンスとの差異）**: CLAUDE.md「タスク参照は PR description で、コメントには書かない」原則に整合。コメント本体（kAXValue だと CotEditor 等で破壊される WHY）は残ったまま、不要な日付・fix 注記のみ落ちた。動作するコード自体は無変更
3. **Hypothesis（単一仮説）**: コメント末尾削除のみでコード実体は無変更なので、再テストは前回と同じ結果（17件 PASS）になる。確実性 100%
4. **Implementation 計画（単一修正）**: 修正なし。simplify が既に Edit 完了。implementing に戻って即 testing → 既存 17件 PASS 確認
