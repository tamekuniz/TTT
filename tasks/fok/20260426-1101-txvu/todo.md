# Step 4 実装計画：TypeToTalk AppIcon 作成

**作成日時**: 2026年4月26日（プランナー小人ちゃん：さくらんぼ）
**サイクル想定**: 1サイクル（アイコン描画 + asset 配置 + ビルド設定 + 検証）
**根拠**: investigation.md の「まとめ」セクション §504-510（実装タスク7項目）

---

## 0. 前提（investigation.md より）

- Assets.xcassets は **存在しない**（要新規作成）→ §1.1
- `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` は **既に project.pbxproj に設定済み** → §1.4
- Info.plist への `CFBundleIconFile` / `CFBundleIconName` 記載は **不要** → §1.3
- project.yml に `resources:` セクションが無いため、`Assets.xcassets` を明示する必要あり（不確かだが安全側） → §3.2
- macOS Sonoma 以降は OS が squircle マスク自動適用 → §5.1.1
- sips は完全対応、Lanczos リサイズ → §6.3

---

## 1. 実装タスク

### Task 1: アイコン描画 Swift スクリプト作成

**ファイル**: `tools/generate-app-icon.swift`（新規）

**仕様**:
- 出力: `tools/build/icon_1024x1024.png`（1024×1024 PNG, RGBA）
- 地色: macOS 風オレンジ `#DE822F`（TimeCamera- の `Color.appOrange` と統一。`decision_timecamera_autoshutter_icon_color_unification` 連想で採用）
- 背景形状: **塗りつぶし squircle**（角丸 220px ≒ Apple 推奨 superellipse 近似）
  - 注: macOS Sonoma 以降は OS が自動マスク適用するが、OS 側マスクと自前角丸が二重マスクされても見た目に問題なし。1024 単独で見ても squircle に見える方が確認しやすいので自前で描く
- 白い T を 3 つ斜め配置:
  - サイズ: 各 T はバウンディング 450×450pt 程度
  - 配置: 左下 → 中央 → 右上の階段状（中心からの相対オフセット ±200pt 程度）
  - 回転: 各 -15 度傾き
  - 色: 白 `#FFFFFF`
  - フォント: `Helvetica-Bold` または `SFPro-Bold`、サイズ 540pt（1024 の約 53%）
  - 重なり順: 後ろの T から順に描画（左下が最背面、右上が最前面）
- フォーマット: 32-bit RGBA PNG、sRGB
- 実行方法: `swift tools/generate-app-icon.swift`（macOS 標準で実行可能）

**実装方針**:
- `AppKit` の `NSImage` + `CGContext` 使用
- `CGContext` を 1024×1024 RGBA で作成
- 背景 squircle を `CGPath` の rounded rect で描画
- T 文字列を `NSAttributedString` でセンタリング描画 × 3（各 transform 適用）
- `CGImage` → `NSBitmapImageRep` → `representation(using: .png)` で PNG 出力

**Why Swift スクリプト**: ImageMagick / Figma 不要。macOS 標準ツールチェーンで完結し再現性高い。

---

### Task 2: AppIcon ビルドシェルスクリプト作成

**ファイル**: `tools/build-app-iconset.sh`（新規、`chmod +x`）

**仕様**:
1. `tools/build/` を作成（既存なら clean）
2. `swift tools/generate-app-icon.swift` を実行 → 1024×1024 PNG 生成
3. sips で各サイズへリサイズ（aspect 保持の正方形リサンプル）:
   - 16×16, 32×32, 64×64, 128×128, 256×256, 512×512（@1x）
   - 32×32, 64×64, 128×128, 256×256, 512×512, 1024×1024（@2x ファイル）
4. `Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/` を作成
5. 各 PNG を `icon_<size>x<size>.png` / `icon_<size>x<size>@2x.png` でコピー
6. Contents.json を生成（macOS idiom）
7. ルート `Contents.json`（Assets.xcassets 直下）も生成

**生成するファイル**（Sources/TypeToTalk/Resources/Assets.xcassets/ 配下）:
```
Assets.xcassets/
├── Contents.json                    # ルート（author/version のみ）
└── AppIcon.appiconset/
    ├── Contents.json                # macOS idiom 全12 entry
    ├── icon_16x16.png
    ├── icon_16x16@2x.png            # = 32×32 PNG
    ├── icon_32x32.png
    ├── icon_32x32@2x.png            # = 64×64 PNG
    ├── icon_128x128.png
    ├── icon_128x128@2x.png          # = 256×256 PNG
    ├── icon_256x256.png
    ├── icon_256x256@2x.png          # = 512×512 PNG
    ├── icon_512x512.png
    └── icon_512x512@2x.png          # = 1024×1024 PNG
```

**注**: Apple macOS 標準セット（Xcode 15）= 16/32/128/256/512 の @1x / @2x で計10ファイル。64×64 は推奨だが必須ではないため省略（investigation.md §6.1 の「最小セット」に準拠）。ファイル数を絞ってビルド時間短縮。

**Contents.json テンプレート**（AppIcon.appiconset/Contents.json）:
```json
{
  "images" : [
    { "filename" : "icon_16x16.png",       "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",    "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",       "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",    "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",     "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",     "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",     "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

**ルート Contents.json**:
```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

---

### Task 3: project.yml に resources セクション追加

**ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/project.yml`

**変更内容**（investigation.md §3.2 の「変更案」に準拠）:

before:
```yaml
targets:
  TypeToTalk:
    type: application
    platform: macOS
    sources:
      - path: Sources/TypeToTalk
        excludes:
          - Resources/Info.plist
```

after:
```yaml
targets:
  TypeToTalk:
    type: application
    platform: macOS
    sources:
      - path: Sources/TypeToTalk
        excludes:
          - Resources/Info.plist
          - Resources/Assets.xcassets
    resources:
      - path: Sources/TypeToTalk/Resources/Assets.xcassets
```

**Why excludes に追加**: `sources` で `Sources/TypeToTalk` 配下を再帰スキャンしているため、`Assets.xcassets` を sources でも拾われると重複登録される。`excludes` で抑止し、`resources` 側で正式登録する。

**不確かポイント**: xcodegen 2.45.0 が `.xcassets` を sources から自動的にリソースフェーズへ振り分けるかは未検証。`excludes` + `resources` 明示で安全側に倒す。

---

### Task 4: ビルド実行＋アイコン適用検証

**手順**:
1. `tools/build-app-iconset.sh` 実行 → Assets.xcassets 完成
2. `xcodegen generate` 実行 → project.pbxproj 再生成（Assets.xcassets が反映されることを確認）
3. `xcodebuild -scheme TypeToTalk -configuration Debug build` 実行
4. ビルド成功確認
5. 生成された `.app` を Finder で目視確認:
   ```
   ls -la ~/Library/Developer/Xcode/DerivedData/TypeToTalk-*/Build/Products/Debug/TypeToTalk.app/Contents/Resources/
   ```
   → `Assets.car` が存在することを確認
6. `open ~/Library/Developer/Xcode/DerivedData/TypeToTalk-*/Build/Products/Debug/TypeToTalk.app/..` で Finder 表示
7. アイコンがオレンジ + 白 T 3 つになっていることを目視確認

**合格基準**:
- ビルドエラー / 警告ゼロ
- Finder 上で TypeToTalk.app のアイコンがオレンジ squircle + 白 T 3 つ階段状に見える
- 1024×1024 元画像が `tools/build/icon_1024x1024.png` に生成されていてプレビュー可能

**TTT は menu bar app の可能性**（investigation.md §7.3 注釈）:
- Dock 表示がされない場合は Finder + Spotlight で代替確認

---

## 2. ファイル作成・変更サマリ

| 種別 | パス | 備考 |
|------|------|------|
| 新規 | `tools/generate-app-icon.swift` | Swift CoreGraphics 描画 |
| 新規 | `tools/build-app-iconset.sh` | ビルドオーケストレータ（chmod +x） |
| 新規 | `tools/build/.gitignore` | `*.png` を ignore（生成物） |
| 新規 | `Sources/TypeToTalk/Resources/Assets.xcassets/Contents.json` | ルート |
| 新規 | `Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | macOS 10 entry |
| 新規 | `Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png` | 10 ファイル |
| 変更 | `project.yml` | excludes に Assets.xcassets 追加 + resources セクション追加 |
| 自動 | `TypeToTalk.xcodeproj/project.pbxproj` | xcodegen で再生成 |

---

## 3. ロールバック手順（失敗時）

1. `Sources/TypeToTalk/Resources/Assets.xcassets/` を削除
2. `project.yml` を git checkout で戻す
3. `xcodegen generate` で pbxproj 復元
4. `tools/` 配下の新規ファイルを削除（Swift スクリプト・shell スクリプト）

---

## 4. 不確か・リスク

- **xcodegen 2.45.0 の自動検出動作**（investigation.md §3.2）→ 明示的 `resources:` 指定で安全側
- **macOS Sonoma squircle 二重マスク**（§5.1.1）→ 自前角丸でも実害なし、見た目で判断
- **16×16 縮小時の T 視認性**（§5.2）→ Helvetica-Bold + 太線で対策、ダメなら 16/32 だけ手動描画も検討
- **TTT が menu bar app の場合 Dock 非表示**（§7.3）→ Finder/Spotlight で代替確認

---

## 5. Step 5（実装小人ちゃん）への申し送り

- Task 1 → Task 2 → Task 3 → Task 4 の順で実行
- 各 Task 完了時に progress.md へ追記
- ビルドエラー出たら即停止、原因を progress.md に書いて次フェーズへバトンタッチ
- 「斜め重ね」は左下→中央→右上の階段状（中心からオフセット）で実装。3つを完全に重ねるのではなく、ずらして配置することで「3」の存在を視認しやすくする
