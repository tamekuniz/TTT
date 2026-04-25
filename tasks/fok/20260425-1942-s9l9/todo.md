# Step 4 計画: Settings 画面にビルドナンバー YYYYMMDDA 形式を表示

**作成日**: 2026-04-25
**プランナー**: メロン Step 4 プランナー小人ちゃん（山形弁）
**採用案**: 案 A（Info.plist + Bundle.main、project.yml の `CURRENT_PROJECT_VERSION` を文字列化）
**スコープ**: TTT（リリース前ローカルアプリ）の Settings 画面で `バージョン x.x.x` の下に `ビルド YYYYMMDDA` を 2行表示する。フォK Step 8 の自動更新フローに乗せる。
**スコープ外**: App Store 配布リスク評価（無視）、Swift 定数の二重管理、About ウインドウ対応

---

## 全体方針

### 採用案 A の中身

1. `project.yml` の `CURRENT_PROJECT_VERSION: 1` を **文字列 `"20260425A"` に変更**（YYYYMMDDA 形式）
2. `Info.plist` の `CFBundleVersion` は既存の `$(CURRENT_PROJECT_VERSION)` 置換のままで自動的に YYYYMMDDA が埋まる
3. `SettingsView.swift` の `appVersionText` を **2行表示** に変更（`バージョン x.x.x` / `ビルド YYYYMMDDA`）
4. `.fok-target` を新設して Step 8 の自動更新対象に登録
5. xcodegen 再生成を Step 6 実装小人ちゃんに必須実施させる

### 文言統一方針

既存ラベル文言は `Settings` 画面で **日本語ラベル**（例: `表示`, `音声入力`, `言語` 等）が使われているため、**日本語に統一**:
- 1行目: `バージョン 0.1.0`
- 2行目: `ビルド 20260425A`

（投資的に英語混在を避けるため、既存の `Version x.x.x (build)` 表記は捨てる）

---

## タスク一覧

### Task 1: `.fok-target` 新設 + `project.yml` の `CURRENT_PROJECT_VERSION` を文字列化 + xcodegen 再生成

**目的**: フォK Step 8 のバージョン更新フローに乗せる仕組みを作る + ビルド時に YYYYMMDDA がアプリに埋め込まれる状態にする

**変更ファイル**:

1. **新規作成**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/.fok-target`
   ```
   VERSION_FILE_1_PATH=project.yml
   VERSION_FILE_1_KEY=CURRENT_PROJECT_VERSION
   VERSION_FORMAT="YYYYMMDD + 連番アルファベット（例: 20260425A）"
   VERSION_EXAMPLE="20260425A"
   DEPLOY_COMMAND="open ~/Library/Developer/Xcode/DerivedData/TypeToTalk-bflowijsxyneuzgvdqdbgbmersdd/Build/Products/Debug/TypeToTalk.app"
   DEPLOY_TARGET="ローカルMac"
   VERIFY_TYPE="Settings 画面で Version/Build 表示を目視確認"
   ```

2. **編集**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/project.yml`
   - L13 の `CURRENT_PROJECT_VERSION: 1` を `CURRENT_PROJECT_VERSION: "20260425A"` に変更（**ダブルクォート必須** — YAML が文字列として認識するため）

3. **コマンド実行**: `xcodegen generate`
   - project.yml 変更後、Xcode プロジェクトを再生成して build settings に反映する
   - 実行ディレクトリ: `/Users/tamekuniz/GitHub/tamekuniz/TTT/`

**検証**（Step 7 で実施）:
- `xcodegen generate` がエラーなく完走する
- `xcodebuild` でビルドが通る
- ビルド成果物の Info.plist で `CFBundleVersion` が `20260425A` になっている（`plutil -p .../TypeToTalk.app/Contents/Info.plist | grep CFBundleVersion`）

**リスク**:
- xcodegen が文字列 `CURRENT_PROJECT_VERSION` を受け付けない可能性（不確か） → 受け付けなかった場合は Step 6 実装小人ちゃんが Step 5 へ差し戻し

---

### Task 2: `SettingsView.swift` の `appVersionText` を 2行表示に変更

**目的**: Settings 画面で「バージョン x.x.x」「ビルド YYYYMMDDA」を 2行表示する

**変更ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Views/SettingsView.swift`

**変更箇所 1**（L414-419 の `appVersionText` 計算プロパティ）:

現状:
```swift
private var appVersionText: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.1.0"
    let buildNumber = info["CFBundleVersion"] as? String ?? "-"
    return "Version \(shortVersion) (\(buildNumber))"
}
```

変更後（2 つの計算プロパティに分割）:
```swift
private var appVersionLine: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let shortVersion = info["CFBundleShortVersionString"] as? String ?? "0.1.0"
    return "バージョン \(shortVersion)"
}

private var appBuildLine: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let buildNumber = info["CFBundleVersion"] as? String ?? "-"
    return "ビルド \(buildNumber)"
}
```

**変更箇所 2**（L29-35 の HStack ブロック）:

現状:
```swift
HStack {
    Spacer()
    Text(appVersionText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
}
```

変更後（VStack で 2 行表示、右寄せ維持）:
```swift
HStack {
    Spacer()
    VStack(alignment: .trailing, spacing: 2) {
        Text(appVersionLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        Text(appBuildLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}
```

**検証**（Step 7 で実施）:
- ビルド成果物アプリを起動して Settings ウインドウを開く
- バージョン表示部に `バージョン 0.1.0` / `ビルド 20260425A` の 2行が右寄せで表示される
- 2行ともテキスト選択可能（コピーできる）
- フォントは caption、色は secondary（グレー）

**リスク**: なし（純粋な UI 変更）

---

## Step 6 実装小人ちゃんへの注意事項（必読）

1. **タスクは Task 1 → Task 2 の順で実施する**（順不同でもOKだが、ビルドエラーを切り分けやすいため）
2. **project.yml 変更後は必ず `xcodegen generate` を走らせる**（忘れると Xcode プロジェクトに反映されない）
3. **`xcodegen generate` の実行ディレクトリは `/Users/tamekuniz/GitHub/tamekuniz/TTT/`**
4. **`appVersionText` という旧名のプロパティは削除する**（不要な dead code を残さない）
5. **`.fok-target` の `VERSION_FILE_1_PATH` の値は相対パス `project.yml`**（リポルートからの相対）

## Step 7 検証小人ちゃんへの注意事項

1. **ビルド検証**: `xcodebuild` または `xcodegen generate && xcodebuild` でビルド完走を確認
2. **Info.plist 検証**: ビルド成果物の `Contents/Info.plist` で `CFBundleVersion = 20260425A` を確認
3. **UI 目視確認**: アプリを起動して Settings ウインドウのバージョン表示を実機（Mac）で確認
4. **dual deploy は不要**（macOS アプリのため、シミュレータ概念なし — ローカルMac のみ）

---

## 完了条件

- [ ] `.fok-target` が新規作成され、シア指定の 7 項目すべて記載されている
- [ ] `project.yml` の `CURRENT_PROJECT_VERSION` が `"20260425A"`（ダブルクォート付き文字列）になっている
- [ ] `xcodegen generate` がエラーなく完走する
- [ ] `SettingsView.swift` の `appVersionText` が `appVersionLine` / `appBuildLine` の 2つに分割されている
- [ ] Settings 画面で `バージョン 0.1.0` / `ビルド 20260425A` が 2行右寄せで表示される
- [ ] ビルドが通る（`xcodebuild` 成功）
- [ ] ビルド成果物の `Info.plist` で `CFBundleVersion = 20260425A` が確認できる

---

## 不確か事項（シアへ）

1. **xcodegen が文字列形式の `CURRENT_PROJECT_VERSION` を受け付けるか不確か**
   - investigation.md 5.1.A では「project.yml で文字列を指定可能」と推測されているが、実証データは未確認
   - もし xcodegen が integer のみ受け付ける場合、Step 5 へ差し戻して別案検討（例: Info.plist 直書き）
2. **DerivedData のハッシュ部 `bflowijsxyneuzgvdqdbgbmersdd` がマシン依存の可能性**
   - シア指定の `DEPLOY_COMMAND` をそのまま .fok-target に書くが、別Macでは動かない可能性あり
   - 必要なら Step 8 自動化時に `xcodebuild -showBuildSettings` から動的解決する仕組みに切り替え
