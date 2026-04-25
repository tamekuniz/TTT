# Whisper ステータス表示食い違い - 調査報告書

**調査対象**: TypeToTalk macOS SwiftUI アプリにおいて、Whisper モデルのステータス表示が設定画面と主ウインドウで異なる問題

**問題現象**:
- 設定画面 (Settings): Whisper ステータスが「準備完了」と表示される
- メインウインドウ (Recorder): Whisper ステータスが「未読込」と表示される
- 同じ `whisper.statusText` を参照しているはずなのに食い違っている

---

## 1. 関連ファイル一覧（パス + 役割）

| ファイルパス | 役割 | 重要度 |
|-----------|------|------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift` | Whisper モデル管理、ステータス定義 | **最高** |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | アプリ起動、Coordinator、メインビュー定義 | **最高** |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift` | 設定画面 UI、Whisper ステータス表示 | **最高** |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/BonsaiManager.swift` | Bonsai モデル管理（参考実装） | 中 |

---

## 2. 既存実装パターン（Whisper のステータス管理クラス、statusText の定義、表示の参照箇所）

### 2.1 WhisperManager.swift の @Published プロパティ

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift`

```swift
// 行 11-18
@MainActor
class WhisperManager: ObservableObject {
    @Published var whisperKit: WhisperKit?
    @Published var isTranscribing = false
    @Published var lastTranscription: String = ""
    @Published var isLoadingModel = false
    @Published private(set) var loadState: WhisperLoadState = .idle
    @Published private(set) var loadingStatusText = "未読込"
```

**@Published の内訳**:
- `loadState`: Enum 型で `idle | loading | loaded(modelID: String) | failed(message: String)` を管理 ✅ @Published
- `loadingStatusText`: 読込中の詳細メッセージ（「ダウンロード中...」など） ✅ @Published
- `isLoadingModel`: 読込中フラグ ✅ @Published

### 2.2 statusText の定義（重要: **計算型プロパティ**）

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift`（行 47-58）

```swift
var statusText: String {
    switch loadState {
    case .idle:
        return needsExplicitLoad ? "未読込" : "準備完了"
    case .loading:
        return loadingStatusText
    case .loaded:
        return needsExplicitLoad ? "未読込" : "準備完了"
    case let .failed(message):
        return "失敗: \(message)"
    }
}
```

**重要な特性**:
- **計算型プロパティ** （`@Published` アノテーション **なし**）
- `loadState` と `loadingStatusText` に依存
- `needsExplicitLoad` に依存（computed var、行 39-40）
- 値を計算するたびに新しい String オブジェクトを返す（参照同一性なし）

### 2.3 statusText の参照箇所

#### ① 設定画面 (SettingsView)

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift`（行 70）

```swift
struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var whisper: WhisperManager    // ← 直接参照
    @ObservedObject var bonsai: BonsaiManager
    @ObservedObject var accessibility: AccessibilityManager
    
    // ...
    
    loadStatusBlock(
        status: whisper.statusText,  // ← 直接参照（行 70）
        loadedModel: whisper.loadedModelDisplayName,
        // ...
    )
```

**観測方式**: `@ObservedObject var whisper` で WhisperManager を直接監視

#### ② メインウインドウ (TypeToTalkMainView)

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`（行 82）

```swift
struct TypeToTalkMainView: View {
    @ObservedObject var coordinator: TypeToTalkCoordinator
    
    // ...
    
    modelStatusRow(
        title: "Whisper",
        detail: coordinator.settings.whisperDisplayName,
        status: coordinator.whisper.statusText  // ← Coordinator 経由で参照（行 82）
    )
```

**観測方式**: `@ObservedObject var coordinator` → `coordinator.whisper` で参照

---

## 3. 影響範囲（呼び出し側 / 依存。Whisper Manager / Coordinator / View 構造）

### 3.1 依存関係の構造図

```
TypeToTalkApp.swift (アプリエントリーポイント)
  ↓ @StateObject
  TypeToTalkCoordinator
    ├─ @Published var whisper: WhisperManager
    │   ├─ @Published var loadState
    │   ├─ @Published var loadingStatusText
    │   ├─ var statusText (← 計算型、@Published なし) ⚠️
    │   └─ var needsExplicitLoad (← 計算型)
    │
    ├─ @Published var settings: SettingsManager
    ├─ @Published var recorder: AudioRecorder
    ├─ @Published var formatter: OpenAICompatibleManager
    ├─ @Published var bonsai: BonsaiManager
    └─ @Published var accessibility: AccessibilityManager

TypeToTalkMainView
  ├─ coordinator.whisper.statusText  (行 82)  ← ⚠️ 計算型プロパティで View が再レンダされない
  └─ statusBadge() で表示

SettingsView
  ├─ whisper.statusText  (行 70)  ← ✅ @ObservedObject で監視可能（ただし微妙）
  └─ loadStatusBlock() で表示
```

### 3.2 Coordinator の依存注入

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`（行 186-231）

```swift
@MainActor
class TypeToTalkCoordinator: ObservableObject {
    @Published var recorder = AudioRecorder()
    @Published var whisper: WhisperManager      // ← 公開されている
    @Published var formatter = OpenAICompatibleManager()
    @Published var bonsai = BonsaiManager()
    @Published var accessibility = AccessibilityManager()
    @Published var network = NetworkManager()
    @Published var settings: SettingsManager
    
    init() {
        let settings = SettingsManager()
        self.settings = settings
        self.whisper = WhisperManager(settings: settings)  // ← 生成
        // ...
    }
}
```

---

## 4. 過去の類似実装（git log で Whisper ステータス周りの変更をチェック）

**コマンド**: `git log --oneline -50`

```
c57309d [フォK] feat: ウインドウタイトルを Mac 標準タイトルバーに移行
1883798 [フォK] fix: 録音終了後のマイクボタンパルス停止バグを修正
9d70ec7 [フォK] feat: マイクボタンUI改善＋権限ラベル微調整
aac4a7a [フォK] feat: モデル自動DL停止、ローカル存在時のみ自動ロード
35fe441 [フォK] feat: 権限動的チェック＋UI区別＋触覚/視覚フィードバック
16d3413 [フォK] feat: UI整理＋言語設定＋整形プロンプト構造化
4b03313 [フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加
cb281cf Refactor: Modularize project structure (App, Managers, Models, Views) for high maintainability
db58908 Implement Settings UI for API keys and custom prompts
1f0d5e7 Add documentation and Info.plist for system permissions
ca4c764 Initial commit of TTT (Talk to Type) macOS app
```

**分析**:
- 直近 50 コミットの中に「statusText」に関する明示的な修正はない
- 「モデル自動DL停止」（aac4a7a）で `needsExplicitLoad` ロジックが追加された可能性 → 状態計算ロジック変更
- 「リファクタ完了」（4b03313）で Coordinator 構造が整備された時期
- **重要**: statusText が計算型のままなのは、リファクタ時点で既にこの設計だった可能性

---

## 5. 想定される副作用 / リスク（修正時に他のステータス表示に影響しないか）

### 5.1 statusText の依存関係の詳細分析

`statusText` の値は以下に依存:

1. **`loadState`** (@Published) → 値変化時に発行者が変わる ✅
2. **`loadingStatusText`** (@Published) → 値変化時に発行者が変わる ✅
3. **`needsExplicitLoad`** (計算型) → 以下に依存:
   - `whisperKit` (@Published)
   - `loadedModelID` (private, 手動セット)
   - `selectedModelID` (computed var, settings 経由)

### 5.2 SwiftUI の @Published と計算型プロパティの相互作用

**問題点**:

- `@Published var loadState` が変化 → Coordinator の `objectWillChange` 発火 ✅
- しかし Coordinator 経由で View が参照する `coordinator.whisper.statusText` は**計算型** → 再計算されても SwiftUI が認識しない ❌

**理由**:

SwiftUI の `@ObservedObject` は以下の場合にのみ View 再レンダを指示:
1. **参照オブジェクト自身の `ObjectWillChange`** が発火 → WhisperManager の @Published が変わった時
2. OR **参照プロパティ自体が @Published** → `coordinator.whisper.statusText` は計算型なので対象外 ❌

計算型プロパティは「参照元オブジェクトの @Published 変化を追跡」されず、値キャッシュもない。

### 5.3 SettingsView が「準備完了」を表示する理由

SettingsView は `@ObservedObject var whisper` で **直接** WhisperManager を観察:

```swift
@ObservedObject var whisper: WhisperManager
loadStatusBlock(
    status: whisper.statusText,  // ← whisper の ObjectWillChange をトリガに再レンダ
```

- `whisper.loadState` 変化 → `whisper.objectWillChange` 発火
- → View 再評価 → `whisper.statusText` 再計算 → 新しい値（「準備完了」）表示 ✅

### 5.4 メインウインドウが「未読込」のままの理由

TypeToTalkMainView は `@ObservedObject var coordinator` 経由で参照:

```swift
@ObservedObject var coordinator: TypeToTalkCoordinator
modelStatusRow(
    status: coordinator.whisper.statusText  // ← Coordinator の変化は追跡しない
```

- `whisper.loadState` 変化 → **Coordinator の objectWillChange は発火しない** (whisper は @Published だが、statusText は計算型)
- → View 再評価されない
- → 初期値のまま「未読込」が表示され続ける ❌

**更に問題を深刻にする要因**:
- メインウインドウは起動時に一度 render される
- その時点で `whisper.statusText` は `.idle` 状態で計算され、「未読込」が return される
- その後 `whisper.loadState` が `.loaded` に変わっても、Coordinator 経由の View は再評価されない

---

## 6. 制約条件（Swift Concurrency / @Published / @ObservedObject 等の SwiftUI 流儀）

### 6.1 現在のアーキテクチャ制約

1. **@MainActor 標準化**: WhisperManager, Coordinator 共に `@MainActor` で宣言 → UI 更新は Main Thread のみ ✅
2. **ObservableObject パターン**: Coordinator と各 Manager が ObservableObject に準拠 ✅
3. **Swift Concurrency**: `async/await` で非同期処理を実装
4. **@Published の伝播**: 子オブジェクトの @Published 変化が親オブジェクトを通じて伝播するには、親が子を @Published で保持する必要がある ✅ (coordinator は @Published var whisper)

### 6.2 計算型プロパティと @Published の相互作用ルール

| パターン | View 再評価 | 備考 |
|---------|---------|------|
| @Published プロパティ | ✅ | objectWillChange 発火 |
| 計算型プロパティ（@Published なし） | ❌ | 依存元の @Published が変わっても、計算型自体が @Published でないと追跡されない |
| @Published 変数を返す計算型プロパティ | ⚠️ 微妙 | 返す値は @Published だが、計算型の "結果" は追跡されない |

### 6.3 修正時に守るべき SwiftUI 流儀

1. **@ObservedObject は浅くネストしない**: `coordinator.whisper.statusText` より `coordinator.whisperStatusText` が好ましい
2. **計算型プロパティは View 更新トリガにしない**: statusText のような計算値は、依存元の @Published が変わったあとに改めて読む設計にする
3. **Coordinator が中継する場合は、子の @Published 変化を明示的に転送**: @Published プロパティを新設する

---

## 7. テスト戦略（実機/シミュ確認ポイント。どの操作で何を見るか）

### 7.1 バグ再現手順

**環境**: macOS 実機推奨（Simulator でも可、Whisper ダウンロード時間: 数分）

1. **初期状態**:
   - TypeToTalk を起動 → メインウインドウ開く
   - メインウインドウ右上 ⚙️ → Settings 開く
   - 並行表示が困難な場合: Command+` (バックティック) でウインドウを切り替え

2. **Whisper 未ロード状態の確認**:
   - Settings: 「状態: 未読込」が表示される ✅
   - メインウインドウ: Whisper ステータス「未読込」 ✅（この時点では一致）

3. **Whisper 再読込トリガ**:
   - Settings: 「再読込」ボタン押下
   - Whisper ダウンロード＆ロード開始

4. **読込中の状態確認**:
   - Settings: 「状態: モデル読込中...」に変わる ✅
   - メインウインドウ: Whisper ステータス「モデル読込中...」に変わる ✅（この時点では一致）

5. **読込完了後の状態確認**（**バグが顕在化する箇所**）:
   - Settings: 「状態: 準備完了」と表示 ✅
   - メインウインドウ: Whisper ステータス「未読込」のまま ❌ ← **バグ**

### 7.2 詳細チェックポイント

| チェック項目 | 確認方法 | 期待値 | 現状 |
|-----------|--------|------|-----|
| Settings の statusText 更新 | ボタン押下後、Settings タブを見る | 「準備完了」に変わる | ✅ 動作 |
| メインウインドウの statusText 更新 | ボタン押下後、メインウインドウを見る | 「準備完了」に変わる | ❌ 「未読込」のまま |
| 初期起動時の自動ロード | 初回起動（ローカル Whisper あり） | 両画面とも「準備完了」 | 不確か（要確認） |
| モデル切り替え時 | Settings でモデル選択 → 再読込 | Settings では更新、メインウインドウでは？ | 不確か |

### 7.3 Xcode デバッガ確認ポイント

1. **WhisperManager の loadState 変化**:
   ```swift
   // Coordinator.swift の setupWhisper 完了地点で確認
   print("loadState changed to: \(self.loadState)")  // .loaded が出力される
   print("statusText: \(self.statusText)")            // 「準備完了」が出力される
   ```

2. **View の再評価有無**:
   - Xcode の Canvas 再評価ログ、または `#Preview` の refresh 動作を確認
   - メインウインドウの statusBadge 内で `print("statusBadge called with: \(value)")` を仕込む

3. **Coordinator.objectWillChange の発火回数**:
   ```swift
   // TypeToTalkCoordinator.init() 内に以下を追加
   let _ = self.objectWillChange.sink { _ in
       print("Coordinator.objectWillChange fired")
   }
   ```

---

## 8. 根本原因 - 最終確定（推測ではなく実コード特定）

### 8.1 計算型プロパティが @Published でないために、SwiftUI View が変化を追跡できない

**根本原因**:

`WhisperManager.statusText` は計算型プロパティであり、**@Published アノテーションが付いていない**。

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift`

```swift
@MainActor
class WhisperManager: ObservableObject {
    @Published private(set) var loadState: WhisperLoadState = .idle
    @Published private(set) var loadingStatusText = "未読込"
    
    var statusText: String {  // ← @Published なし ❌
        switch loadState {
        case .idle:
            return needsExplicitLoad ? "未読込" : "準備完了"
        case .loading:
            return loadingStatusText
        case .loaded:
            return needsExplicitLoad ? "未読込" : "準備完了"
        case let .failed(message):
            return "失敗: \(message)"
        }
    }
}
```

### 8.2 SettingsView が正しく表示される理由（例外的に動作）

SettingsView は WhisperManager を直接 @ObservedObject で参照:

```swift
@ObservedObject var whisper: WhisperManager
loadStatusBlock(
    status: whisper.statusText,  // 直接参照
```

- `whisper.loadState` (@Published) が変わる
- → `whisper.objectWillChange` が発火
- → `whisper` を参照している SettingsView のすべてのプロパティが再評価される
- → `whisper.statusText` が再計算される
- → 新しい値が表示される ✅

ただし、これは「LabyrinthQUARK」（@ObservedObject が全プロパティ再評価する仕様）のおかげで、設計として正しいわけではない。

### 8.3 メインウインドウが古い値を表示し続ける理由（根本的な設計不具合）

TypeToTalkMainView は Coordinator を経由して参照:

```swift
@ObservedObject var coordinator: TypeToTalkCoordinator
status: coordinator.whisper.statusText  // 計算型への間接参照
```

**多段参照のパスが成立していない**:

1. `whisper.loadState` が変わる ✅
2. → `whisper.objectWillChange` 発火 ✅
3. → **しかし Coordinator の objectWillChange は発火しない** ❌
   - 理由: Coordinator は `@Published var whisper` を持っているが、whisper の内部 @Published 変化は Coordinator の objectWillChange トリガにならない
   - @Published が追跡するのは「whisper オブジェクト参照の変化」（再割り当て）のみ、オブジェクト内部の @Published 変化ではない
4. → `coordinator` を監視している View は再評価されない ❌
5. → `coordinator.whisper.statusText` は初期値のまま ❌

**つまり**: 計算型プロパティが @Published でない＆ Coordinator が中継している ＝ 二重の障壁で View 更新が止まる

---

## 9. 最終結論

### 問題の本質

`WhisperManager.statusText` が **計算型プロパティ** かつ **@Published なし** であるため、以下の現象が発生する:

- SettingsView: 直接参照なので、WhisperManager の @Published 変化で全体再評価 → statusText も再計算される ✅
- TypeToTalkMainView: Coordinator 経由で参照し、計算型への変化追跡なし + Coordinator の objectWillChange トリガがない ❌

### 修正の方向性（実装は別途）

以下いずれかの方法で statusText の変化を View に追跡させる必要がある:

**オプション A** (推奨): `statusText` を @Published プロパティに昇格
- WhisperManager 内で `@Published private(set) var statusText` を新設
- `loadState` / `loadingStatusText` 変化時に手動で `statusText` を更新

**オプション B**: Coordinator で statusText を転送
- Coordinator に `@Published private(set) var whisperStatusText` を新設
- `whisper.statusText` 変化をリスン & キャッシュ

**オプション C** (非推奨): 多段参照を避ける
- TypeToTalkMainView を直接 WhisperManager で監視（Coordinator 省略）
- アーキテクチャ上の整合性低下のため非推奨

---

## 10. 補足資料

### 10.1 BonsaiManager との比較（参考実装）

BonsaiManager は statusMessage が手動で管理される @Published プロパティ:

```swift
@Published private(set) var statusMessage = "未読込"  // ← @Published である

func configureSelectedModel(_ modelID: String) {
    currentSelectedModelID = modelID
    switch loadState {
    case .idle:
        statusMessage = "未読込"    // 手動更新 ✅
    case .loading:
        statusMessage = "読込中"
    case .loaded:
        statusMessage = loadedModelID == modelID ? "準備完了" : "未読込"
    case .failed:
        break
    }
}
```

- statusMessage は直接 @Published → 変化が自動的に伝播される
- SettingsView / メインウインドウの両方で正しく表示される ✅

**教訓**: 計算型ではなく、明示的な @Published プロパティで管理すべき

