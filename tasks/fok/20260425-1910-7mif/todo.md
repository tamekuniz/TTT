# Whisper ステータス表示食い違い 修正計画 (todo.md)

**task_id**: 20260425-1910-7mif
**作成者**: はっさく小人ちゃん（土佐弁担当）
**Step**: 4 プランナー
**作成日**: 2026-04-25

---

## 1. 課題サマリー

- **症状**: Whisper モデル読込完了後、Settings 画面では「準備完了」、メインウインドウでは「未読込」のまま
- **根本原因（Step 3 確定）**: `WhisperManager.statusText` が **計算型プロパティ** で `@Published` アノテーションが無いため、Coordinator 経由で参照しているメインウインドウ (`TypeToTalkMainView`) に変化が伝播しない
- **対象ファイル**: `Sources/TypeToTalk/Managers/WhisperManager.swift`（主） / `Sources/TypeToTalk/App/TypeToTalkApp.swift`（参照側、必要なら確認）/ `Sources/TypeToTalk/Views/SettingsView.swift`（参照側、確認のみ）

---

## 2. 採用方針: オプション A（`statusText` を @Published プロパティに昇格）

### 選定理由

investigation.md §6/§7 で示された 3 オプションの比較:

| オプション | 概要 | 採否 | 理由 |
|-----------|------|------|------|
| A: WhisperManager 内で `@Published var statusText` 化 | 計算結果を保持する @Published に変える。状態変化時に手動更新 | **採用** | ・参考実装 BonsaiManager.statusMessage と同じパターン（一貫性◎）<br>・WhisperManager 内で完結（影響範囲最小）<br>・SettingsView / メインウインドウ両方で自動更新 |
| B: Coordinator に `whisperStatusText` 中継 @Published 追加 | Coordinator が whisper.statusText をリスン＆キャッシュ | 不採用 | ・Coordinator に責務が漏れ出す<br>・sink 解除管理など Combine 周りの実装コストが増える<br>・WhisperManager 単体で表示文言の正しさを担保できなくなる |
| C: メインウインドウから WhisperManager を直接 @ObservedObject | Coordinator 中継を省略 | 不採用 | ・既存の Coordinator 集約アーキテクチャを崩す<br>・他 Manager との一貫性低下 |

**結論**: BonsaiManager と同じく「@Published な statusMessage を状態遷移ごとに手動セット」する方式に揃える。設計の一貫性が最優先。

### 実装方針の詳細

1. `WhisperManager.swift` の `statusText` を計算型プロパティから `@Published private(set) var statusText: String = "未読込"` に変更
2. `loadState` を更新するすべての箇所で、新しい `statusText` を計算してセットするヘルパー `private func refreshStatusText()` を導入
3. `loadingStatusText` を更新する箇所、および `whisperKit` / `loadedModelID` / `selectedModelID` が変わって `needsExplicitLoad` が変わりうる箇所でも `refreshStatusText()` を呼ぶ
4. 計算ロジック自体（switch 文の中身）は既存のものをそのままヘルパー側に移植する → 表示文言は一切変えない
5. `loadState` を `@Published` のままにする（外部から KVO したい用途があるかもしれないし、`didSet` で `refreshStatusText()` を呼ぶことで網羅性を担保する）

---

## 3. TODO（実装手順）

### TODO-1: WhisperManager のステータス更新点を全列挙する（実装前リサーチ）

- [ ] `Sources/TypeToTalk/Managers/WhisperManager.swift` を Read で先頭から末尾まで通読
- [ ] `loadState =` または `self.loadState =` に代入する箇所を Grep で全列挙
- [ ] `loadingStatusText =` に代入する箇所を Grep で全列挙
- [ ] `whisperKit =` / `loadedModelID =` に代入する箇所を Grep で全列挙
- [ ] `needsExplicitLoad` の定義を確認し、依存プロパティを把握
- [ ] 列挙結果を progress.md にメモ

**完了条件**: ステータス変化に絡む代入箇所が漏れなく洗い出されている

---

### TODO-2: WhisperManager.swift を修正

- [ ] `statusText` を計算型プロパティから `@Published private(set) var statusText: String = "未読込"` に変更
- [ ] `private func refreshStatusText()` を新設し、現在の switch 文ロジックを移植（戻り値を直接 `self.statusText` に代入する形）
- [ ] `loadState` プロパティに `didSet { refreshStatusText() }` を追加
- [ ] `loadingStatusText` プロパティに `didSet { refreshStatusText() }` を追加
- [ ] `whisperKit` / `loadedModelID` を更新する箇所で `refreshStatusText()` を呼ぶ（needsExplicitLoad が変わるため）
- [ ] `init(...)` 末尾で `refreshStatusText()` を 1 回呼んで初期値を確定する
- [ ] 既存の `statusText` 利用箇所（SettingsView, TypeToTalkMainView）はインターフェース変更なしで動くこと（`var statusText: String` という外形は維持）

**完了条件**: WhisperManager.swift がコンパイルエラーなく、表示文言が既存と同一なまま @Published 経由で配信される

---

### TODO-3: ビルド検証

- [ ] プロジェクトをビルドし、コンパイルエラー / 警告がゼロであることを確認
- [ ] 既存の警告が増えていないことを確認

**完了条件**: クリーンビルド成功

---

### TODO-4: 動作確認（実機 or シミュ。investigation.md §7.1 の手順に沿う）

- [ ] TypeToTalk を起動 → メインウインドウとSettings の両方を開く
- [ ] 初期状態: 両画面が同じ表示（「未読込」または「準備完了」）であること
- [ ] Settings の「再読込」ボタン押下
- [ ] 読込中: 両画面とも「モデル読込中...」（または `loadingStatusText` の値）に同期して切り替わること
- [ ] 読込完了: 両画面とも「準備完了」に同期して切り替わること（**バグ解消の決定打**）
- [ ] モデル切り替え時: Settings でモデル選択 → 両画面が「未読込」に戻り、再読込で両画面が「準備完了」に揃うこと

**完了条件**: 全 5 シナリオで両画面の表示が常に一致

---

### TODO-5: 副作用チェック（他のステータス表示を壊していないか）

- [ ] BonsaiManager のステータス表示が変わっていないこと（読込完了「準備完了」、未読込「未読込」）
- [ ] 失敗ケースの文言「失敗: ...」が両画面で正しく表示されること（強制的に発生させる必要があれば、選択モデルを存在しない ID にして再読込）
- [ ] 録音 → 文字起こし → 整形のフルフローが従来通り動くこと

**完了条件**: 既存機能のリグレッションがゼロ

---

## 4. リスク / 注意点

- `loadState` に `didSet` を追加すると、`loadState` が `@Published private(set)` のまま自分自身の didSet からアクセスされるが、これは Swift 仕様上問題ない（didSet は @Published の変更通知のあとに走る）
- `init(...)` で他プロパティの初期化前に `refreshStatusText()` を呼ぶと未初期化アクセスでクラッシュするため、**必ず init の末尾**で呼ぶこと
- `needsExplicitLoad` が依存する `selectedModelID` は settings 経由の computed なので、settings が変わったときの追従は別問題。本タスクのスコープ外（既存挙動を維持）
- 本修正は文言ロジックを変えない。既存の「未読込」「準備完了」「モデル読込中...」「失敗: ...」の出力結果は完全互換を維持する

---

## 5. 完了の定義

- TODO-1 〜 TODO-5 すべて完了
- 実機 or シミュで投影されたメインウインドウとSettings の表示が常に一致することを目視確認
- WhisperManager.swift のコンパイル成功 & リグレッションゼロ
- 進捗・確認結果を progress.md に記録

---

## 6. メモ

- 修正は WhisperManager.swift 一本で完結する（Coordinator や View 側に手を入れない）。これにより Step 5 実装小人ちゃんの作業が単純化され、レビュー観点も「@Published 化と didSet による状態同期が正しく組まれているか」に集約される
- 参考実装は BonsaiManager.swift（investigation.md §10.1）。同じ流儀に揃える
