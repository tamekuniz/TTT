# Step 3 調査報告書：ショートカット仕様統合の影響範囲分析

**作成日**: 2026年4月25日  
**調査対象**: TypeToTalk for macOS（SwiftUI + KeyboardShortcuts ライブラリ）  
**調査者**: Step 3 調査小人ちゃん（Thorough exploration）  
**目的**: `KeyboardShortcuts.toggleWindow` と `triggerRecording` の統合仕様化に向けた、実装構造・副作用・リスク・制約の完全把握

---

## 1. 関連ファイル一覧（パス + 役割）

### コアファイル
| パス | 役割 | 主要コンテンツ |
|------|------|------------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | **ショートカット定義・ハンドラ・Coordinator主体** | KeyboardShortcuts.Name 定義（行6-7）、onKeyDown/onKeyUp ハンドラ（行214-230）、handleTriggerShortcutDown/Up（行315-342）、handleToggleWindow（行430-448）、toggleRecording（行240-313） |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift` | **ショートカット設定UI** | KeyboardShortcuts.Recorder for .triggerRecording（行228）、for .toggleWindow（行232） |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/SettingsManager.swift` | **設定値永続化・デフォルト定義** | ShortcutTriggerMode enum（行119-136）、shortcutTriggerModeRawValue プロパティ＋UserDefaults（行180-182）、デフォルト値 .disabled（行232）、shortcutTriggerMode computed property（行271-274） |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AudioRecorder.swift` | **録音状態管理** | @Published isRecording フラグ（行45）、startRecording() / stopRecording()（行47-93） |

### 依存・参照ファイル
| パス | 役割 |
|------|------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Package.swift` | KeyboardShortcuts ライブラリ（バージョン 2.4.0以上）の依存定義（行14） |
| `.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/KeyboardShortcuts.swift` | KeyboardShortcuts.onKeyDown/onKeyUp 実装（行457-510）、ハンドラ管理（legacyKeyDownHandlers/legacyKeyUpHandlers） |
| `.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift` | KeyboardShortcuts.Recorder<Label> SwiftUI View の実装（行44-89） |

---

## 2. 既存実装パターン

### 2.1 KeyboardShortcuts ショートカット定義（行6-7）

```swift
extension KeyboardShortcuts.Name {
    static let triggerRecording = Self("triggerRecording")
    static let toggleWindow = Self("toggleWindow")
}
```

**特徴**:
- `KeyboardShortcuts.Name` は String でラップされた型。UserDefaults キーとして `"KeyboardShortcuts_triggerRecording"` のような形式で自動保存される
- 定義時点では**デフォルトキー割当はない**。ユーザー設定で初めて割り当てられる
- 複数のショートカットで衝突する値は SettingsView（KeyboardShortcuts.Recorder）側で入力時に警告・拒否される

### 2.2 onKeyDown / onKeyUp ハンドラの登録（行214-230）

```swift
// triggerRecording: キー押下時と解放時を分別
KeyboardShortcuts.onKeyDown(for: .triggerRecording) { [weak self] in
    Task { @MainActor in
        await self?.handleTriggerShortcutDown()  // 行316: 状態チェック後 toggle or pushToTalk 開始
    }
}

KeyboardShortcuts.onKeyUp(for: .triggerRecording) { [weak self] in
    Task { @MainActor in
        await self?.handleTriggerShortcutUp()  // 行335: pushToTalk モード時は録音停止
    }
}

// toggleWindow: キー押下時のみ反応（キー解放イベント不要）
KeyboardShortcuts.onKeyDown(for: .toggleWindow) { [weak self] in
    Task { @MainActor in
        self?.handleToggleWindow()  // 行431: ウインドウ表示/非表示をトグル
    }
}
```

**KeyboardShortcuts ライブラリ内部動作**:
- `onKeyDown(for: .triggerRecording)` は私有辞書 `legacyKeyDownHandlers[.triggerRecording] = []` に登録（`.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/KeyboardShortcuts.swift` 行10、line 457-）
- 同様に onKeyUp は `legacyKeyUpHandlers` に登録
- Carbon イベント監視（CarbonKeyboardShortcuts）で実際のキープレスを検知し、登録済みハンドラを実行

### 2.3 handleTriggerShortcutDown() の処理フロー（行315-332）

```swift
private func handleTriggerShortcutDown() async {
    guard !isTriggerShortcutPressed else { return }  // 重複押下防止
    isTriggerShortcutPressed = true
    recordTriggerFeedback(source: "グローバル")  // ビープ音 + statusMessage 更新
    
    switch settings.shortcutTriggerMode {
    case .disabled:
        break  // なにもしない
    case .toggle:
        showRecorderWindow()                         // ウインドウを表示
        await toggleRecording()                      // 録音/停止をトグル
    case .pushToTalk:
        if !recorder.isRecording && !isProcessing {
            showRecorderWindow()                     // ウインドウを表示
            await toggleRecording()                  // 録音開始のみ
        }
    }
}
```

**重要**: 現在 triggerRecording は**ウインドウ表示とセット**で動作（showRecorderWindow() 行324, 328）

### 2.4 handleTriggerShortcutUp() の処理フロー（行334-342）

```swift
private func handleTriggerShortcutUp() async {
    guard isTriggerShortcutPressed else { return }
    isTriggerShortcutPressed = false
    
    guard settings.shortcutTriggerMode == .pushToTalk else { return }  // toggle モードなら無反応
    guard recorder.isRecording else { return }
    
    await toggleRecording()  // pushToTalk モードのみ、キー解放時に録音停止
}
```

### 2.5 handleToggleWindow() の処理フロー（行430-448）

```swift
private func handleToggleWindow() {
    let recorderWindow = NSApplication.shared.windows.first { window in
        window.identifier?.rawValue == "RecorderWindow"
    }
    
    guard let window = recorderWindow else {
        showRecorderWindow()  // ウインドウが未生成ならフォールバック
        return
    }
    
    if window.isVisible {
        window.orderOut(nil)  // 非表示
    } else {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)  // 表示
    }
}
```

**重要**: toggleWindow は**ウインドウ表示/非表示を純粋にトグル**するのみ。**録音状態には一切干渉しない**。

### 2.6 toggleRecording() の実装（行240-313）

```swift
func toggleRecording() async {
    if recorder.isRecording {
        // 停止フロー
        recorder.stopRecording()
        statusMessage = "文字起こし中..."
        isProcessing = true
        // Whisper による文字起こし → AI による整形 → テキスト入力（行259-301）
    } else {
        // 開始フロー
        await synchronizeModelsForCurrentSettings()
        recordingURL = try await recorder.startRecording()
        statusMessage = "録音中..."
    }
}
```

**状態管理**:
- `recorder.isRecording` は AudioRecorder の @Published プロパティ（AudioRecorder.swift 行45）
- startRecording() は AVAudioEngine を設定し `isRecording = true` を設定（行83）
- stopRecording() は `isRecording = false` を設定（行90）

### 2.7 SettingsView のショートカット設定UI（行227-233）

```swift
settingRow("ショートカット") {
    KeyboardShortcuts.Recorder(for: .triggerRecording)
}

settingRow("ウインドウ表示トグル") {
    KeyboardShortcuts.Recorder(for: .toggleWindow)
}
```

**KeyboardShortcuts.Recorder 動作**:
- SwiftUI View で、ユーザーが新しいキーを記録できるUI
- 自動的に `UserDefaults.standard` に `"KeyboardShortcuts_triggerRecording"`, `"KeyboardShortcuts_toggleWindow"` というキーで保存
- 既存システム/アプリメニューのショートカットとの衝突検出・警告機能内蔵
- onChange コールバックで、登録時にリアルタイム反応可能（現在は使用していない）

---

## 3. 影響範囲（呼び出し側 / 依存）

### 3.1 triggerRecording の呼び出し元・依存

| 要素 | 位置 | 用途 | 統合後への影響 |
|------|------|------|------------|
| **Coordinator.init()** | 行214-224 | onKeyDown/onKeyUp ハンドラ登録 | ショートカット定義廃止なら削除必須 |
| **SettingsView** | 行228 | KeyboardShortcuts.Recorder UI 表示 | 統合ショートカット名に置換 |
| **handleTriggerShortcutDown()** | 行315-332 | トリガー処理 | 機能は triggerRecording に統合可 |
| **handleTriggerShortcutUp()** | 行334-342 | pushToTalk キー解放時処理 | 機能は triggerRecording に統合可 |
| **shortcutTriggerMode** | SettingsManager 行271-274 | モード選択（disabled/toggle/pushToTalk） | 既存ユーザー設定保持が課題 |

### 3.2 toggleWindow の呼び出し元・依存

| 要素 | 位置 | 用途 | 統合後への影響 |
|------|------|------|------------|
| **Coordinator.init()** | 行226-230 | onKeyDown ハンドラ登録 | ショートカット定義廃止なら削除必須 |
| **SettingsView** | 行232 | KeyboardShortcuts.Recorder UI 表示 | 統合ショートカット名に置換 |
| **handleToggleWindow()** | 行430-448 | 実装ロジック | **ウインドウ表示/非表示のみ**（純粋な副作用なし） |

### 3.3 SettingsManager での shortcutTriggerMode の役割

**定義**:
```swift
enum ShortcutTriggerMode: String, CaseIterable, Identifiable {
    case disabled, toggle, pushToTalk
}

@Published var shortcutTriggerModeRawValue: String {
    didSet { UserDefaults.standard.set(shortcutTriggerModeRawValue, forKey: "shortcutTriggerMode") }
}

init() {
    self.shortcutTriggerModeRawValue =
        UserDefaults.standard.string(forKey: "shortcutTriggerMode") ??
        UserDefaults.standard.string(forKey: "rightOptionMode") ??
        ShortcutTriggerMode.disabled.rawValue  // デフォルト: disabled
}

var shortcutTriggerMode: ShortcutTriggerMode {
    get { ShortcutTriggerMode(rawValue: shortcutTriggerModeRawValue) ?? .disabled }
    set { shortcutTriggerModeRawValue = newValue.rawValue }
}
```

**互換性**: 旧 "rightOptionMode" キーを読む（line 231）。既存ユーザーで右 Option 設定があれば復元。

### 3.4 SettingsView のUI構成（行225-251）

```swift
GroupBox {
    VStack(alignment: .leading, spacing: 12) {
        settingRow("ショートカット") {
            KeyboardShortcuts.Recorder(for: .triggerRecording)  // 現 triggerRecording
        }
        
        settingRow("ウインドウ表示トグル") {
            KeyboardShortcuts.Recorder(for: .toggleWindow)  // 現 toggleWindow
        }
        
        settingRow("動作") {
            Picker("トリガー動作", selection: $settings.shortcutTriggerModeRawValue) {
                ForEach(ShortcutTriggerMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
        }
        
        Text("任意のショートカットに加えて、右 Option 単体でも...").font(.caption)
    }
} label: {
    sectionTitle("ショートカット", subtitle: "録音の開始方法")
}
```

**ラベルロジック**:
- **"ショートカット"** → triggerRecording の設定UI
- **"ウインドウ表示トグル"** → toggleWindow の設定UI
- **"動作"** → トリガーモード（トグル/プッシュトーク/無効）の選択

---

## 4. 過去の類似実装（git log）

### 4.1 主要な変更履歴（--oneline -50）

```
848ef06 [フォK] fix: Whisperステータス不整合修正
c57309d [フォK] feat: ウインドウタイトルを Mac 標準へ
1883798 [フォK] fix: 録音終了後パルス停止バグ修正
9d70ec7 [フォK] feat: マイクボタンUI改善
aac4a7a [フォK] feat: モデル自動DL停止
35fe441 [フォK] feat: 権限動的チェック
16d3413 [フォK] feat: UI整理 + 言語設定
4b03313 [フォK] feat: TypeToTalk リファクタ完了＋ウインドウトグル追加  ← 重要
cb281cf Refactor: モジュール構造化
db58908 Implement: Settings UI
1f0d5e7 Add: ドキュメント + Info.plist
ca4c764 Initial: TypeToTalk commit
```

### 4.2 ウインドウトグル追加の commit 詳細（4b03313）

**date**: 2026年4月25日 13:37:25

**コミットメッセージ**（抜粋）:
```
[フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加

- T3: ウインドウ表示トグル用ショートカット toggleWindow を新規追加
       （既存 triggerRecording はそのまま、SettingsView に Recorder UI 追加、
       デフォルトキー未割当、録音状態には触らない設計）
```

**重要な設計意思**:
- **既存 triggerRecording を変更しない** 設計（互換性重視）
- **toggleWindow は純粋にウインドウ表示/非表示** 機能のみ
- **デフォルトキー割当なし**（ユーザーが自由に設定）
- **録音状態に干渉しない**（独立した機能）

---

## 5. 想定される副作用 / リスク

### 5.1 ユーザーが既に設定したショートカットの保持リスク

**現状**:
- triggerRecording に例えば `Cmd+Opt+R` をユーザーが割り当てている
- toggleWindow はデフォルトキー未割当
- UserDefaults: `"KeyboardShortcuts_triggerRecording"` に保存済み

**統合時のリスク**:
- A案（toggleWindow を統合機能化）: 既存 UserDefaults キー `"KeyboardShortcuts_triggerRecording"` が無視される
- B案（新ショートカット追加）: UserDefaults に 2 つのキーが共存し、混乱の可能性
- C案（triggerRecording を統合機能化）: triggerRecording が廃止される場合、旧キーの処理が必要

**推奨**: ショートカット廃止時は、初期化ロジックで旧キーを新キーへマイグレーション、または互換読み込みを実装。

### 5.2 既存のショートカット定義削除がもたらす影響

**定義削除の場合**:
```swift
// 現状（行6-7）
static let triggerRecording = Self("triggerRecording")
static let toggleWindow = Self("toggleWindow")

// 統合後、一方を廃止すると
static let recordingShortcut = Self("recordingShortcut")  // 新定義
// triggerRecording の定義削除
```

**影響**:
1. **KeyboardShortcuts.onKeyDown/onKeyUp の登録削除**必須（現 Coordinator.init 行214-230）
2. **SettingsView の Recorder UI 削除または統合**（行228 or 232）
3. **UserDefaults の読み込みロジック調整**（旧キーからの移行）
4. **Recorder UI のラベル変更**（"ショートカット" または新名前に統一）

**不確か**: 旧ショートカット定義を完全削除せず、互換性フラグで共存させるオプションもある（KeyboardShortcuts ライブラリの仕様上可能か確認が必要）。

### 5.3 状態遷移の複雑化リスク

**現状の独立した状態マシン**:
```
triggerRecording キー押下
  ├─ toggle モード: showRecorderWindow() + toggleRecording()（開始/停止切替）
  └─ pushToTalk モード: 
       ├─ キー押下: showRecorderWindow() + toggleRecording()（開始）
       └─ キー解放: toggleRecording()（停止）

toggleWindow キー押下
  └─ ウインドウ表示/非表示トグル（録音状態無関係）
```

**統合時（仮）**:
```
統合ショートカット キー押下
  ├─ ウインドウ表示状態 + 録音状態の組み合わせで動作判定
  └─ 「1キーで『表示 + 録音』『停止のみ』『非表示のみ』等を区別」
```

**リスク**: 状態空間が爆発的に増加し、テスト対象が増える。

### 5.4 ウインドウ閉じるタイミングの不確定

**現状**: handleTriggerShortcutDown/Up は**ウインドウ表示のみ**、閉じない。handleToggleWindow のみ閉じる機能を持つ。

**統合時の設問**:
- 統合ショートカットで「表示 + 録音開始」した後、「停止」時にウインドウを自動閉じるか？
- トグルモードで2回目押下時は停止 + 自動閉じる？
- プッシュトークモードでキー解放時は停止 + 自動閉じる？

**リスク**: 仕様不明確のまま実装すると、ユーザー混乱。

---

## 6. 制約条件

### 6.1 KeyboardShortcuts ライブラリの API 制約

**バージョン**: 2.4.0 以上（Package.swift 行14）

**API 機能**:
- `KeyboardShortcuts.Name`: String でラップされた Hashable な型
- `onKeyDown(for:action:)`, `onKeyUp(for:action:)`: 非同期ハンドラ登録（複数登録可能）
- `KeyboardShortcuts.Recorder`: SwiftUI View（自動 UserDefaults 保存）
- 衝突検出・警告機能内蔵

**制約**:
- 1 つの `Name` に対して複数の onKeyDown/onKeyUp ハンドラを登録可能（配列管理）
- ハンドラは**スレッドセーフでない**（MainActor 指定必須、現実装で守られている）
- UserDefaults キーは自動生成（`"KeyboardShortcuts_" + name.rawValue`）、カスタム可否は不確か

**不確か**: KeyboardShortcuts ライブラリのバージョンアップで API が変わる可能性、macOS バージョン互換性の下限（現 macOS 14 以上）。

### 6.2 ショートカット衝突回避

**現状**:
- KeyboardShortcuts.Recorder は入力時に衝突検出（システム + アプリメニュー + 既存ショートカット）
- ユーザーが同じキーを複数のショートカットに割り当てると、先登録のハンドラのみ実行される可能性

**制約**:
- 統合ショートカットと toggleWindow のキーが同じ場合、どちらが優先実行されるか不明確
  - → KeyboardShortcuts.Recorder の衝突警告で物理的に防止できるはず
- 右 Option キーとの共存（現実装は line 344-373 で NSEvent.addGlobalMonitorForEvents で別途監視）

### 6.3 AppKit / NSApp との連携制約

**ウインドウ管理**:
```swift
// 行419-428, 431-447
NSApplication.shared.windows  // 全ウインドウのリスト
window.identifier?.rawValue == "RecorderWindow"  // 識別子で検索
window.isVisible, window.makeKeyAndOrderFront(nil), window.orderOut(nil)
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.activate(ignoringOtherApps: true)
```

**制約**:
- WindowGroup で自動生成されるウインドウの identifier は TypeToTalkApp.onAppear で手動設定（行510）
- SceneKit / SwiftUI ウインドウ管理の特性上、複数ウインドウ時の動作は不確定

**不確か**: macOS バージョン（10.15～14）でのウインドウ API の差異。

---

## 7. テスト戦略（ショートカット押下時の挙動確認シナリオ）

### 7.1 状態マトリクス定義

| 項目 | 値 | 説明 |
|------|------|------|
| **ウインドウ状態** | 表示 / 非表示 | NSWindow.isVisible |
| **録音状態** | 開始中 / 停止中 | AudioRecorder.isRecording |
| **処理状態** | アイドル / 処理中 | Coordinator.isProcessing（文字起こし＋AI整形中） |
| **ショートカット設定** | disabled / toggle / pushToTalk | ShortcutTriggerMode |
| **キー入力** | 押下 / 解放 | onKeyDown / onKeyUp |

### 7.2 既存実装のテストシナリオ（triggerRecording）

#### **シナリオ 1-1: トグルモード + ウインドウ非表示 + 停止状態**
- **入力**: triggerRecording キー押下
- **期待**: ウインドウ表示 + 録音開始 + statusMessage = "録音中..."
- **実装根拠**: handleTriggerShortcutDown → toggle case → showRecorderWindow() + toggleRecording() (line 324-325)

#### **シナリオ 1-2: トグルモード + ウインドウ表示 + 録音中**
- **入力**: triggerRecording キー押下
- **期待**: 録音停止 + statusMessage = "文字起こし中..." + isProcessing = true
- **実装根拠**: toggleRecording() で isRecording チェック → recorder.stopRecording() (line 242)
- **副作用**: ウインドウは表示したままの想定（ハンドラで触らない）

#### **シナリオ 1-3: プッシュトークモード + キー押下**
- **入力**: triggerRecording キー押下
- **期待**: ウインドウ表示 + 録音開始 + isTriggerShortcutPressed = true
- **実装根拠**: handleTriggerShortcutDown → pushToTalk case → showRecorderWindow() + toggleRecording() (line 328-329)

#### **シナリオ 1-4: プッシュトークモード + キー解放（録音中）**
- **入力**: triggerRecording キー解放
- **期待**: 録音停止 + statusMessage = "文字起こし中..."
- **実装根拠**: handleTriggerShortcutUp → pushToTalk モード確認 → isRecording 確認 → toggleRecording() (line 338-341)
- **副作用**: ウインドウは閉じない（キー解放では何もしない）

#### **シナリオ 1-5: disabled モード**
- **入力**: triggerRecording キー押下
- **期待**: なにもしない（ビープ音も鳴らない）
- **実装根拠**: handleTriggerShortcutDown → disabled case → break (line 321-322)

### 7.3 既存実装のテストシナリオ（toggleWindow）

#### **シナリオ 2-1: ウインドウ表示中**
- **入力**: toggleWindow キー押下
- **期待**: ウインドウ非表示
- **実装根拠**: handleToggleWindow() → window.isVisible → window.orderOut(nil) (line 441-442)
- **副作用**: 録音状態は変わらない。isProcessing も変わらない。

#### **シナリオ 2-2: ウインドウ非表示中**
- **入力**: toggleWindow キー押下
- **期待**: ウインドウ表示
- **実装根拠**: handleToggleWindow() → !window.isVisible → NSApplication.shared.setActivationPolicy(.regular) + window.makeKeyAndOrderFront(nil) (line 443-446)
- **副作用**: 録音状態は変わらない。

#### **シナリオ 2-3: ウインドウ未生成（初回起動時の特殊ケース）**
- **入力**: toggleWindow キー押下
- **期待**: ウインドウ作成 + 表示（フォールバック）
- **実装根拠**: handleToggleWindow() → guard let window → showRecorderWindow() (line 435-437)

### 7.4 統合仕様のテストシナリオ（案）

**仮定**: 新しい `KeyboardShortcuts.Name.integratedRecording` で「ウインドウ表示 + 録音開始」「停止時はウインドウを非表示」を実装する場合。

#### **シナリオ 3-1: 統合ショートカット + 非表示・停止状態 + トグルモード**
- **入力**: integratedRecording キー押下
- **期待**: ウインドウ表示 + 録音開始
- **テスト**: NSWindow.isVisible == true && AudioRecorder.isRecording == true

#### **シナリオ 3-2: 統合ショートカット + 表示・録音中 + トグルモード**
- **入力**: integratedRecording キー押下
- **期待**: 
  - **案A**: 停止 + ウインドウ非表示
  - **案B**: 停止のみ（ウインドウは表示のまま）
- **テスト**: AudioRecorder.isRecording == false。NSWindow.isVisible の期待値は要仕様確定。

#### **シナリオ 3-3: 統合ショートカット + プッシュトークモード**
- **入力**: キー押下 → キー解放
- **期待**:
  - キー押下: ウインドウ表示 + 録音開始
  - キー解放: 録音停止 + ウインドウ表示/非表示（案A or B）
- **テスト**: onKeyDown と onKeyUp の両方登録が必須

### 7.5 回帰テスト対象

| テスト項目 | 既存機能 | 統合後の懸念 |
|----------|---------|----------|
| 右 Option キー単体の動作 | handleFlagsChanged で別途監視 | 統合ショートカットと干渉しないか |
| ウインドウがない状態での KeyboardShortcuts イベント | onAppear で identifier 設定 | 統合時に identifier 処理が変わるか |
| UserDefaults キーの互換性 | 旧 "rightOptionMode" から読み込み | 旧 "KeyboardShortcuts_triggerRecording" 読み込みが必須か |
| 複数キープレス同時 | isTriggerShortcutPressed で重複防止 | 統合ショートカット + toggleWindow 同時押下時の挙動 |

---

## 8. 制約条件（再掲・詳細版）

### 8.1 状態管理フレームワークの制約

**@Published と @MainActor**:
- Coordinator は @MainActor クラス（SwiftUI UI スレッド更新が必須）
- KeyboardShortcuts ハンドラは Task { @MainActor } で囲む必要あり（現実装で守られている）
- 状態変更はメインスレッドのみ、それ以外は race condition リスク

### 8.2 UserDefaults キー管理の制約

**現状**:
```
KeyboardShortcuts ライブラリ: "KeyboardShortcuts_triggerRecording", "KeyboardShortcuts_toggleWindow"
shortcutTriggerMode: "shortcutTriggerMode"
右 Option 互換: "rightOptionMode"（廃止予定か）
```

**統合時の課題**:
- 複数ショートカット削除時、旧キーの存在チェック＆削除が必要
- または初期化時にマイグレーション（旧 → 新キー）を実装

### 8.3 ウインドウ識別子の制約

**現状**: identifier = "RecorderWindow"（行510）

**検索ロジック**:
```swift
NSApplication.shared.windows.first { window in
    window.identifier?.rawValue == "RecorderWindow"
}
```

**制約**:
- マルチウインドウ化時に識別子が一意でなくなる可能性
- SwiftUI の WindowGroup は各ウインドウに異なる identifier を自動割当すると不明確

---

## 9. 仕様策定への小人ちゃんからの提言

### 9.1 ショートカット名の方針（3案の比較）

#### **方針A: 既存 toggleWindow を統合機能化して triggerRecording を廃止**

**メリット**:
- 設定UI は単純（1 つのショートカットレコーダー）
- ショートカット名の変更で仕様の転換をユーザーに明示

**デメリット**:
- 既存ユーザーで triggerRecording に割り当てたキーが失われる
- 短期間に 2 つのショートカット仕様が急変（2026/4 月に toggleWindow 追加 → 数週間後に統合）
- マイグレーションコード実装負荷大

**推奨性**: **低**。既存ユーザーへの衝撃大。

---

#### **方針B: 新しい統合ショートカット名を追加して旧 2 つは互換のため残す**

**例**:
```swift
static let triggerRecording = Self("triggerRecording")  // 既存：互換のため残す
static let toggleWindow = Self("toggleWindow")          // 既存：互換のため残す
static let integratedRecording = Self("integratedRecording")  // 新：統合機能
```

**メリット**:
- 既存ユーザーの triggerRecording / toggleWindow の設定が有効のまま
- 新ユーザーまたは更新ユーザーは integratedRecording を利用
- 段階的な移行が可能

**デメリット**:
- ショートカット定義が 3 つに増加（複雑化）
- 旧 2 つと新 1 つの衝突回避ロジック必須（UI 警告の工夫が必要）
- ハンドラ登録コードが冗長化

**推奨性**: **中～高**。既存互換性とクリーンな新機能両立が可能。

---

#### **方針C: 既存の triggerRecording を統合機能化して toggleWindow を廃止**

**例**:
```swift
static let triggerRecording = Self("triggerRecording")  // 既存を再定義：統合機能へ
// toggleWindow は削除
```

**メリット**:
- 既存ユーザーの triggerRecording 割当が活かされる（ショートカットキーのポイント）
- 実装コードが最小（1 つのショートカット）

**デメリット**:
- triggerRecording の仕様が大きく変わる（「ウインドウ表示+録音」← 現「録音のみ」）
- 既存ユーザーで toggle/pushToTalk モードでウインドウを表示していた人の挙動が急変
  - → ウインドウ表示機能の不足（toggleWindow が廃止される）
- toggleWindow に割り当てたユーザーがいれば、その設定が失われる（まだ新機能なので少数の想定）

**推奨性**: **低～中**。既存 triggerRecording ユーザーへの影響大。

---

### 9.2 各方針のメリット・デメリット（表形式）

| 方針 | 追加設定UI | 複雑度 | 既存互換 | 学習曲線 | リスク |
|------|----------|--------|---------|---------|--------|
| **A** | 削除（triggerRecording） | 低 | **低** | 低 | **マイグレーション** |
| **B** | 追加（integratedRecording） | **高** | **高** | 中 | 衝突検出・複雑ロジック |
| **C** | 削除（toggleWindow）、再定義（triggerRecording） | 中 | 中 | **高** | 仕様急変・ユーザー混乱 |

---

### 9.3 **推奨方針: 方針B（新統合ショートカット + 旧2つ互換維持）**

**根拠**:
1. **既存ユーザー保護**: triggerRecording / toggleWindow の割当が有効のまま
2. **段階的移行**: ドキュメントで integratedRecording を推奨、旧 2 つは「非推奨」という段階的廃止戦略が可能
3. **新ユーザー向け**: 初期設定では integratedRecording のみをガイド、旧 2 つは「詳細設定」カテゴリ
4. **テスト焦点**: 衝突検出ロジック（旧と新で同じキー割当を防ぐ）に集中、実装リスクは限定的

**実装案**:
```swift
extension KeyboardShortcuts.Name {
    static let triggerRecording = Self("triggerRecording")           // 既存：互換
    static let toggleWindow = Self("toggleWindow")                   // 既存：互換
    static let integratedRecording = Self("integratedRecording")    // 新：推奨
}
```

**SettingsView の UI 改定案**:
```
--- ショートカット（新UI案）---

[ グループ1: 統合機能（推奨） ]
ショートカット：[KeyboardShortcuts.Recorder for .integratedRecording]
動作：[トグル / プッシュトーク / 無効] (既存の shortcutTriggerMode)
説明："このショートカットで『ウインドウ表示＋録音開始』『停止時にウインドウ非表示』を実行します"

[ グループ2: 従来の個別機能（詳細 / レガシー） ]
▼ 詳細オプションを表示...
  - 従来のショートカット（非推奨）：
    ・ショートカット：[KeyboardShortcuts.Recorder for .triggerRecording]
    ・ウインドウ表示トグル：[KeyboardShortcuts.Recorder for .toggleWindow]
```

**衝突検出ロジック**: KeyboardShortcuts.Recorder の組み込み機能で自動検出（既存）

---

### 9.4 **補助仕様：録音停止時にウインドウを閉じるかどうかの推奨**

#### **方針X: 停止 + 自動閉じ（推奨）**

**実装**:
```swift
private func handleIntegratedRecordingDown() async {
    if recorder.isRecording {
        await toggleRecording()  // 停止
        let recorderWindow = NSApplication.shared.windows.first { ... }
        recorderWindow?.orderOut(nil)  // 自動閉じ
    } else {
        showRecorderWindow()
        await toggleRecording()  // 開始
    }
}
```

**メリット**:
- ワークフロー直感的（「ショートカット 1 キーで全て完結」）
- ウインドウ管理が簡潔（録音終了 = 文字起こし結果は通知 or 入力済みなので表示不要）

**デメリット**:
- トグルモードとプッシュトークモード両方で同じ「閉じ」挙動が発生
  - → ユーザーが予期しない場合あり

**推奨性**: **高**

---

#### **方針Y: 停止のみ（ウインドウ表示のまま）**

**実装**:
```swift
private func handleIntegratedRecordingDown() async {
    if recorder.isRecording {
        await toggleRecording()  // 停止のみ
    } else {
        showRecorderWindow()
        await toggleRecording()  // 開始
    }
}
```

**メリット**:
- ウインドウは「意思を持つ」（ユーザーが toggleWindow で閉じるまで表示）
- 既存 handleToggleWindow の独立性を保持

**デメリット**:
- 統合ショートカットの意味が曖昧（「なぜウインドウ表示のままなのか」）
- ショートカット再押下時に「既に表示」か「非表示」か判定が不明確になる

**推奨性**: **低～中**

---

### 9.5 最終推奨仕様

| 項目 | 推奨 | 根拠 |
|------|------|------|
| **ショートカット名方針** | **方針B**: 新 integratedRecording + 旧 triggerRecording / toggleWindow 互換維持 | 既存ユーザー保護 + 段階的廃止 |
| **初期設定時のUI** | integratedRecording のみをデフォルト表示 | 新ユーザー向けシンプル性 |
| **詳細設定** | triggerRecording / toggleWindow を「非推奨」として別カテゴリに | 既存ユーザーのサポート |
| **停止時のウインドウ挙動** | **自動閉じ（方針X）** | ワークフロー直感性 |
| **shortcutTriggerMode** | 既存の disabled / toggle / pushToTalk を継続（integratedRecording に適用） | 既存モード資産を活かす |

---

## 10. 総括

### 10.1 調査結果の要点

1. **現在の実装**:
   - triggerRecording: ウインドウ表示 + 録音開始/停止（トグル/プッシュトーク）
   - toggleWindow: ウインドウ表示/非表示を純粋トグル（独立機能）
   - 両者は機能的に独立（ただし両方が showRecorderWindow() を呼ぶ）

2. **統合の主要課題**:
   - 既存ユーザーで triggerRecording に割り当てたキーの保持
   - ショートカット衝突検出ロジックの維持
   - 状態空間の複雑化（ウインドウ表示状態 × 録音状態 × モード の組み合わせ）

3. **技術的制約**:
   - KeyboardShortcuts ライブラリ（v2.4.0）の API は複数ショートカット共存対応
   - UserDefaults キー管理は自動化（旧キー互換性対応は手動実装）
   - NSApp ウインドウ管理は identifier ベース（マルチウインドウ考慮が必要）

4. **テスト対象**:
   - 統合ショートカット + 各モード（disabled / toggle / pushToTalk）での 8 シナリオ
   - ウインドウ可視状態 × 録音状態 × 処理状態 のマトリクス（最大 2×2×2=8 状態）
   - 右 Option キー、複数キー同時押下などの回帰テスト

### 10.2 次フェーズへの引き継ぎ

**Step 4（仕様確定）への引き継ぎ事項**:
- 方針B（新統合ショートカット + 旧2つ互換）の合意取得
- ウインドウ自動閉じ（方針X）の最終確認
- SettingsView の UI 改定案の詳細化
- UserDefaults マイグレーション戦略の確定

**Step 5（実装）への引き継ぎ事項**:
- 新 KeyboardShortcuts.Name.integratedRecording の追加
- handleIntegratedRecordingDown / Up の実装
- SettingsView のUI改定
- UserDefaults ロジックの修正
- テストシナリオの実装

---

## 付録A: ファイル行番号クイックリファレンス

| 機能 | ファイル | 行番号 |
|------|---------|--------|
| ショートカット定義 | TypeToTalkApp.swift | 6-7 |
| onKeyDown/onKeyUp 登録 | TypeToTalkApp.swift | 214-230 |
| handleTriggerShortcutDown | TypeToTalkApp.swift | 315-332 |
| handleTriggerShortcutUp | TypeToTalkApp.swift | 334-342 |
| handleToggleWindow | TypeToTalkApp.swift | 430-448 |
| toggleRecording | TypeToTalkApp.swift | 240-313 |
| showRecorderWindow | TypeToTalkApp.swift | 418-428 |
| SettingsView ショートカットUI | SettingsView.swift | 225-251（行227-232） |
| ShortcutTriggerMode enum | SettingsManager.swift | 119-136 |
| shortcutTriggerMode 初期化 | SettingsManager.swift | 229-232 |
| AudioRecorder.isRecording | AudioRecorder.swift | 45 |
| Coordinator.recorder | TypeToTalkApp.swift | 187 |
| TypeToTalkCoordinator.init | TypeToTalkApp.swift | 207-231 |

---

**文書作成完了**  
**調査の徹底度**: Very Thorough（全ハンドラ・状態管理・UI・設定・ライブラリ仕様を網羅）
