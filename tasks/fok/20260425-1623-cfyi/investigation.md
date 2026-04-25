# Step 3 調査: マイクボタン UI 改善（アイコン＆色）

## 1. 関連ファイル一覧（パス + 役割）

### UI 実装ファイル
- **`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`**
  - `TypeToTalkMainView`: マイクボタン本体の SwiftUI View
    - L42-66: Button label（ZStack）でマイクボタン実装
    - L49-53: パルスアニメーション制御（scaleEffect, opacity）
    - L60: アイコン分岐 `Image(systemName: coordinator.recorder.isRecording ? "stop.fill" : "mic.fill")`
    - L69: help修飾子（"録音開始 / 停止"）
    - L70-80: onChange(of: coordinator.recorder.isRecording)でパルストリガー
    - L113-123: micButtonColor private var（録音中は .red、待機で青系の2分岐）
  
  - `TypeToTalkCoordinator`: マイクボタン制御のロジッククラス
    - L191: @Published var recorder = AudioRecorder()
    - L244-316: toggleRecording() メソッド（録音開始・停止）
    - L200: @Published var isProcessing（文字起こし進行中フラグ）

### マイク・録音機能ファイル
- **`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AudioRecorder.swift`**
  - `@Published var isRecording = false` (L45)
  - `startRecording()` / `stopRecording()` で状態管理
  - L45-93: 録音ロジック（AVAudioEngine 使用）

### 設定・管理ファイル
- **`/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/WhisperManager.swift`**
  - @Published var whisperKit: WhisperKit? (L13)
  - マイクボタン色決定の条件: "whisperKit != nil" → 準備完了（鮮やかな青）

---

## 2. 既存実装パターン（命名・構造、SwiftUI のスタイル）

### マイクボタンの Color 制御パターン
```swift
private var micButtonColor: Color {
    if coordinator.recorder.isRecording {
        return .red  // ★ 現在: 赤一色（要変更）
    }

    if coordinator.whisper.whisperKit != nil {
        return Color(red: 0.10, green: 0.47, blue: 0.95)  // 準備完了: 鮮やかな青
    }

    return Color(red: 0.45, green: 0.83, blue: 0.98)  // 待機（未ロード）: 水色
}
```
- **特徴**: 3状態を Color で区別
  1. 録音中: `.red` (RGB(1.0, 0.0, 0.0))
  2. 待機・準備完了: RGB(0.10, 0.47, 0.95)
  3. 待機・未ロード: RGB(0.45, 0.83, 0.98)
- **マジックナンバー**: RGB 値を直書き（Color extension なし）

### アイコン分岐パターン
```swift
Image(systemName: coordinator.recorder.isRecording ? "stop.fill" : "mic.fill")
    .font(.system(size: 30, weight: .semibold))
    .foregroundStyle(.white)
```
- **現在**: 録音中は "stop.fill" に切替（SF Symbols）
- **要件**: 常に "mic.fill" のまま（変更のみ）

### パルスアニメーションの実装
```swift
// Circle の修飾子
.scaleEffect(coordinator.recorder.isRecording && isPulsing ? 1.08 : 1.0)
.opacity(coordinator.recorder.isRecording && isPulsing ? 0.85 : 1.0)

// トリガー: onChange で isPulsing 状態管理
.onChange(of: coordinator.recorder.isRecording) { _, recording in
    if recording {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    } else {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPulsing = false
        }
    }
}
```
- **条件**: `coordinator.recorder.isRecording && isPulsing`（両方真のときのみスケール）
- **タイミング**: isRecording → true に遷移したら、0.8 秒の easeInOut で repeatForever
- **停止時**: isRecording → false で、0.2 秒で isPulsing を false に（アニメーション終了）

### SwiftUI / @MainActor パターン
- `TypeToTalkCoordinator`: @MainActor クラス（全 @Published はメインスレッドで更新）
- View のリアクティブ性: @ObservedObject var coordinator で購読
- ボタンの disabled 状態: `.disabled(coordinator.isProcessing)` で文字起こし中はボタン無効化

### Accessibility 修飾子
- L69: `.help("録音開始 / 停止")` → macOS のツールチップ（VoiceOver でも読み上げ）
- **問題**: アイコンが "stop.fill" に変わっても、help は変わらない（矛盾）

---

## 3. 影響範囲（呼び出し側 / 依存先 / データフロー）

### マイクボタン色が参照されている場所
```
TypeToTalkMainView.body
  └─ Button { ... } label: { 
       ZStack {
         Circle().fill(micButtonColor)  ← ★ L49 でのみ使用
         ...
       }
     }
```
- **呼び出し箇所**: L49 のみ（Circle の .fill 修飾子で使用）
- **依存先**: 
  - `coordinator.recorder.isRecording` (AudioRecorder.@Published)
  - `coordinator.whisper.whisperKit` (WhisperManager.@Published)
  - これら 2 つの状態で 3 段階の色を決定

### アイコン分岐が参照されている場所
```
TypeToTalkMainView.body
  └─ ZStack {
       // ...
       if coordinator.isProcessing { ... }
       else {
         Image(systemName: coordinator.recorder.isRecording ? "stop.fill" : "mic.fill")
            ↑ L60 でのみ使用
       }
     }
```
- **呼び出し箇所**: L60 のみ（isProcessing が false のときだけ表示）
- **依存先**: 
  - `coordinator.recorder.isRecording` (AudioRecorder.@Published)
  - `coordinator.isProcessing` (TypeToTalkCoordinator.@Published)

### パルスアニメーション
```
.scaleEffect(coordinator.recorder.isRecording && isPulsing ? 1.08 : 1.0)
.opacity(coordinator.recorder.isRecording && isPulsing ? 0.85 : 1.0)
  ↑ L52-53: Circle（背景）に適用
```
- **トリガー**: onChange で isPulsing State を管理（L70-80）
- **条件**: `coordinator.recorder.isRecording && isPulsing` の両方が true のときのみアニメーション

### データフロー図
```
[ユーザーがマイクボタンをクリック]
  ↓
Button action → coordinator.toggleRecording()
  ├─ recorder.startRecording()
  │   └─ isRecording = true（@Published）
  │       ↓
  │   onChange(of: isRecording) トリガー
  │   └─ isPulsing = true（withAnimation）
  │       └─ scaleEffect / opacity 更新（L52-53）
  │       └─ micButtonColor 更新（L49）
  │       └─ Image systemName 更新（L60）← ★ "stop.fill" に切替
  │
  └─ recorder.stopRecording()
      └─ isRecording = false
          ↓
          onChange トリガー
          └─ isPulsing = false
              └─ パルス停止、色も待機状態に戻る
```

---

## 4. 過去の類似実装（git log でマイクボタン関連コミット）

### git log 検索結果
```
aac4a7a [フォK] feat: モデル自動DL停止、ローカル存在時のみ自動ロード
35fe441 [フォK] feat: 権限動的チェック＋UI区別＋触覚/視覚フィードバック
16d3413 [フォK] feat: UI整理＋言語設定＋整形プロンプト構造化
4b03313 [フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加
cb281cf Refactor: Modularize project structure (App, Managers, Models, Views) for high maintainability
db58908 Implement Settings UI for API keys and custom prompts
ca4c764 Initial commit of TTT (Talk to Type) macOS app
```

### マイクボタン関連の主要コミット
- **4b03313**: TypeToTalk リファクタ完了
  - TTT → TypeToTalk にリネーム
  - マイクボタン UI の基本形（stop.fill / mic.fill 分岐）がここで確定
  - Color 定義パターン（RGB 直書き）も導入

- **35fe441**: 権限動的チェック＋触覚/視覚フィードバック
  - マイクボタン周辺では特に変更なし（AccessibilityManager 追加が中心）
  - help 修飾子（"録音開始 / 停止"）の確認なし（恐らく既に存在）

- **16d3413**: UI整理＋言語設定
  - SettingsView の整理が中心
  - マイクボタン本体への変更なし

### 重要な知見
- **マイクボタンの stop.fill / mic.fill 分岐は初期実装（ca4c764）から存在**
- **RGB 色の定義パターンは 4b03313 で確定**
- **過去に「赤から青へ」「アイコン統一」などの議論がなかった**
  - 初回リリース時点では、このデザイン（stop.fill + 赤）が意図的だった？
  - または、UI/UX 改善タスクとしては初めての対応

---

## 5. 想定される副作用 / リスク（既存ユーザー体験変化、アクセシビリティ）

### 既存ユーザーへの体験変化

#### 変更前（現状）
- **アイコン**: 待機中 `mic.fill`（マイク）→ 録音中 `stop.fill`（停止）
- **色**: 待機中 水色 or 青 → 録音中 赤
- **心理**: 「停止アイコン + 赤」で「今は停止操作ができる状態」を暗示

#### 変更後（要件）
- **アイコン**: 常に `mic.fill`（マイク）
- **色**: 待機中 水色 or 青 → 録音中 濃い青
- **心理**: 「常にマイク」で「マイク機能の活度」を示す、色で「強度」を表現

### 影響パターン

| シナリオ | 従来の挙動 | 変更後の挙動 | ユーザー感 |
|---------|---------|---------|---------|
| 初回クリック（録音開始） | マイク → 停止アイコン + 赤 + パルス | マイク + 濃い青 + パルス | 「停止アイコンがないので心理的に分かりやすい」 |
| もう一度クリック（録音停止） | 停止 → マイク + 水色/青 | 濃い青 → 水色/青 | 「色だけで状態が変わる（アイコン統一で悪くない）」 |
| ダークモード / ライトモード | RGB 色なので不変 | RGB 色なので不変 | 「変化なし」 |

### アクセシビリティへの影響

#### 現状（stop.fill 使用時）
```swift
.help("録音開始 / 停止")
```
- VoiceOver が読み上げるテキスト: 「録音開始 スラッシュ 停止」
- アイコン名: VoiceOver が "stop.fill" をそのまま読む可能性（言語化されない）
- **問題**: 実際には「この時点での操作は停止」なのに、待機時は "mic.fill" が読まれ、混乱する

#### 変更後（mic.fill 統一）
```swift
.help("録音開始 / 停止")
```
- VoiceOver が読み上げるテキスト: 「録音開始 スラッシュ 停止」（同じ）
- アイコン名: VoiceOver が常に "mic.fill" を読む
- **改善**: 
  - アイコンが一貫性あり（常に マイク）
  - help テキストと実装の矛盾がない
  - **ただし** help テキストで「開始 / 停止」と両方書くより、`accessibilityHint()` で「録音 ON/OFF の切り替え」を追加すると更に改善

#### 推奨アクセシビリティ対応
```swift
.help("録音開始 / 停止")
.accessibilityHint(coordinator.recorder.isRecording ? "録音中。クリックで停止" : "クリックで録音開始")
```

### 色の区別可能性（アクセシビリティ基準）
- **WCAG 2.1 AA**: 色のみで情報を伝えない（形や テキスト併用推奨）
- **現状**: マイクボタンは色のみで状態区別 → OK（help テキストが補助）
- **変更後**: 同じく色のみ → OK（help + accessibilityHint で補助可）
- **対比**:
  - 水色 RGB(0.45, 0.83, 0.98) vs 濃い青 RGB(0.05, 0.35, 0.80)
  - 濃い青 RGB(0.05, 0.35, 0.80) vs 鮮やかな青 RGB(0.10, 0.47, 0.95)
  - いずれも十分な視覚的差異がある

---

## 6. 制約条件（命名規約 / SwiftUI / @MainActor / アクセシビリティ）

### SwiftUI / @MainActor の制約
- `TypeToTalkCoordinator`: @MainActor クラス
- すべてのマイクボタン制御ロジックは MainActor に束縛（Thread safety 確保）
- @Published プロパティの更新は自動的に View 再描画

### 命名規約（既存）
- **Color**: `micButtonColor` （private var）
  - 用途が明確（マイクボタン専用）
  - 変更時は メソッド/プロパティ名は変わらない（内部実装のみ）

- **State**: `isPulsing`（@State private）
  - View ローカルな状態管理
  - パルスアニメーション ON/OFF の切り替え

- **@Published**: `isRecording` / `isProcessing`
  - Coordinator が発行（AudioRecorder / Coordinator 自身から）
  - View が購読

### SwiftUI Animation の制約
```swift
.scaleEffect(coordinator.recorder.isRecording && isPulsing ? 1.08 : 1.0)
.opacity(coordinator.recorder.isRecording && isPulsing ? 0.85 : 1.0)
.onChange(of: coordinator.recorder.isRecording) { _, recording in
    if recording {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    } else {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPulsing = false
        }
    }
}
```
- **制約**: `isPulsing` State は View ローカル（複数View 間で共有不可）
- **easeInOut(duration: 0.8)**: 0.8 秒で拡大・縮小往復
- **repeatForever(autoreverses: true)**: 無限ループ（autoreverses で自動往復）
- **変更時**: パルス周期 / サイズは同じく維持（要件で明記）

### Color 定義の制約
- **RGBマジックナンバー**: Color(red: 0.xx, green: 0.xx, blue: 0.xx)
- **拡張性**: Color extension を作成することも可能（ただし 現状では 3 値のみ）
- **将来**: 6 段階以上の色が必要な場合は、Color extension 導入を検討

### iOS / macOS の互換性
- このアプリは **macOS アプリ** (AppKit)
- SF Symbols ("mic.fill", "stop.fill") は macOS 11+ で利用可能
- `help()` 修飾子は **macOS固有** （iOS では `.accessibilityLabel()` / `.accessibilityHint()` 推奨）

---

## 7. テスト戦略（実機確認ポイント）

このプロジェクトは SwiftUI アプリで、UI テストは実機 / シミュレータでの手動確認が主。

### T1. アイコンの統一確認

#### T1-1: 待機状態（未ロード）
- [ ] アプリ起動時、マイクボタンのアイコンが `mic.fill` であることを確認
- [ ] 色が水色 RGB(0.45, 0.83, 0.98) であることを確認（視覚的に）

#### T1-2: 待機状態（準備完了）
- [ ] Whisper モデルロード後、マイクボタンの色が鮮やかな青 RGB(0.10, 0.47, 0.95) に変わることを確認
- [ ] **アイコンは依然 `mic.fill` のまま**（stop.fill に変わらない）

#### T1-3: 録音中（クリック後）
- [ ] マイクボタンをクリック → 録音開始
- [ ] アイコンが `mic.fill` **のまま**（従来の stop.fill ではない）を確認
- [ ] 色が濃い青 RGB(0.05, 0.35, 0.80) に変わることを確認

#### T1-4: 録音停止（再クリック）
- [ ] 再度マイクボタンをクリック → 録音停止
- [ ] アイコンが mic.fill のまま（変化なし）を確認
- [ ] 色が待機状態（鮮やかな青）に戻ることを確認

### T2. パルスアニメーション確認

#### T2-1: 待機状態ではパルスなし
- [ ] アプリ起動時（未ロード）、マイクボタンに拡大・縮小の動きがないことを確認
- [ ] 待機状態でも拡大・縮小なし

#### T2-2: 録音中のみパルス
- [ ] マイクボタンクリック → 録音開始
- [ ] マイクボタンが 1.08 倍に拡大（scaleEffect 1.08）
- [ ] 同時に透過度が 0.85（やや透明）になることを確認
- [ ] 0.8 秒周期で往復（拡大→縮小→拡大→...）を繰り返す

#### T2-3: パルス停止確認
- [ ] 再度クリック → 録音停止
- [ ] パルスが **滑らかに** 停止（0.2 秒で通常サイズに戻る）
- [ ] その後、待機状態に戻る

### T3. 色の見た目確認（RGB 値の微調整用）

#### T3-1: 待機・未ロード（現仕様: RGB(0.45, 0.83, 0.98)）
- [ ] 水色（薄い青）に見えることを確認
- [ ] 視認性が良好（背景コントラスト OK）

#### T3-2: 待機・準備完了（現仕様: RGB(0.10, 0.47, 0.95)）
- [ ] 鮮やかな青に見えることを確認
- [ ] RGB(0.45, 0.83, 0.98) より濃い青（視覚的に明らかに区別可能）

#### T3-3: 録音中（新規: RGB(0.05, 0.35, 0.80)）
- [ ] 濃い青に見えることを確認
- [ ] RGB(0.10, 0.47, 0.95)「準備完了」より濃い（要件の「濃いめの青」を満たす）
- [ ] **赤系ではない**（従来の .red との大きな違い）
- [ ] 3 段階が視覚的に明らかに異なることを確認

#### T3-4: 色の段階感
```
未ロード: RGB(0.45, 0.83, 0.98)  ← 最も薄い水色
待機:     RGB(0.10, 0.47, 0.95)  ← 鮮やかな青
録音中:   RGB(0.05, 0.35, 0.80)  ← 最も濃い青
```
- [ ] 左から右へ順に濃くなる勾配が自然か、微調整が必要か判断

### T4. アクセシビリティ確認

#### T4-1: VoiceOver（macOS）
- [ ] VoiceOver 有効化
- [ ] マイクボタンにフォーカス
- [ ] 読み上げ: 「録音開始 スラッシュ 停止」（help テキスト）
- [ ] **差分**: 従来の「停止（アイコン名）」が「マイク（アイコン名）」に統一されるはず

#### T4-2: ボタン操作感（keyboard focus）
- [ ] Tab キーでマイクボタンにフォーカス可能か
- [ ] Space / Enter で実行可能か
- [ ] ボタンの visible frame（contentShape）が適切か

### T5. 色覚多様性への対応

#### T5-1: 色覚特性（色盲・色弱）シミュレーション
- [ ] macOS 設定 → アクセシビリティ → ディスプレイ → 色フィルタ
  - 「プロターノピア」（赤色盲）
  - 「デューテロアノピア」（緑色盲）
  - 「トリタノピア」（青黄色盲）
- [ ] いずれのフィルタでも 3 段階の色が区別可能か確認

#### T5-2: コントラスト
- [ ] ライトモード・ダークモード両方で視認性を確認
- [ ] 背景（白 or 暗い色）とマイクボタンのコントラスト比が 3:1 以上か

### T6. リグレッション確認

#### T6-1: ボタン機能は変わらない
- [ ] クリック → 録音開始 → 文字起こし実行（従来通り）
- [ ] キーボードショートカット（triggerRecording）でも動作
- [ ] 「右Option キー」長押しでも動作（pushToTalk）

#### T6-2: 色・アイコン以外の見た目
- [ ] マイクボタンのサイズ（88x88）変わらず
- [ ] シャドウ（shadow: 4px, y: 2px, opacity: 0.15）変わらず
- [ ] SettingsView / Formatter 表示は影響なし

---

## 補足: 深掘り結果（A, B, C の詳細）

### A. マイクボタン UI の全体フロー

```
[View Mount]
  ↓
TypeToTalkMainView
  @ObservedObject var coordinator: TypeToTalkCoordinator
  @State private var isPulsing = false
  ↓
Button {
  await coordinator.toggleRecording()
} label: {
  ZStack {
    Circle()
      .fill(micButtonColor)          ← ★ L49
      .scaleEffect(...isPulsing...)  ← ★ L52
      .opacity(...isPulsing...)      ← ★ L53
    Image(systemName: condition ? "stop.fill" : "mic.fill")  ← ★ L60
  }
}
.onChange(of: coordinator.recorder.isRecording) { _, recording in  ← ★ L70
  if recording {
    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
      isPulsing = true  ← ★ scaleEffect / opacity トリガー
    }
  } else {
    withAnimation(.easeInOut(duration: 0.2)) {
      isPulsing = false  ← ★ パルス停止
    }
  }
}
```

**要件変更時の修正点:**
- L49: `micButtonColor` の実装 → 録音中を `.red` から `Color(red: 0.05, green: 0.35, blue: 0.80)` へ変更
- L60: `coordinator.recorder.isRecording ? "stop.fill" : "mic.fill"` → 常に `"mic.fill"` へ変更
- L70-80: パルスロジックは **そのまま維持**

### B. パルスアニメーションの正確な制御

**トリガー条件**:
```swift
.scaleEffect(coordinator.recorder.isRecording && isPulsing ? 1.08 : 1.0)
```
- `coordinator.recorder.isRecording` = true かつ
- `isPulsing` = true
- **両方真のときのみ 1.08 倍に**

**否定論理**:
- 待機中（isRecording=false）: scaleEffect は 1.0（効果なし）
- 録音開始時（isRecording=true, isPulsing まだ false）: scaleEffect 1.0 → 0.8 秒で 1.08 へ段階的に拡大
- 録音中（both true）: 1.08 ↔ 1.0 を 0.8 秒周期で往復
- 録音停止時（isRecording=false）: withAnimation が 0.2 秒で isPulsing=false に切り替え → scaleEffect 1.0 に戻る

**重要**: 単に `isPulsing` のみで判定しているのではなく、`coordinator.recorder.isRecording && isPulsing` で **両条件が必須**

### C. 色定義の拡張可能性

**現状パターン** (3 色直書き):
```swift
private var micButtonColor: Color {
    if coordinator.recorder.isRecording {
        return .red
    }
    if coordinator.whisper.whisperKit != nil {
        return Color(red: 0.10, green: 0.47, blue: 0.95)
    }
    return Color(red: 0.45, green: 0.83, blue: 0.98)
}
```

**将来の拡張案** (Color extension 使用):
```swift
extension Color {
    static let micButtonIdleNotLoaded = Color(red: 0.45, green: 0.83, blue: 0.98)
    static let micButtonReady = Color(red: 0.10, green: 0.47, blue: 0.95)
    static let micButtonRecording = Color(red: 0.05, green: 0.35, blue: 0.80)
}

private var micButtonColor: Color {
    if coordinator.recorder.isRecording {
        return .micButtonRecording
    }
    if coordinator.whisper.whisperKit != nil {
        return .micButtonReady
    }
    return .micButtonIdleNotLoaded
}
```
- **メリット**: 
  - 色値を一元管理できる
  - 命名が明確（目的が分かる）
  - 他の UI で同じ色を再利用可能
- **デメリット**: 
  - 3 値のみなら直書きでも問題ない
  - 段階的にリファクタ可能

---

## 結論: 不確かな点 & 安全側の指針

### 不確か

1. **アイコン "mic.fill" の表示確認**:
   - 実装では `Image(systemName: ...)` で SF Symbols を使用
   - macOS 11+ では問題なく表示されるはずだが、ターゲット OS の確認が必要
   - → **実機確認で確認すること**

2. **RGB 値 RGB(0.05, 0.35, 0.80) の視認性**:
   - 要件では「濃い青」と記載（参考値）
   - 実際の見た目は ライトモード・ダークモード・ディスプレイによって異なる
   - → **実機確認で微調整が必要** (Step 8 で実施)

3. **アクセシビリティ修飾子の最適化**:
   - 現状 `.help("録音開始 / 停止")` のみ
   - VoiceOver で「開始 / 停止」の区別が正確に読まれるか不確か
   - → **accessibilityHint() 追加を推奨** (Step 4 の設計で決定)

### 安全側の指針

1. **変更の最小化**: 
   - L49 と L60 の 2 箇所のみ修正
   - L70-80 のパルスロジックには手を入れない

2. **パルスアニメーション維持**:
   - scaleEffect(1.08), opacity(0.85), duration(0.8), repeatForever は必ず維持
   - 色変更でアニメーション周期は変えない

3. **テスト優先**:
   - 実装前に「アイコン統一・色変更」のみで Step 4 デザイン確認
   - Step 8 実機確認で RGB 値を微調整

---

## 関連情報・参考資料

- **SF Symbols**: macOS 11.0 以降で mic.fill / stop.fill 利用可能
- **Color(red: green: blue:)**: SwiftUI の RGB Color 初期化（0.0-1.0 の Float）
- **@State vs @Published**: 
  - isPulsing は View ローカル → @State (L12)
  - isRecording は Coordinator が発行 → @Published（複数 View で購読）
- **withAnimation()**: SwiftUI の暗黙的アニメーション制御（修飾子と併用）
