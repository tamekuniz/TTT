# Step 4 進捗：TypeToTalk AppIcon 作成

**プランナー**: さくらんぼ小人ちゃん
**作成日時**: 2026年4月26日

---

## Step 4: 計画策定（プランナー）

- [x] investigation.md 通読（524行）
- [x] todo.md 作成（実装タスク 4 項目に分割）
- [x] progress.md 作成（このファイル）

**完了時刻**: 2026-04-26 Step 4 完了

---

## Step 5: 実装（実装小人ちゃん：あけび秋田弁）

### Task 1: アイコン描画 Swift スクリプト作成
- [x] `tools/generate-app-icon.swift` 新規作成（AppKit + CoreGraphics、shebang 付）
- [x] `swift tools/generate-app-icon.swift` 実行成功
- [x] `tools/AppIcon-1024.png` が 1024×1024 RGBA で生成（出力先は入力指示準拠で `tools/AppIcon-1024.png`、todo.md 案の `tools/build/` ではない）
- [ ] Preview.app での目視確認はシア / Step 7 deploy 担当に委ねる

### Task 2: AppIcon ビルドシェルスクリプト作成
- [x] `tools/build-app-iconset.sh` 新規作成（chmod +x）
- [x] sips リサイズ 10 ファイル成功（16/32/128/256/512 各 @1x/@2x）
- [x] `Sources/TypeToTalk/Resources/Assets.xcassets/` 構造完成
- [x] Contents.json（ルート + appiconset）生成

### Task 3: project.yml 更新
- [x] `xcodegen generate` 成功
- [x] pbxproj に Assets.xcassets が登録されたことを確認（PBXResourcesBuildPhase + folder.assetcatalog）
- [x] `resources:` セクションは **使わなかった**（後述）
- [x] `excludes` への追加も **不要だった**（後述）

### Task 4: ビルド & 検証
- [ ] ビルドは Step 7 担当（指示通りスキップ）

---

## ブロッカー / メモ

### project.yml の resources セクションは不要だった

todo.md 案では `excludes:` に `Resources/Assets.xcassets` を追加し、`resources:` セクションを新設する方針だったが、xcodegen 2.45.4 で実際に試した結果、その構成だと **Assets.xcassets が pbxproj に一切登録されない**（PBXFileReference にも PBXBuildFile にも入らない）。`resources:` キーは target 直下では無視される（xcodegen の正式 spec ではない可能性が高い）。

最終的に project.yml は **元の構造のまま**（sources で `Sources/TypeToTalk` を再帰スキャン、excludes は `Resources/Info.plist` のみ）に戻し、Assets.xcassets は sources 配下に置くことで xcodegen が自動で:
- `folder.assetcatalog` 型の PBXFileReference を作成
- PBXResourcesBuildPhase を新規生成
- そこに Assets.xcassets を登録

までやってくれた。pbxproj の関連箇所:
```
D7E45FC617F878E8A8A19FAC /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = D0B148AF8F64D41C900E8538 /* Assets.xcassets */; };
D0B148AF8F64D41C900E8538 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
FF0418708DD7280FDAA8E695 /* Resources */ = { isa = PBXResourcesBuildPhase; ... files = ( D7E45FC617F878E8A8A19FAC /* Assets.xcassets in Resources */ ); };
```

ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon は Debug/Release 双方に既存設定として残っているため、ビルド時に Xcode が自動でアイコンをコンパイルする。

### 入力指示と todo.md の差分（入力指示優先で実装）
- T 配置オフセット: 入力指示は `(-180, +180)` / `(0, 0)` / `(+180, -180)`、todo.md 案は `±200pt 程度`。**入力指示の値**を採用。
- 出力先 PNG: 入力指示は `tools/AppIcon-1024.png`、todo.md 案は `tools/build/icon_1024x1024.png`。**入力指示**を採用。
- T のアルファ falloff: 入力指示は 0.7 / 0.85 / 1.0。todo.md は明記なしのため入力指示を採用。
- 描画順: 後ろ（左下、α=0.7）→ 中央 → 手前（右上、α=1.0）の順で描画。

### CoreGraphics 座標の整理（コード内コメントにも記載）
入力指示は「左下 (-180, +180)」「右上 (+180, -180)」と書かれているが、これは「画面上の見た目」基準（y は下向き正）。CoreGraphics は y 上向き正なので、`drawT()` 内で `center.y - offset.y` として座標を反転している。結果として:
- offset (-180, +180) → 視覚的に左下 → 最背面（α=0.7）
- offset (0, 0)       → 視覚的に中央 → 中間 （α=0.85）
- offset (+180, -180) → 視覚的に右上 → 最前面（α=1.0）

### 生成物サイズ
- 1024×1024 マスター PNG: 約 86 KB（500 KB の Apple 推奨内）
- 最大個別ファイル `icon_512x512@2x.png`: 約 63 KB（同上）
- すべて 32-bit RGBA、sRGB、PNG、squircle 外側は透過

---

## Step 6: レビュー（レビュワー小人ちゃん）

- [ ] todo.md と diff 整合性
- [ ] スタッフエンジニア水準の品質か
- [ ] 不要な変更なし、最小限か
- [ ] アイコン仕様（オレンジ + 白 T 3 つ）が要件通りか

---

## Step 7: deploy / 動作確認

- [ ] Debug build → 起動 → Finder/Dock/Spotlight で表示確認
- [ ] Release build も同様に確認

---

## Step 8: 完了報告

- [ ] git commit（フォKコミットメッセージ規約）
- [ ] tasks/lessons.md 更新（学びがあれば）
