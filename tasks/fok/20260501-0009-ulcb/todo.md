# todo (Step 4 計画)

採用案: investigation.md §5-A `@preconcurrency import WhisperKit`（最小変更）

- [ ] T1: `WhisperManager.swift` の WhisperKit import を `@preconcurrency import` に変更
    - 対象: `/Users/jonji/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift`（先頭の `import WhisperKit` 行）
    - 期待挙動: 222 行目の `sending 'whisperKit' risks causing data races` 警告/エラーが消える。文字起こしの実行時挙動は不変。
    - 備考: 他ファイル（TypeToTalkApp.swift / HUDView.swift / SettingsView.swift）は `whisperKit != nil` 判定のみで sending 警告は出ていないため触らない。最小限ルール厳守。

- [ ] T2: `./scripts/build_app.sh Debug` で BUILD SUCCEEDED を確認
    - 対象: ビルド全体（Swift 6 strict concurrency 警告ゼロ）
    - 期待挙動: `Built app: /tmp/TypeToTalkDerivedData/Build/Products/Debug/TypeToTalk.app` が出力される。
    - 備考: 他に同種の sending 警告が出たら T1 と同じスコープ（WhisperManager.swift 内）で対応可否を判断。範囲外の警告が出た場合はシアに戻す。

- [ ] T3: `project.yml` の CURRENT_PROJECT_VERSION を bump
    - 対象: `/Users/jonji/GitHub/tamekuniz/TTT/project.yml`
    - 期待挙動: TTT 規約「毎コミット必ず bump」に従い、現在値から +1。
    - 備考: feedback_ttt_always_bump_version、feedback_fok_step8_version_bump 準拠。Step 8 で実施するが、計画として明示しておく。
