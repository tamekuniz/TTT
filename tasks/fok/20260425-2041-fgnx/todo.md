# todo - Bonsai 自動ロード不安定 + ステータス表示食い違い 修正

**サイクルID**: 20260425-2041-fgnx
**対象ファイル**: investigation.md（必読）
**方針**: 問題A・Bを独立した2タスクで1サイクルで処理

---

## タスク一覧

### Task 1: 問題B修正 — Coordinator.formatterStatusText を @Published 化（Whisperパターン適用）

**優先度**: 高（原因確定済み・修正パターン確立済み）

**ファイル**:
- `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

**根本原因**（investigation.md §8.1）:
- `TypeToTalkCoordinator.activeFormatterStatusText` が計算型プロパティ
- `bonsai.statusMessage` が変化しても Coordinator の objectWillChange が発火しない
- → `TypeToTalkMainView` (`@ObservedObject var coordinator`) には伝播せず、設定画面と食い違う

**実装ステップ**:

1. **Coordinator に @Published プロパティを追加**
   ```swift
   @Published private(set) var formatterStatusText: String = "未読込"
   ```
   （初期値は activeFormatterStatusText 計算結果と一致させる。init 末尾で `refreshFormatterStatusText()` を呼ぶ）

2. **`refreshFormatterStatusText()` ヘルパー関数を新設**
   - 既存 `activeFormatterStatusText` の switch ロジックをそのまま移植
   - case .groq, .openAI: `network.isOnline ? "準備完了" : "未接続"`
   - case .bonsai: `bonsai.statusMessage`
   - 結果を `formatterStatusText` に代入

3. **依存元の変化を監視して `refreshFormatterStatusText()` を呼ぶ**
   - 監視対象: `bonsai.statusMessage`, `network.isOnline`, `settings.activeFormatterProvider`（または resolvedFormatterProvider 相当）
   - 実装方式: **Combine sink** を採用（Whisper 修正 848ef06 と同等の意図、ただし Whisper は同一クラス内 didSet なのに対し、こちらは別オブジェクトの @Published を監視するため Combine 必須）
   - init 内で `bonsai.$statusMessage`, `network.$isOnline`, `settings.$<provider>` を sink して `refreshFormatterStatusText()` を呼ぶ
   - 購読は `private var cancellables = Set<AnyCancellable>()` で保持
   - `import Combine` を追加（既存に無ければ）

4. **既存の計算型 `activeFormatterStatusText` を削除**
   - 旧プロパティを残すと参照ミスの温床になるため削除
   - SettingsView 等で参照していないか Grep で確認（investigation.md ではメインのみ参照と記載されているが念のため確認）

5. **TypeToTalkMainView の参照を `coordinator.formatterStatusText` に変更**
   - 行86 (`status: coordinator.activeFormatterStatusText`) → `status: coordinator.formatterStatusText`

**自己検証**:
- ビルド成功
- 起動時、設定画面とメインウインドウの Formatter ステータスが一致すること
- Bonsai 再読込ボタン押下中：両画面で「モデル取得中 XX%」が同期更新されること
- ロード完了後：両画面で「準備完了」表示
- Provider を Groq/OpenAI に切り替え：両画面で「準備完了」or「未接続」が一致

**リスク**:
- Combine 購読の循環参照に注意（sink クロージャ内で `[weak self]` 必須）
- init 内で sink 設定する順序：`refreshFormatterStatusText()` 初回呼び出しは購読登録の後で実行

---

### Task 2: 問題A修正 — Bonsai 自動ロード安定化（タイミング遅延 + Whisperパターン揃え）

**優先度**: 高（実機検証必要、実装小）

**ファイル**:
- `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/BonsaiManager.swift`
- `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

**根本原因仮説**（investigation.md §8.2）:
- 仮説1: `isLocalModelAvailable()` のロジック・パスのバグ（最有力）
- 仮説2: `configureSelectedModel` と `ensureSelectedModelLoaded` の呼び出しタイミング
- 仮説3: `modelsBaseDirectory` の初期化タイミング遅延

**シア指定の方針**:
- **最小修正**: 判定タイミングを `settings.resolvedBonsaiModelID` 確定後に遅らせる
- **健全化**: Whisper の autoLoad パターン（loadState を見て loadIfNeeded）と揃える
- **強化**: 起動時に確実に `Task { await autoLoadIfPossible() }` を呼んで結果を loadState/statusMessage に必ず反映する

**実装ステップ**:

1. **仮説検証 print を仕込む（一時的）**
   - `BonsaiManager.ensureSelectedModelLoaded(modelID:)` 冒頭で:
     ```swift
     print("[Bonsai] ensureSelectedModelLoaded modelID=\(modelID)")
     print("[Bonsai] modelsBaseDirectory=\(modelsBaseDirectory.path)")
     print("[Bonsai] canAutoLoad=\(canAutoLoad), isLocalAvailable=\(isLocalModelAvailable(modelID: modelID))")
     ```
   - 実機で起動 → ログ確認して仮説を絞る
   - 確定後、print を残すか除去するかを判断（基本除去、健全化が成功すれば不要）

2. **modelsBaseDirectory の初期化検証**
   - investigation.md §10.2 によれば `~/.typetotalk/models/<modelID>/`
   - `~` がチルダ展開されているか確認（FileManager.default.homeDirectoryForCurrentUser ベースで構築されているか）
   - 文字列結合で `~/...` をそのまま使っていたらバグ → `homeDirectoryForCurrentUser.appendingPathComponent(...)` に修正

3. **isLocalModelAvailable() の判定ロジック検証**
   - ディレクトリ存在 + 中身が空でないチェック
   - `.DS_Store` だけ入っているケースを除外する必要があるか確認（あるなら除外フィルタ追加）
   - 実モデルファイル名（例: `*.safetensors`, `config.json`）の存在を見る方が堅牢ならそちらに変更

4. **呼び出しタイミング健全化（TypeToTalkApp.swift）**
   - 現状: `synchronizeModelsForCurrentSettings()` 内で `configureSelectedModel(settings.resolvedBonsaiModelID)` → 条件付き `ensureSelectedModelLoaded`
   - 修正後: settings 確定を保証してから呼ぶ。現状でも順序は正しいが、`activeFormatterProvider == .bonsai` ガードで Bonsai が active でない時は自動ロードされない仕様 → これは意図的だが、ユーザー期待と合致しているか investigation.md §3.5 を再確認
   - **強化**: `activeFormatterProvider != .bonsai` でも、設定画面で Bonsai を開いた時に自動ロードされるよう、SettingsView 表示時に `Task { await coordinator.bonsai.ensureSelectedModelLoaded(modelID: settings.resolvedBonsaiModelID) }` を呼ぶ追加導線を検討
   - ただし「自動ロード不安定」現象は Bonsai が active な時に起きとる前提（投稿者報告）。まず active 時の挙動を直す

5. **Whisper パターン揃え検討**
   - Whisper の `ensureSelectedModelLoaded()` 実装を Read して比較
   - loadState ベースで「既に loaded なら skip / loading なら待機 / idle なら開始」の分岐があるか確認
   - Bonsai 側に同等のガードが無ければ追加（重複ロード防止 + 状態反映の確実性）

6. **結果反映の確実性**
   - `ensureSelectedModelLoaded` の catch 句で statusMessage と loadState を両方更新（既存実装あり）
   - 成功時も statusMessage = "準備完了" が確実に立つ経路を確認（`loadModel` 内 行168）

**自己検証**:
- ビルド成功
- 実機: ローカルモデル存在 → アプリ再起動 → 起動直後に「準備完了」表示（手動「再読込」不要）
- 実機: ローカルモデル未存在 → アプリ再起動 → 「未読込」のまま、ネット通信なし、エラーなし
- print ログで isLocalModelAvailable の判定結果を確認（false なら原因特定して再修正）

**不確かさ**:
- 仮説1〜3 のどれが原因かは実機検証次第。最小修正で済むか、ロジック改善が必要かは検証後に確定
- 健全化（Whisperパターン揃え）の必要性も Whisper 実装比較後に判断

**リスク**:
- print 残すと本番ビルドにログが混入 → 検証後は確実に除去 or `#if DEBUG` で囲む
- 自動ロードの強化で意図せずネット通信が発生しないか（`isLocalModelAvailable` ガードを必ず先に通すこと）

---

## 実装順序

1. **Task 1（問題B）を先に実装**: 原因確定済み・パターン確立済みで低リスク。完了後にビルド検証。
2. **Task 2（問題A）を後に実装**: 実機検証ベースで仮説を絞りながら進める。
3. 両タスクのビルド・実機検証が通ったら 1コミットにまとめる（または 2コミット分割）。

**コミット粒度の判断**:
- 修正対象ファイルが重なる（TypeToTalkApp.swift）ので、**1コミットにまとめる**方が rebase しやすい
- コミットメッセージ: `[フォK] fix: Bonsai 自動ロード安定化＋ステータス表示不整合を修正`

---

## 完了条件

- [ ] Task 1 実装完了 + ビルド成功 + 実機検証で食い違い解消確認
- [ ] Task 2 実装完了 + ビルド成功 + 実機検証で自動ロード成功確認
- [ ] 仕様ドキュメント更新（必要があれば）
- [ ] フォK Step 7 で実機 + シミュ両方に install
