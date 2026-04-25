# TypeToTalkMainView Text 削除調査レポート

日時: 2026-04-25
調査者: マンゴーの小人（関西弁）
要件: TypeToTalkMainView から `Text("ショートカットで呼び出すと、このダイアログを前面に出します")` と関連修飾子（`.font(.caption)`, `.foregroundStyle(.secondary)`, `.multilineTextAlignment(.center)`）を削除する

---

## 1. 関連ファイル一覧

### 削除対象ファイル
- **ファイルパス**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift`
- **削除行番号**: L90–L93
  ```swift
  Text("ショートカットで呼び出すと、このダイアログを前面に出します。")
      .font(.caption)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
  ```

### 同文言の他箇所参照確認
- **grep 検索結果**: 同じ文言「ショートカットで呼び出すと、このダイアログを前面に出します」は、TTT プロジェクト全体で 1 箇所のみ
  - 唯一の出現場所: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift:90`
- **関連する他の「ショートカット」テキスト**: SettingsView（L235, L248, L254）に「ショートカット」という単語が存在するが、削除対象テキストとは異なる内容
  - L235: `settingRow("ショートカット")` – キーボードショートカット設定ラベル
  - L248: `Text("任意のショートカットに加えて、右 Option 単体でも...")` – ショートカット説明文
  - L254: `sectionTitle("ショートカット", subtitle: "録音の開始方法")` – セクション見出し

### 影響を受けるファイル
- **直接削除対象**: TypeToTalkApp.swift のみ
- **ビルド・テスト関連**:
  - `/Users/tamekuniz/GitHub/tamekuniz/TTT/scripts/build_app.sh` – ビルドスクリプト（xcodegen 経由）
  - `/Users/tamekuniz/GitHub/tamekuniz/TTT/project.yml` – XcodeGen 設定
  - `/Users/tamekuniz/GitHub/tamekuniz/TTT/Tests/TypeToTalkTests/ModelSelectionTests.swift` – ユニットテスト（TypeToTalkMainView を直接テストしない）
  - `/Users/tamekuniz/GitHub/tamekuniz/TTT/Tests/TypeToTalkTests/AudioRecorderTests.swift` – ユニットテスト（TypeToTalkMainView を直接テストしない）
- **UI 参照**:
  - SettingsView.swift – 関連なし（別のショートカット説明を持つ）

---

## 2. 既存実装パターン

### VStack 構造（親レイアウト L15–L95）
```
VStack(spacing: 18) {                      // L16: 親の最上位 VStack
    HStack(alignment: .top) { ... }        // L17–L38: ステータス表示 + 設定ボタン
    
    Button { ... } label: { ... }          // L41–L77: マイクボタン（88×88）
    
    VStack(spacing: 10) {                  // L79: 内部 VStack（※削除対象テキストを含む）
        modelStatusRow(...)                // L80–L84: Whisper 状態行
        modelStatusRow(...)                // L85–L89: Formatter 状態行
        Text("ショートカットで呼び出すと...")  // L90–L93: 削除対象テキスト
    }
}
.padding(20)                               // L96
.frame(width: 360, height: 300)            // L97
```

### Text 要素の修飾子パターン
削除対象の Text の修飾子は、他の説明的なテキスト要素と同じパターンを使用：

```swift
// L90–L93（削除対象）
Text("ショートカットで呼び出すと、このダイアログを前面に出します。")
    .font(.caption)                    // キャプション（小さいフォント）
    .foregroundStyle(.secondary)       // グレーアウト（説明文の標準スタイル）
    .multilineTextAlignment(.center)   // 中央揃え

// 比較: SettingsView 内の説明文パターン（L89, L217, L223 など）
Text("選択した Whisper モデルをローカルにダウンロードして使います...")
    .font(.caption)
    .foregroundStyle(.secondary)
```

### modelStatusRow() メソッドの内部構造（L122–L148）
```swift
private func modelStatusRow(
    title: String,
    detail: String,
    status: String
) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 3) { ... }
        Spacer()
        VStack(alignment: .trailing, spacing: 6) { statusBadge(status) }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(RoundedRectangle(...))
}
```

---

## 3. 影響範囲

### レイアウト崩れのリスク評価

**削除前**: 
- VStack(spacing: 10) の子要素 × 3 個
  1. modelStatusRow（Whisper）
  2. modelStatusRow（Formatter）
  3. Text（削除対象テキスト）

**削除後**:
- VStack(spacing: 10) の子要素 × 2 個
  1. modelStatusRow（Whisper）
  2. modelStatusRow（Formatter）

**予想される表示変化**:
- 削除対象 Text が画面から消える
- VStack(spacing: 10) の最後の要素が modelStatusRow になる
- 親 VStack(spacing: 18) のスペーシングは変わらない（最上位の 4 つの要素が 3 つになるのみ）
- **レイアウト崩れの可能性**: **非常に低い** – spacing 値は両方の VStack で自動で適用され、要素が減るだけでは破損しない

### 他からの参照確認
- **直接参照**: なし（削除対象 Text は View 定義内のリテラルで、他から参照されていない）
- **名前付きリソースへの参照**: なし（LocalizedStringResource などを使用していない）
- **UI テストでの参照**: テストファイル内に TypeToTalkMainView を検証するテストなし（ModelSelectionTests, AudioRecorderTests は Coordinator・Manager の動作テスト）

---

## 4. 過去の類似実装

### 当該テキスト追加コミット
**コミットID**: `4b0331319f4fdf9fe2557cc58d790d977b5e9787`
**日時**: Sat Apr 25 13:37:25 2026 +0900
**コミットメッセージ**: 
```
[フォK] feat: TypeToTalk リファクタ完了＋整形AI整合性とウインドウトグル追加

- TTT → TypeToTalk リネーム（旧 Sources/TTT/ 削除、新 Sources/TypeToTalk/ 配置）
- ...
- T3: ウインドウ表示トグル用ショートカット toggleWindow を新規追加
       （既存 triggerRecording はそのまま、SettingsView に Recorder UI 追加、
       デフォルトキー未割当、録音状態には触らない設計）
```

**追加時のコンテキスト**:
当該テキストは、初回リファクタ時に toggleWindow ショートカット機能の説明として導入されました。git log で確認した diff より：
```diff
+                Text("ショートカットで呼び出すと、このダイアログを前面に出します。")
+                    .font(.caption)
+                    .foregroundStyle(.secondary)
+                    .multilineTextAlignment(.center)
```

### 関連する後続コミット
以下のコミットで当該テキストの周辺は修正されたが、テキスト自体は削除されずに残存：
- `9c10aed` – ショートカットを triggerRecording 1 つに統合
- `c57309d` – ウインドウタイトルを Mac 標準タイトルバーに移行
- `a578b32` – Bonsai 状態伝播＋自動ロード健全化

**当該テキストに対する削除要求**: 
- 本要件（Step 3）が初めての削除要求
- 過去のコミットログに「ショートカットで呼び出すと」に関する削除・修正はなし

---

## 5. 想定される副作用 / リスク

### VStack の spacing 影響
- **親 VStack(spacing: 18)**: 
  - 現在: HStack (L17–L38) → spacing 18 → Button (L41–L77) → spacing 18 → VStack (L79–L94) → padding(20)
  - 削除後: HStack → spacing 18 → Button → spacing 18 → VStack (modelStatusRow × 2) → padding(20)
  - **副作用**: なし。最上位の論理的構造は変わらない

- **内部 VStack(spacing: 10)**: 
  - 現在: modelStatusRow × 2 + Text（削除対象）
  - 削除後: modelStatusRow × 2
  - **副作用**: なし。spacing 値が自動で子要素間に適用されるため、要素削除で spacing が悪影響を受けない

### Visual Appearance への影響
- **削除対象テキストの消失**: ダイアログ下部の説明文が画面から消える
  - 消失するテキスト内容: 「ショートカットで呼び出すと、このダイアログを前面に出します。」
  - ユーザーへの説明が減少（ショートカット動作の説明が削除される）
  
- **残存要素の動き**: Whisper, Formatter ステータス行は表示位置が若干上がる（Text 削除による空間確保）

### 機能への影響
- **なし**: View 定義のみの削除で、Coordinator・Manager などのビジネスロジックには影響なし
- **ショートカット動作**: triggerRecording, 右 Option キーの動作は TypeToTalkCoordinator の handleTriggerShortcutDown() / handleTriggerShortcutUp() で定義されており、変わらない

### 潜在的リスク
1. **ユーザーへの説明不足**: 説明文削除でユーザー向けドキュメント内容が減少
   - **対策**: SettingsView や外部マニュアルで説明補足が必要な可能性
2. **ローカライズの考慮**: 削除対象テキストが多言語対応されていた場合、多言語リソースから削除し忘れのリスク
   - **確認**: Localizable.strings などのリソースファイルをスキャン→ 確認結果：テキストはリテラル定義で、多言語リソースなし
3. **アクセシビリティラベル**: Text 要素の削除で、スクリーンリーダーが読み上げる説明が減少
   - **確認**: 削除対象 Text に `.accessibilityLabel()` や `.accessibilityHint()` は付与されていない（画面説明の補助テキスト扱い）

---

## 6. 制約条件

### SwiftUI 規約
1. **View の構造**: TypeToTalkMainView は `struct TypeToTalkMainView: View` で定義
   - View protocol を厳密に守る必要あり
   - 削除後も View の body は有効な SwiftUI View を返す必要あり
   - **確認**: 削除後も VStack(spacing: 10) は 2 つの有効な View 要素（modelStatusRow 呼び出し）を持つため問題なし

2. **修飾子チェーン**: 削除対象 Text と修飾子（.font, .foregroundStyle, .multilineTextAlignment）は一体削除
   - **制約**: 修飾子だけを削除して Text を残すことは不可
   - **現要件**: テキスト + 修飾子を全削除で問題なし

### 削除以外触らない原則
- **他の行番号の修正**: L79–L94 の VStack 内で、modelStatusRow 呼び出しやその他要素に変更を加えない
- **親 VStack の修正**: L16 の spacing: 18 など親の構造は変更しない
- **メソッドシグネチャ変更**: modelStatusRow() の引数・戻り値は変更しない

---

## 7. テスト戦略

### Unit Test
- **対象**: TypeToTalkApp.swift の View 構造には現在ユニットテストなし
- **理由**: SwiftUI View のテストは実機・シミュレータでの目視が標準的
- **Action**: 削除後、ModelSelectionTests, AudioRecorderTests は変更不要（Coordinator・Manager 層をテストしており、UI 非依存）

### ビルド確認
1. **コマンド**: `./scripts/build_app.sh` (Debug mode)
2. **期待値**: コンパイルエラーなし、ビルド成功
3. **検査項目**:
   - Swift コンパイラがテキスト削除を受け入れるか
   - 削除後 VStack の構文が正しいか
   - Xcode による自動補完・修正なし

### 実機目視確認
1. **削除後の画面表示**:
   - Whisper ステータス行が表示されているか
   - Formatter ステータス行が表示されているか
   - 「ショートカットで呼び出すと...」テキストが消えているか
   
2. **レイアウト確認**:
   - ウインドウサイズ（360×300）が保たれているか
   - マイクボタン、ステータス行の位置がズレていないか
   - 上下のパディング（spacing 18）が正常か
   - VStack 内の spacing（spacing 10）が正常か（modelStatusRow 間の間隔）

3. **機能確認**:
   - マイクボタンのクリック動作（録音開始・停止）が正常か
   - ショートカットキー（triggerRecording 設定値）での録音制御が正常か
   - 右 Option キー単体での動作が正常か
   - SettingsView への遷移が正常か

4. **他との組合わせテスト**:
   - Whisper モデル読込中（ProgressView 表示）の UI
   - Formatter ステータス異常時（赤色ステータス）の表示
   - ネットワーク未接続時（Bonsai フォールバック）の動作

---

## まとめ

| 項目 | 結果 |
|------|------|
| 削除対象ファイル | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/App/TypeToTalkApp.swift` L90–L93 |
| 同一文言の他箇所 | なし（1 箇所のみ） |
| レイアウト崩れリスク | **非常に低い**（VStack の spacing 自動適用、要素削除のみ） |
| 影響対象ファイル数 | 1 ファイル（削除対象のみ） |
| ビジネスロジックへの影響 | なし（View のみの変更） |
| テスト必要性 | ビルド成功 + 実機目視確認（UI View なのでユニットテスト不要） |
| 実装の安全性 | **高い**（修飾子も含めて完全削除で、構文破損なし） |

