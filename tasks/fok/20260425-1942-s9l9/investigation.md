# Step 3 調査報告書: Settings 画面にビルドナンバー YYYYMMDDA 形式を表示する実装検討

**タスク**: macOS SwiftUI アプリ TypeToTalk の Settings 画面のバージョン表示の下に、ビルドナンバー `YYYYMMDDA` 形式（A は当日の連番アルファベット）を表示したい。手動更新方式で、フォK Step 8 のバージョン更新フローに組み込む。  
**候補案**:
- A) Info.plist の CFBundleVersion を YYYYMMDDA に設定し、Bundle.main からアプリ内で読み込み
- B) Swift コード内に定数を持たせて表示
- C) 両方

**調査実施日**: 2026-04-25  
**調査者**: ミカン Step 3 調査小人ちゃん (very thorough) - 関西弁

---

## 1. 関連ファイル一覧（パス + 役割）

| ファイル | パス | 役割 |
|---------|------|------|
| **SettingsView.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift` | Settings 画面 UI。L414-419 で `appVersionText` 計算プロパティを定義。Bundle.main から CFBundleShortVersionString と CFBundleVersion を読み込み、「Version x.x.x (build)」形式で表示 |
| **Info.plist** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Resources/Info.plist` | アプリメタデータ。L5-8 で CFBundleShortVersionString と CFBundleVersion をビルド時変数として定義（$(MARKETING_VERSION), $(CURRENT_PROJECT_VERSION)） |
| **project.yml** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/project.yml` | プロジェクト設定。L13-14 で CURRENT_PROJECT_VERSION: 1、MARKETING_VERSION: 0.1.0 を定義 |
| **SettingsManager.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Managers/SettingsManager.swift` | アプリ設定管理。Settings 画面で ObservedObject として利用されるが、バージョン定数は保持していない |
| **Package.swift** | `/Users/tamekuniz/GitHub/tamekuniz/TTT/Package.swift` | パッケージ定義。Swift マニフェスト |

---

## 2. 既存実装パターン

### 2.1 Settings 画面でのバージョン表示

**SettingsView.swift L414-419**:
```swift
private var appVersionText: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.1.0"
    let buildNumber = info["CFBundleVersion"] as? String ?? "-"
    return "Version \(shortVersion) (\(buildNumber))"
}
```

- 現在の表示形式: 「Version 0.1.0 (1)」
- Bundle.main.infoDictionary から読み込み
- CFBundleShortVersionString: マーケティング版番号（ユーザーに見せる）
- CFBundleVersion: ビルド番号（内部管理）
- デフォルト値フォールバック: shortVersion は "0.1.0"、buildNumber は "-"

**SettingsView.swift L29-35** (バージョン表示部分の UI):
```swift
HStack {
    Spacer()
    Text(appVersionText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
}
```

- 右寄せ、caption フォント、secondary 色（グレー）
- テキスト選択可能（クリップボードコピー対応）

### 2.2 Bundle.main.infoDictionary の CFBundleVersion/CFBundleShortVersionString 取得

**現在の実装パターン**: Bundle.main で取得。他に buildVersion 定数を持つコード例なし。

```swift
let info = Bundle.main.infoDictionary ?? [:]
let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.1.0"
let buildNumber = info["CFBundleVersion"] as? String ?? "-"
```

**grep 結果**（ビルド番号関連の定数が Swift コード内にあるか）:
- buildNumber、buildVersion、BUILD_NUMBER、BUILD_VERSION は SettingsView.swift L417 と L418 の変数以外に見当たらない
- つまり、既存の Swift 定数パターンはない

### 2.3 project.yml の CURRENT_PROJECT_VERSION / MARKETING_VERSION 設定

**project.yml L6-17**:
```yaml
settings:
  base:
    PRODUCT_BUNDLE_IDENTIFIER: com.tamekuniz.TypeToTalk
    PRODUCT_NAME: TypeToTalk
    INFOPLIST_KEY_CFBundleDisplayName: TypeToTalk
    INFOPLIST_KEY_CFBundleName: TypeToTalk
    SWIFT_VERSION: "6.0"
    CURRENT_PROJECT_VERSION: 1
    MARKETING_VERSION: 0.1.0
    GENERATE_INFOPLIST_FILE: NO
    INFOPLIST_FILE: Sources/TypeToTalk/Resources/Info.plist
```

- CURRENT_PROJECT_VERSION: 1（ビルド番号、整数）
- MARKETING_VERSION: 0.1.0（バージョン、セマンティック）
- GENERATE_INFOPLIST_FILE: NO（Info.plist は手動ファイル）
- INFOPLIST_FILE: Sources/TypeToTalk/Resources/Info.plist

### 2.4 Info.plist の構造

**Info.plist L5-8**:
```xml
<key>CFBundleShortVersionString</key>
<string>$(MARKETING_VERSION)</string>
<key>CFBundleVersion</key>
<string>$(CURRENT_PROJECT_VERSION)</string>
```

- CFBundleShortVersionString: ビルド時に $(MARKETING_VERSION) 変数で置換
- CFBundleVersion: ビルド時に $(CURRENT_PROJECT_VERSION) 変数で置換
- 変数化されているため、ビルド時に project.yml の値が自動的に埋め込まれる

---

## 3. 影響範囲（呼び出し側 / 依存）

### 3.1 appVersionText の呼び出し箇所

**SettingsView.swift L31**: 
```swift
Text(appVersionText)
```

- SettingsView 内でのみ使用
- 計算プロパティのため、毎回 Bundle.main から読み込み

### 3.2 CFBundleVersion 変更による影響

**変更対象**:
- project.yml L13 の CURRENT_PROJECT_VERSION を整数 (1, 2, ...) から 文字列 (20260425A) に変更
- Info.plist は自動で置換されるため、変更なし

**影響を受けるシステム**:
1. **Xcode ビルド**: CURRENT_PROJECT_VERSION は Xcode build settings で使用。整数から文字列への変更は、Xcode の bundle version handling に影響する可能性
2. **macOS/App Store ビルド検証**: Bundle version の形式は App Store Connect でバリデーション対象。詳細は「制約条件」参照
3. **Settings 画面**: Bundle.main から読み込む際に、整数ではなく文字列として扱われる（既存コードで対応）
4. **その他のメタデータ**: アプリケーション署名、証明書周りへの影響は不明（要確認）

### 3.3 ビルド設定変更の波及

**project.yml 変更時**:
- `xcodegen` で Xcode.xcodeproj を再生成
- Info.plist は自動で $(CURRENT_PROJECT_VERSION) が置換される
- ビルド番号の手動更新を Step 8 で行う際、project.yml の CURRENT_PROJECT_VERSION を YYYYMMDDA に更新

---

## 4. 過去の類似実装（git log から）

**git log --oneline -50 結果**:
```
d08f241 [フォK] feat: 権限再チェックボタンをアプリ再起動ボタンに変更
9c10aed [フォK] feat: ショートカットを triggerRecording 1つに統合
848ef06 [フォK] fix: Whisperステータスがメインウインドウに伝播しない不整合を修正
...（省略）
ca4c764 Initial commit of TTT (Talk to Type) macOS app
```

**バージョン更新関連のコミット**: 見当たらない。CURRENT_PROJECT_VERSION は常に 1 のまま。

**参考**: TimeCamera- で「project.yml の CURRENT_PROJECT_VERSION と Swift 定数の両方を更新している」という実装があるとの話だが、このリポには該当コード見当たらず。

---

## 5. 想定される副作用 / リスク

### 5.1 CFBundleVersion を YYYYMMDDA 形式にすることのリスク

#### A) Xcode ビルド設定の仕様

**CURRENT_PROJECT_VERSION**:
- Xcode 標準では、integer 値を想定（例: 1, 2, 3, ...）
- **ただし** project.yml で文字列を指定可能（変数置換は `$(...)` 形式で行われるため、文字列も対応）
- stringification の仕様: project.yml が文字列を指定すれば、Info.plist の $(CURRENT_PROJECT_VERSION) は文字列として置換される

**リスク度**: 低～中（文字列仕様は xcodegen と Xcode で対応）

#### B) macOS Gatekeeper / コード署名

- CFBundleVersion は bundle metadata（署名対象外）
- コード署名に直接影響しない
- ただし、系統的変更（整数→文字列）が signing infrastructure で変動を引き起こすことはないとは言い切れない

**リスク度**: 低（署名対象外）

#### C) Mac App Store ビルド検証

**App Store Connect の仕様**:
- CFBundleShortVersionString（MARKETING_VERSION）: セマンティック形式 (1.0.0, 0.1.0 等)
- CFBundleVersion（CURRENT_PROJECT_VERSION）: **整数か、整数の小数点区切り形式を推奨**
  - 例: 1, 1.0, 1.2.3
  - YYYYMMDDA 形式（文字列）は **非推奨～規約違反の可能性**

**App Store 審査時**:
- Transporter で自動バリデーション時に警告または拒否される可能性あり
- TTT が Mac App Store で配布予定なら、検討必須

**リスク度**: 中～高（App Store 配布予定あるなら）

#### D) ユーザー観点での影響

- About ウインドウ（アプリメニュー「TypeToTalk について」等）でバージョン表示される場合、形式が変わる
- TTT に About ウインドウがあるかは未確認（Settings View では表示されている）

**リスク度**: 低（UI 表示のみ）

### 5.2 Swift 定数パターン（案 B/C）の副作用

**案 B): Swift コード内に `let BUILD_NUMBER = "20260425A"` など定数を持たせる場合**:
- プロジェクト全体で定数を管理
- Info.plist と の同期ズレのリスク（片方だけ更新されるミス）
- ビルド自動化時に 2 箇所を更新する必要

**リスク度**: 中（同期ズレ）

### 5.3 Step 8 フロー（フォK の自動更新）への組み込み

- project.yml の CURRENT_PROJECT_VERSION を YYYYMMDDA に更新
- 必要に応じて Swift 定数も更新（案 C）
- .fok-target に VERSION_FILE_1_PATH を記載して、自動化フロー側で処理
- 手動更新のミスリスク

**リスク度**: 低～中（フロー設計次第）

---

## 6. 制約条件（macOS の Bundle Version 仕様）

### 6.1 CFBundleShortVersionString vs CFBundleVersion

| 項目 | CFBundleShortVersionString | CFBundleVersion |
|------|--------------------------|-----------------|
| **用途** | マーケティング版番号（ユーザーに見せる） | ビルド番号（内部追跡） |
| **形式** | セマンティック (X.Y.Z) 推奨 | 整数、または 整数.小数点形式 |
| **例** | 0.1.0, 1.0, 2.3.4 | 1, 100, 1.0.0 |
| **App Store ルール** | 厳密に セマンティック版を要求 | 整数形式を強く推奨 |
| **YYYYMMDDA 形式適性** | 不可（セマンティック形式ではない） | **リスク（整数/小数点形式でない）** |

### 6.2 Bundle Version の文字列 vs 数値

**Xcode プロジェクト設定**:
- project.yml では CURRENT_PROJECT_VERSION を文字列で指定可能
- Info.plist の $(CURRENT_PROJECT_VERSION) 置換時は文字列化される
- Swift コードで Bundle.main から読み込む際は、String として扱われる

**現在のコード** (L417):
```swift
let buildNumber = info["CFBundleVersion"] as? String ?? "-"
```
- String キャストなので、数値でも文字列でも対応可能

### 6.3 macOS Deployment Target との互換性

**current deployment target**: macOS 14.0 (project.yml L5)

- CFBundleVersion, CFBundleShortVersionString の仕様は macOS 14.0 以上でも変わらない
- YYYYMMDDA 形式への変更は OS 互換性に影響しない

---

## 7. テスト戦略（実機/シミュレータ確認ポイント）

### 7.1 バージョン表示の見た目確認

#### テスト項目

1. **Settings 画面でのバージョン表示**
   - 表示形式: 「Version 0.1.0 (20260425A)」
   - フォント: caption（小さい）
   - 色: secondary（グレー）
   - テキスト選択可能か確認

2. **ビルド時の YYYYMMDDA 置換**
   - project.yml で CURRENT_PROJECT_VERSION: 20260425A に設定後、ビルド
   - Info.plist が正しく置換されているか確認
   - Bundle.main.infoDictionary でアプリ起動時に正しく読み込まれるか確認

3. **フォールバック動作**
   - Info.plist 読み込み失敗時、buildNumber が "-" で表示されるか確認

#### 確認環境

- **実機**: Mac mini / MacBook Pro (Apple Silicon or Intel)
- **シミュレータ**: Xcode Simulator (macOS 14.0 以上)

### 7.2 ビルド検証ポイント

1. **xcodegen での Xcode.xcodeproj 再生成**
   ```bash
   xcodegen generate
   ```
   - project.yml の CURRENT_PROJECT_VERSION: 20260425A が Xcode build settings に正しく反映されるか

2. **Info.plist の $(CURRENT_PROJECT_VERSION) 置換**
   ```bash
   # ビルド後に Info.plist を確認
   plutil -p dist/TypeToTalk.app/Contents/Info.plist | grep CFBundleVersion
   ```
   - 置換後の値が 20260425A で表示されるか

3. **Bundle.main での読み込み**
   - SettingsView の appVersionText が正しく 「Version 0.1.0 (20260425A)」を返すか

### 7.3 副作用確認

1. **アプリ署名**
   - ビルド後、codesign で署名が valid か確認
   ```bash
   codesign -vv dist/TypeToTalk.app
   ```

2. **アプリ起動**
   - Settings ウインドウを開いて、バージョン表示が正しいか目視確認
   - エラー出力（stderr）がないか確認

---

## 8. 不確か / シアへの確認事項

### 8.1 .fok-target ファイルの形式

このリポの過去のタスク（20260425-1932-i17i など）に .fok-target の記載がない。フォK の仕様では以下を推測：
- .fok-target は Step 8 で自動ビルド番号更新を行うための設定ファイル
- 記載内容案: VERSION_FILE_1_PATH、VERSION_FILE_2_PATH 等のパスリスト
- **確定が必要**: 正確な .fok-target の形式と、記載すべきファイルパス（project.yml or Info.plist or Swift ファイル）

### 8.2 App Store 配布予定の有無

CFBundleVersion を YYYYMMDDA 形式にすることが App Store Connect のバリデーションで警告/拒否される可能性あり。

- **TTT が Mac App Store で配布予定か？** → 案 A を採用するなら要確認
- 予定なし、あるいは Setapp などの別チャネルのみなら、リスク軽減

### 8.3 Swift 定数パターン（案 C）の採否

TimeCamera- で「project.yml の CURRENT_PROJECT_VERSION と Swift 定数の両方を更新している」とのことだが、TTT でも同様にするか？

- 案 A（Info.plist + Bundle.main のみ）→ シンプル、単一の真実
- 案 C（+ Swift 定数）→ 複雑さ増加、同期ズレリスク

---

## 9. 小人ちゃんからの提案

### 9.1 CFBundleVersion YYYYMMDDA 形式の妥当性評価

**評価**:
- TTT が内部配布（Setapp など非 App Store）なら **妥当**
- Mac App Store 配布予定あるなら、**非推奨～リスク**

**代替案**: 
- CFBundleShortVersionString を "0.1.0-20260425A" に変更（日付を付記）
- CFBundleVersion は整数 (1, 2, 3, ...) で保持
- ただし、この方式だと "Version 0.1.0-20260425A (1)" となり、「ビルド番号」の意味が薄れる

### 9.2 Settings 画面のレイアウト構造案

**現在**: 「Version 0.1.0 (1)」1 行表示

**提案: 縦並べ案**
```
Version: 0.1.0
Build: 20260425A
```

- 実装: appVersionText を 2 行返す、あるいは VStack で構成
- 利点: 各情報が明確に分離、ユーザーが「ビルド番号」と「マーケティング版」を区別しやすい

**提案: 横並べ案（現在形式の拡張）**
```
Version 0.1.0 • Build 20260425A
```
- 実装: 区切り文字を • または | に変更
- 利点: 1 行表示を保持、スペース効率的

### 9.3 .fok-target VERSION_FILE_1_PATH の最終確定

**推奨案**:
```
VERSION_FILE_1_PATH: project.yml
VERSION_FILE_2_PATH: (不要)
```

理由:
- project.yml の CURRENT_PROJECT_VERSION を YYYYMMDDA に手動更新
- Info.plist は ビルド時の $(CURRENT_PROJECT_VERSION) 置換で自動化
- Swift 定数は使わない（同期ズレリスク）
- xcodegen で Xcode.xcodeproj 再生成は Step 8 フロー側で自動化

---

## 10. 結論・推奨パス

### 10.1 候補案の評価

| 案 | 利点 | リスク | 推奨度 |
|----|------|--------|--------|
| **A) Info.plist + Bundle.main のみ** | シンプル、同期ズレなし | App Store リスク（要確認） | ★★★（App Store 配布なしなら） |
| **B) Swift 定数のみ** | 自動化しやすい? | Bundle.main との二重管理、Info.plist との同期必須 | ★（非推奨） |
| **C) A + B（両方）** | 冗長性確保? | 同期ズレリスク増加 | ★（複雑） |

### 10.2 採用推奨: 案 A + 要件確認

1. **App Store 配布予定の確認を優先**
   - 予定あり → リスク検討が必須。整数 CFBundleVersion 維持を検討
   - 予定なし → 案 A で進行可能

2. **Settings 画面レイアウト** → 縦並べ案（Version / Build を分離） or 現在形式維持（要決定）

3. **.fok-target VERSION_FILE_1_PATH** → `project.yml` に確定

4. **Step 8 フロー自動化** → project.yml の CURRENT_PROJECT_VERSION を YYYYMMDDA に手動更新、xcodegen 再実行

