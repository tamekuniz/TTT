# todo: マイクボタンパルス停止バグ修正

採用方針: **パターン2** (`.animation(value:)` ベースの implicit animation 切替)

> 調査レポート (`investigation.md` §8) の推奨。`repeatForever` を `withAnimation` 内で発火させるのをやめ、`.animation(value:)` modifier に「録音中なら repeatForever、それ以外なら一回限りの easeInOut(0.2)」という Animation 値を渡して切り替える。`isPulsing` の値変更だけでアニメ駆動が決まるため、録音終了時に repeatForever が独立駆動で残らない。

スコープ: `Sources/TypeToTalk/App/TypeToTalkApp.swift` のマイクボタンアニメーション制御部分のみ（L42-80 周辺）。

---

## タスク 1: パルス停止バグ修正（`.animation(value:)` ベースに切替）

### 対象ファイル

- `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`

### 編集箇所

#### A. `.scaleEffect` / `.opacity` の条件式を簡素化（L52-53 相当）

**Before:**

```swift
.scaleEffect(coordinator.recorder.isRecording && isPulsing ? 1.08 : 1.0)
.opacity(coordinator.recorder.isRecording && isPulsing ? 0.85 : 1.0)
```

**After:**

```swift
.scaleEffect(isPulsing ? 1.08 : 1.0)
.opacity(isPulsing ? 0.85 : 1.0)
```

理由: `isPulsing` の真偽だけで scale/opacity を決める。`isRecording` との AND 評価をやめ、State 単一ソースに寄せる。`isRecording` との同期は onChange に集約。

#### B. `.animation(value:)` modifier を `.opacity` の直後に追加

`.scaleEffect` と `.opacity` の **直後**（適用される側に modifier 順で後続する位置）に以下を追加:

```swift
.animation(
    coordinator.recorder.isRecording
        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        : .easeInOut(duration: 0.2),
    value: isPulsing
)
```

理由: `isPulsing` の値変更時にだけアニメーションが走る。録音中は repeatForever、録音終了直後は 0.2 秒の easeInOut で 1.0/1.0 へ滑らかに戻る。値変更が止まれば repeatForever も新規発火しない（SwiftUI が State 値ベースで管理するため、独立駆動で残らない）。

#### C. `.onChange(of: coordinator.recorder.isRecording)` 内ロジックを簡略化

**Before:**

```swift
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

**After:**

```swift
.onChange(of: coordinator.recorder.isRecording) { _, recording in
    isPulsing = recording
}
```

理由: アニメーション切替は `.animation(value:)` 側に集約済み。onChange は値同期だけに絞る。`withAnimation` 内で `repeatForever` を発火させるのが今回の根本原因なので、`withAnimation` 自体を撤去する。

---

### 実装上の留意点（小人ちゃんへ）

1. **modifier 順序が重要**: `.animation(value:)` は対象 modifier (`.scaleEffect` / `.opacity`) より **後ろ** に置く必要がある。Circle に対する modifier chain の順序を Read で正確に把握してから Edit すること。
2. **`isPulsing` の初期値は `false`** のまま。@State 宣言は変更しない。
3. **macOS 14.0+ で `.animation(value:)` は利用可能**（要件確認済み: investigation.md §6）。
4. **他の modifier（`.fill` / `.frame` / `.shadow` / ProgressView / icon）には触れない**。スコープ外。
5. **触覚フィードバック / ProgressView / 色 / アイコン / 録音操作**: 全て **触らない**。
6. もし modifier 順序の都合で `.animation(value:)` を Circle 単体ではなく ZStack 全体に掛けたほうが自然な場合は、その判断をしてよい。ただし副作用として ProgressView や icon にもアニメ干渉が起きていないか目視確認すること。

---

### 検証手順

#### 1. ビルド確認

```bash
cd /Users/tamekuniz/GitHub/tamekuniz/TTT && swift build
```

エラー / 警告ゼロで通ること。

#### 2. テスト実行

```bash
cd /Users/tamekuniz/GitHub/tamekuniz/TTT && swift test
```

既存 16 件 PASS（リグレッションなし）を確認。

#### 3. 実機 / 起動確認（受け入れ条件 1-4）

`swift run TypeToTalk` などでアプリを起動し、以下を目視確認:

- **受け入れ条件 1**: マイクボタン押下で scale 1.0↔1.08 / opacity 1.0↔0.85 のパルス開始（0.8 秒往復、繰り返し）
- **受け入れ条件 2**: 再度押下（録音終了）で **0.2 秒以内** に scale=1.0 / opacity=1.0 へ戻る
- **受け入れ条件 3**: 戻った後、3 秒以上観察してパルスが **完全静止** していること（再開しない）
- **受け入れ条件 4**: 開始 → 停止を 5 サイクル繰り返しても、毎回停止後 0.2 秒で完全静止すること

#### 4. パターン2 が機能しているかの検証

もし実機確認でパルスが止まらない場合:

- `.animation(value:)` の modifier 順序を見直す（`.scaleEffect` / `.opacity` の **後ろ** にあるか）
- `Animation` 値の三項演算子が録音終了時に正しく `.easeInOut(duration: 0.2)` 側に切り替わっているか（State 値の評価タイミング）
- それでも止まらない場合は investigation.md §8 のパターン1 (`withAnimation(nil)`) へフォールバックを検討（ただし要件「滑らかに戻る」は微妙にそぐわなくなる点を progress.md に明記）

---

### 受け入れ条件（requirements.md より）

1. 録音開始でパルス開始（scale 1.08 / opacity 0.85 で 0.8 秒往復、繰り返し）
2. 録音終了で 0.2 秒以内に scale=1.0 / opacity=1.0 へ戻る
3. 戻った後、それ以上パルス動作が見えない（完全静止）
4. 連続で録音開始/停止を繰り返してもパルスが残らない
5. ビルド成功 / `swift test` 16 件 PASS（リグレッションなし）

---

## スコープ外（明示的に触らない）

- 色変更（前フォKで対応済）
- アイコン種類変更
- 録音操作仕様変更
- 触覚フィードバック変更
- ProgressView / isProcessing 周辺
- 他の View / Manager / Test
