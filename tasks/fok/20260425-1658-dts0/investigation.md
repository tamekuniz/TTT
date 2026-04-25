# 調査レポート: マイクボタンパルス停止バグ

## 1. 関連ファイル一覧

| パス | 役割 |
|------|------|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` | メインUI＆アニメーション実装（L12 `@State private var isPulsing`、L42-80 マイクボタン＆onChange） |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/AudioRecorder.swift` | 録音状態管理（@Published `isRecording`） |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Package.swift` | プロジェクト設定（platforms: macOS .v14） |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/project.yml` | ビルド設定（deploymentTarget: macOS 14.0） |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Tests/TypeToTalkTests/AudioRecorderTests.swift` | 録音関連テスト（16/16 PASS） |

## 2. 既存実装パターン（完全再現）

### 現状コード（TypeToTalkApp.swift L12, 42-80）

```swift
struct TypeToTalkMainView: View {
    @ObservedObject var coordinator: TypeToTalkCoordinator
    @State private var isPulsing = false  // ← L12: パルス状態フラグ

    var body: some View {
        // ...
        Button { /* ... */ } label: {
            ZStack {
                Circle()
                    .fill(micButtonColor)
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    // L52-53: isPulsing 時のみ scale 1.08 / opacity 0.85 を適用
                    .scaleEffect(coordinator.recorder.isRecording && isPulsing ? 1.08 : 1.0)
                    .opacity(coordinator.recorder.isRecording && isPulsing ? 0.85 : 1.0)
                // ... ProgressView / mic.fill icon
            }
        }
        .onChange(of: coordinator.recorder.isRecording) { _, recording in
            if recording {
                // L72-74: 録音開始時、repeatForever で無限パルス開始
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                // L76-78: 録音終了時、easeInOut 0.2秒アニメで isPulsing = false に変更
                //         → ただし repeatForever は SwiftUI の既知挙動で値変更だけでは停止しない
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPulsing = false
                }
            }
        }
        // ...
    }
}
```

### 問題の根本原因

- **L72-74** の `withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isPulsing = true }` で implicit animation が開始される
- **L76-78** で `isPulsing = false` に変更しても、SwiftUI が既に登録した repeatForever アニメーションは独立して駆動し続ける（**既知の仕様**）
- `scaleEffect()` / `opacity()` の値が `isPulsing ? ... : ...` で条件分岐していても、repeatForever のアニメーションが引き続き値を変更し続けるため、実質的に止まらない

---

## 3. 影響範囲

### 呼び出し側（TypeToTalkApp.swift）

- **L70** `onChange(of: coordinator.recorder.isRecording)` トリガー
- **L42-66** マイクボタン（Circle + ProgressView + Icon）
- **L49-53** `.scaleEffect()` / `.opacity()` 適用箇所

### 依存先（AudioRecorder.swift）

- **L45** `@Published var isRecording = false` が `onChange` の監視対象
- **L83** `startRecording()` 内で `isRecording = true` をセット
- **L90** `stopRecording()` 内で `isRecording = false` をセット

### データフロー

```
AudioRecorder.isRecording
    ↓ (published)
TypeToTalkMainView.onChange(of: coordinator.recorder.isRecording)
    ↓ (reading isPulsing)
Button の .scaleEffect / .opacity
    ↓ (表示)
UI に反映
```

---

## 4. 過去の類似実装（git log より）

### コミット履歴

| コミット | 日付 | メッセージ | パルス関連の変更 |
|---------|------|----------|-----------------|
| `9d70ec7` | 2026-04-25 16:58 | [フォK] feat: マイクボタンUI改善＋権限ラベル微調整 | 色を .red → RGB(0.05, 0.35, 0.80) に変更のみ（パルス実装は据置） |
| `35fe441` | 2026-04-25 16:07 | [フォK] feat: モデル自動DL停止 | UI 無関係 |
| `16d3413` | 2026-04-25 15:12 | [フォK] feat: 権限動的チェック＋UI区別 | UI ロジック追加（パルス無関係） |
| `4b03313` | 2026-04-25 14:48 | [フォK] feat: TypeToTalk リファクタ完了 | 初版リファクタ（repeatForever 実装が導入された） |
| `ca4c764` | 2026-04-19 00:58 | Initial commit of TTT | 初期実装 |

**発見**: `4b03313` のコミットで `repeatForever` パターンが最初に導入され、以降そのまま継続している。過去に同様の停止バグが報告・修正された形跡はない（別案の実装はない）。

---

## 5. 想定される副作用 / リスク

### 修正による影響

| パターン | リスク | 実装への影響範囲 |
|---------|--------|-----------------|
| **パターン1（`withAnimation(nil)`）** | アニメーション無しで即座に 1.0/1.0 に戻る → 視覚的に「ガクン」と止まる可能性 | L76-77 の withAnimation 部分のみ |
| **パターン2（`.animation(value:)` に切替）** | modifier 順序が重要（scaleEffect/opacity より後ろに付ける必要あり） | L52-53, L70-80 両方の大幅修正 |
| **パターン3（`Double` で scale/opacity を State 化）** | State 追加（isScaleAnimating, isOpacityAnimating など）→ ロジック複雑化 | 全 onChange, modifier 書き換え |
| **パターン4（`withTransaction` 使用）** | SwiftUI 14+ で対応必要、動作確認要 | L76-78 修正 |

### リグレッション可能性

- 他のアニメーション（ProgressView, 色変更など）への干渉
- 連続 on/off サイクルでの状態リセット漏れ
- macOS 14.0 での互換性

---

## 6. 制約条件

### SwiftUI / macOS バージョン

| 項目 | 値 | 出典 |
|------|----|----|
| **最低 macOS バージョン** | 14.0 | project.yml L4-5、Package.swift L6-8 |
| **Swift バージョン** | 6.0 | project.yml L12、Package.swift L1 |
| **@State / @Published** | macOS 10.15+ で利用可（全バージョンで対応） | - |
| **`.animation(value:)` modifier** | macOS 12.0+ で利用可（L14.0 には十分） | - |
| **`withAnimation()` / `withTransaction()`** | macOS 10.15+ で利用可 | - |

### @MainActor 制約

- `TypeToTalkCoordinator` は `@MainActor` クラス（L189）
- `TypeToTalkMainView` は `View` ゆえ主スレッド上
- onChange 内の State 変更は自動的に MainActor で実行される（問題なし）

---

## 7. テスト戦略

### 実機確認ポイント

#### 7.1 基本フロー（受け入れ条件 1-3 の検証）

1. **パルス開始**
   - マイク権限許可状態で、マイクボタンをクリック
   - circle が 1.0 → 1.08 / opacity 1.0 → 0.85 で 0.8 秒往復を繰り返すか目視確認
   - Console に「recording in progress」的なログが出力されているか確認

2. **パルス停止（0.2 秒以内）**
   - 再度マイクボタンをクリック（停止）
   - scale / opacity が 0.2 秒以内に 1.0 / 1.0 に戻るか確認
   - その後、パルスが **完全に止まっているか**（再度伸び縮みしていないか）を 3 秒以上観察

3. **完全静止の確認**
   - マイクボタンが 1.0 / 1.0 のまま、以後アニメーションが見えないこと
   - この状態で 10 秒以上放置してもパルスが再開しないこと

#### 7.2 連続サイクル（受け入れ条件 4 の検証）

1. 開始 → 停止 → 開始 → 停止 を 5 回繰り返す
2. 毎回、停止後 0.2 秒で完全に静止するか確認
3. 3 サイクル目以降、残存アニメーションが累積していないか確認

#### 7.3 Console / Debugger ログ

```swift
// 修正後、以下の形でログを出力すると便利
onChange(of: coordinator.recorder.isRecording) { _, recording in
    if recording {
        print("DEBUG: パルス開始 (isPulsing = true)")
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    } else {
        print("DEBUG: パルス停止 (isPulsing = false)")
        withAnimation(...) {  // 修正内容に応じて
            isPulsing = false
        }
    }
}
```

#### 7.4 テスト自動化（UITest 案）

```swift
// 例: SwiftUI Preview でアニメーションの on/off を検証
#Preview {
    TypeToTalkMainView(coordinator: TypeToTalkCoordinator())
        .onAppear {
            // シミュレートして、isPulsing 値が 0.2 秒で flse に戻るか
        }
}
```

---

## 8. 推奨される修正パターン（候補比較）

### パターン 1: `withAnimation(nil)` で即座に停止

```swift
} else {
    withAnimation(nil) {  // アニメーション無し → 即座に 1.0 / 1.0
        isPulsing = false
    }
}
```

**メリット**
- 最小限の修正（1 行）
- repeatForever を明示的に停止できる（SwiftUI の既知パターン）

**デメリット**
- 視覚的に「ガクン」と止まる（0.2 秒のスムーズなトランジションが失われる）
- 要件「0.2 秒以内に滑らかに戻る」に微妙にそぐわない可能性

---

### パターン 2: `.animation(value:)` に切替え（推奨度★★★★★）

```swift
// L52-53 を修正
.scaleEffect(scale)  // isRecording && isPulsing ? 1.08 : 1.0 → computed property scale に
.opacity(opacity)

// L70-80 を修正
.animation(
    isPulsing 
        ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        : nil,
    value: isPulsing
)

// L70-80 onChange ロジックを簡略化
.onChange(of: coordinator.recorder.isRecording) { _, recording in
    if recording {
        isPulsing = true
    } else {
        isPulsing = false  // SwiftUI がアニメーション切り替えを自動で処理
    }
}
```

**メリット**
- SwiftUI が `isPulsing` の値に応じて自動的にアニメーションを切り替える
- 0.2 秒のスムーズなトランジション（別途定義可能）
- repeatForever を明示的に削除 → 停止保証
- 「状態と見た目が常に一致」という SwiftUI の原則に沿う

**デメリット**
- L52-53 の条件分岐を削除し、`scale` / `opacity` computed property を追加する必要がある
- 初期実装より複雑になる（ただし長期的には保守性が向上）

---

### パターン 3: `Double` State で直接制御

```swift
@State private var currentScale: CGFloat = 1.0
@State private var currentOpacity: Double = 1.0

.scaleEffect(currentScale)
.opacity(currentOpacity)

.onChange(of: coordinator.recorder.isRecording) { _, recording in
    if recording {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            currentScale = 1.08
            currentOpacity = 0.85
        }
    } else {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentScale = 1.0
            currentOpacity = 1.0
        }
    }
}
```

**メリット**
- 値を直接操作するので意図が明確

**デメリット**
- State が 2 個増える（管理負荷）
- 依然として repeatForever の停止問題が残る可能性（実装次第）

---

### パターン 4: `withTransaction` を使用

```swift
} else {
    var transaction = Transaction(animation: .easeInOut(duration: 0.2))
    transaction.disablesAnimations = false
    
    withTransaction(transaction) {
        isPulsing = false
    }
}
```

**メリット**
- Transaction レベルで explicit に制御
- macOS 14+ で動作確認可能

**デメリット**
- repeatForever 停止の確実性が不明（実装次第の検証が必要）
- コード量が増える

---

## まとめと推奨

### **最も推奨: パターン 2 (`.animation(value:)` 切替)**

**理由**:
1. SwiftUI の設計思想に最も準拠している（「値の変更に基づいてアニメーションが自動決定」）
2. repeatForever の独立駆動を根本的に排除できる（アニメーションそのものを値連動化）
3. 0.2 秒スムーズトランジションの要件を完全に満たす
4. 連続サイクルでのアニメーション累積リスクが最も低い
5. 将来の拡張（例：パルスをオフにしている状態での色変更アニメーション追加）に耐える

### 次点: パターン 1（即座停止）

- 要件「滑らかに戻る」が「完全静止」に読み替えられるなら、最小修正で対応可能

---

## 調査時点での制限事項

- 実機での repeatForever アニメーションの停止動作を確認していない（報告内容に基づく推定）
- SwiftUI の `.animation(value:)` 内での repeatForever 動作を確認していない（公式ドキュメント未確認）
- Xcode のデバッガで State 変更時の アニメーション stack を直接確認していない

**Step 4 の詳細実装で、パターン 2 の動作確認と実機検証を行うことを強く推奨**。

