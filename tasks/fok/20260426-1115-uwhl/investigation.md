# Step 3 調査: generate-app-icon.swift の alpha 値統一化

## 1. 関連ファイル一覧

### 直接影響を受ける主要ファイル

| ファイルパス | 役割 | 備考 |
|---|---|---|
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/tools/generate-app-icon.swift` | 1024x1024 PNG 生成スクリプト（Swift） | CoreGraphics を使用して描画；alpha 値設定の中心 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/tools/build-app-iconset.sh` | AppIcon セット生成シェルスクリプト | master PNG を sips で 10 種類にリサイズ、Contents.json 生成 |
| `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | AppIcon メタデータ | 10 個の PNG ファイル（@1x/@2x）の登録リスト |

### 派生的な PNG 出力ファイル（10個）

すべて `/Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/` 配下

```
icon_16x16.png       (16x16 pixels)
icon_16x16@2x.png    (32x32 pixels)
icon_32x32.png       (32x32 pixels)
icon_32x32@2x.png    (64x64 pixels)
icon_128x128.png     (128x128 pixels)
icon_128x128@2x.png  (256x256 pixels)
icon_256x256.png     (256x256 pixels)
icon_256x256@2x.png  (512x512 pixels)
icon_512x512.png     (512x512 pixels)
icon_512x512@2x.png  (1024x1024 pixels)
```

---

## 2. 既存実装パターン（行番号付き）

### 2.1 alpha 値の設定箇所

**ファイル**: `tools/generate-app-icon.swift`

**構造体定義** (行 34-37)
```swift
struct TPlacement {
    let offset: CGPoint
    let alpha: CGFloat
}
```

**配置定義** (行 39-43)
```swift
let placements: [TPlacement] = [
    TPlacement(offset: CGPoint(x: -180, y:  180), alpha: 0.70),  // back (lower-left visually -> drawn first)
    TPlacement(offset: CGPoint(x:    0, y:    0), alpha: 0.85),  // middle
    TPlacement(offset: CGPoint(x:  180, y: -180), alpha: 1.00),  // front (upper-right visually -> drawn last)
]
```

### 2.2 drawT 関数のシグネチャ

**関数定義** (行 101)
```swift
func drawT(in ctx: CGContext, canvas: CGFloat, offset: CGPoint, alpha: CGFloat) {
```

**NSColor 設定箇所** (行 108)
```swift
.foregroundColor: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha),
```

この `alpha` パラメータが NSAttributedString.Key.foregroundColor のアルファチャネルに直接指定される。
そのため 0.7/0.85/1.0 の値がテキスト描画時に適用される。

### 2.3 drawT 呼び出し箇所（3回）

**ループ内での呼び出し** (行 150-152)
```swift
// 2. Three Ts, back-to-front.
for placement in placements {
    drawT(in: ctx, canvas: canvasSize, offset: placement.offset, alpha: placement.alpha)
}
```

- ループは `placements` 配列を順序通り処理する
- インデックス 0 → 1 → 2 の順で drawT を呼び出す
- 各回で `placement.alpha` の値（0.70 → 0.85 → 1.00）が渡される
- 描画順序が奥から手前へ進むため、最後（1.00）が最も前面に見える

---

## 3. 影響範囲

### 3.1 スクリプト実行フロー

```
[ユーザー実行] swift tools/generate-app-icon.swift
     ↓
[出力] tools/AppIcon-1024.png (1024x1024 RGBA PNG)
     ↓
[呼び出し] tools/build-app-iconset.sh
     ↓
[処理] sips -Z <size> tools/AppIcon-1024.png --out <target.png> (10回)
     ↓
[出力] icon_16x16.png, icon_16x16@2x.png, ... (10個のリサイズ版 PNG)
     ↓
[メタデータ生成] Contents.json (AppIcon.appiconset)
                 Contents.json (Assets.xcassets)
     ↓
[ビルド時] Xcode が Assets.xcassets を自動走査
     ↓
[成果物] Assets.car (バイナリアセットカタログ)
```

### 3.2 各段階への影響

| 段階 | 変更内容 | 影響の詳細 |
|---|---|---|
| **Swift スクリプト実行** | alpha 値を全て 1.0 に変更 | master PNG (1024x1024) が 3 個の T を完全不透明で描画 |
| **sips による リサイズ** | png 形式での処理 | 1.0 alpha の画像をそのまま 16x16～512x512 にリサイズ（品質損失なし） |
| **10 個の PNG 上書き** | 既存ファイルを置換 | icon_*.png が新しい master から生成される；ファイルサイズは変わる可能性あり |
| **ビルド時 Assets.car 再生成** | Xcode asset compiler 実行 | 不透明度の高い画像により Assets.car 内のリソース値が変更 |
| **アプリケーション実行** | メニューバー・Dock アイコン表示 | 従来は重なった領域が透けていた；変更後は最後に描画された T で完全に塗りつぶされる |

---

## 4. 過去の類似実装

### 4.1 直近のコミット情報

**コミット**: `14397f9`  
**メッセージ**: `[フォK] feat: AppIcon 追加 (オレンジ地・白 T x3 斜め重ね)`  
**作成日時**: Sun Apr 26 11:13:55 2026 +0900  
**作者**: tamekuniz <tamekuniz@gmail.com>

### 4.2 コミット内容の詳細

```
- tools/generate-app-icon.swift: CoreGraphics で 1024x1024 PNG 生成
  ・地色 #DE822F の squircle (角丸 220px)
  ・Helvetica-Bold 540pt の白 T を 3 つ、左下→中央→右上の階段配置
  ・各 -15° 傾き、奥から α 0.7/0.85/1.0 で奥行き
- tools/build-app-iconset.sh: sips で 16/32/128/256/512 の @1x/@2x 計 10 PNG 生成
- Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/ 新規
  Contents.json は macOS idiom 標準フォーマット
- xcodegen が Assets.xcassets を folder.assetcatalog として自動認識
  既存の ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon と整合

CURRENT_PROJECT_VERSION を 20260426B に更新。
```

**変更ファイル一覧** (統計):
- AppIcon.appiconset/Contents.json: 18 行追加
- icon_128x128.png～icon_512x512@2x.png: 10 個の PNG ファイル新規（合計 ~200KB）
- Assets.xcassets/Contents.json: 6 行追加

### 4.3 過去実装における alpha 値の位置付け

コミット 14397f9 では、最初から「奥行き表現」として alpha 値を段階的に設定する設計になっていた。

- **背景**: 奥行き感を視覚的に演出するため、複数の T を重ねた時に奥側を薄く、手前側を濃くしたいという要件があった
- **実装方法**: NSColor の alpha パラメータに直接割り当て、CoreGraphics のテキスト描画時に適用する
- **変更対象**: 現在の要件は「この奥行き表現を廃止し、全 T を完全不透明（1.0）にしたい」という指示

---

## 5. 想定される副作用 / リスク

### 5.1 描画結果への視覚的変化

**変更前の挙動** (現在)
- 背後の T (0.70): 薄く表示される
- 中央の T (0.85): 中程度の透明度
- 前景の T (1.00): 完全不透明（最も濃い）
- **重なり領域**: 前景の T が背後の T を「透過的に覆う」；複数の T の色が混合される（加算合成ではなく、白テキストの半透明度に応じた alpha blend）

**変更後の挙動** (全て 1.0)
- 背後の T (1.0 に変更): 完全不透明で描画
- 中央の T (1.0 に変更): 完全不透明で描画
- 前景の T (1.0 のまま): 完全不透明で描画
- **重なり領域**: 最後に描画された（前景の）T が直前に描画されたすべてのピクセルを「完全に上書き」する；透明度による混合は発生しない

### 5.2 描画順序に依存した動作

```swift
let placements: [TPlacement] = [
    TPlacement(offset: CGPoint(x: -180, y:  180), alpha: 0.70),  // インデックス 0 → 最初に描画
    TPlacement(offset: CGPoint(x:    0, y:    0), alpha: 0.85),  // インデックス 1 → 2番目に描画
    TPlacement(offset: CGPoint(x:  180, y: -180), alpha: 1.00),  // インデックス 2 → 最後に描画
]
```

**現在の描画順序**:
1. 左下 T (alpha 0.70) を描画 → canvas に書き込み
2. 中央 T (alpha 0.85) を描画 → canvas に alpha blend で合成
3. 右上 T (alpha 1.00) を描画 → canvas に alpha blend で合成

**配列の順序が逆であった場合のリスク**（不確か: 実際に逆順に変更されないかぎり実施は発生しないが、理論的には存在）
```swift
// 仮に誤って逆順に定義された場合の例
let placements: [TPlacement] = [
    TPlacement(offset: CGPoint(x:  180, y: -180), alpha: 1.00),  // 最初に描画
    TPlacement(offset: CGPoint(x:    0, y:    0), alpha: 0.85),  // 次に描画
    TPlacement(offset: CGPoint(x: -180, y:  180), alpha: 0.70),  // 最後に描画
]
```

この場合、手前の T（右上）が背後の T（左下）で完全に上書きされ、手前 T が消える。

### 5.3 alpha 値変更時の CGContext 合成モード

**現在の設定** (行 74):
```swift
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
```

これは RGBA フォーマット（R G B A のバイト順）で、pre-multiplied alpha（RGB 値が既に alpha で乗算済み）を使用。

**alpha = 1.0 に統一した場合の影響**:
- RGB 値が alpha で乗算される計算が「1.0 倍」になるため、RGB 値そのものがそのまま使用される
- ブレンドモード（通常は over）に変化はない；依然として後に描画された要素が前に描画された要素を覆う（alpha が 1.0 であれば完全に上書き）
- パフォーマンス上は微小な差（計算が単純化）

### 5.4 ビルド成果物への影響

- **Assets.car ファイルサイズ**: ほぼ変わらず（PNG の透明度情報が変わるが、バイナリサイズには大きな影響がない可能性が高い）
- **アプリケーションバイナリサイズ**: 変化なし
- **実行時メモリ使用量**: 変化なし
- **Dock / メニューバーでの表示**: 完全不透明の T により、重なり領域の視認性が変わる

---

## 6. 制約条件

### 6.1 tools/generate-app-icon.swift の構造的制約

| 制約事項 | 詳細 |
|---|---|
| **Swift スクリプト形式** | `#!/usr/bin/env swift` で直接実行可能；ビルドシステムに依存しない |
| **依存フレームワーク** | AppKit, CoreGraphics, Foundation のみ；外部ライブラリ不要 |
| **出力形式** | PNG（RGBA 8bit）に固定；他形式への変更は不可（build-app-iconset.sh の sips 入力として機能する必要があるため） |
| **Canvas サイズ** | 1024x1024 に固定（行 23）；ハードコード |
| **フォント** | Helvetica-Bold, サイズ 540pt に固定（行 27-28）；システムフォント利用で互換性あり |
| **色設定** | 背景 #DE822F（hex カラー解析機能あり）、テキスト白（1, 1, 1）に固定 |
| **描画モード** | CGContext + CTLine（Core Text）の組み合わせ；回転・透視は CGContext の affine transform で実現 |

### 6.2 CGContext 描画パイプラインの制約

```swift
ctx.saveGState()          // 行 116
ctx.translateBy(...)      // 行 120
ctx.rotate(...)           // 行 121
ctx.textPosition = ...    // 行 124
CTLineDraw(line, ctx)     // 行 125 ← この時点で NSColor alpha が適用される
ctx.restoreGState()       // 行 127
```

**制約**:
- NSColor の alpha 値は Core Text（CTLineDraw）の テキスト描画時に直接処理される
- `foregroundColor` アトリビュートの alpha は NSAttributedString 側で設定され、CGContext 側のブレンドモードに依存（デフォルト: normal/over）
- CGContext.setAlpha() のような別途の alpha 指定は使用されていない；NSColor の alpha のみが有効

### 6.3 placements 配列の制約

```swift
let placements: [TPlacement] = [
    TPlacement(offset: CGPoint(x: -180, y:  180), alpha: 0.70),
    TPlacement(offset: CGPoint(x:    0, y:    0), alpha: 0.85),
    TPlacement(offset: CGPoint(x:  180, y: -180), alpha: 1.00),
]
```

**制約**:
- 3 個の要素が固定；増減は設計変更に相当する
- オフセット（位置）と alpha は 1 対 1 で対応；個別に変更可能
- ループ処理で順序通り描画されるため、配列の要素順が描画順序に直結

---

## 7. テスト戦略

### 7.1 変更実施前の検証方法

#### 7.1.1 Swift スクリプト直接実行テスト

```bash
cd /Users/tamekuniz/GitHub/tamekuniz/TTT
swift tools/generate-app-icon.swift
```

**期待される出力**:
```
Wrote /Users/tamekuniz/GitHub/tamekuniz/TTT/tools/AppIcon-1024.png (1024x1024)
```

**検証コマンド**:
```bash
file tools/AppIcon-1024.png
```

**期待される結果**:
```
PNG image data, 1024 x 1024, 8-bit/color RGBA, non-interlaced
```

#### 7.1.2 PNG ファイルの視覚的確認

生成された `AppIcon-1024.png` をプレビューアプリで開く（Finder で右クリック → スペースキー）

**変更前** (現在の期待値):
- 左下: 薄い白 T（透明度あり）
- 中央: 中程度の白 T
- 右上: 完全に濃い白 T
- 重なり領域: 複数の T が微妙に透けて見える（色の混合）

**変更後** (alpha 全て 1.0 に変更後の期待値):
- 左下: 完全に濃い白 T（不透明）
- 中央: 完全に濃い白 T（不透明）
- 右上: 完全に濃い白 T（不透明）
- 重なり領域: 最後に描画された T のみが見える；透けて見えることはない

#### 7.1.3 AppIcon セット再生成テスト

```bash
cd /Users/tamekuniz/GitHub/tamekuniz/TTT
tools/build-app-iconset.sh
```

**期待される出力**:
```
==> Generating master 1024x1024 icon
Wrote /Users/tamekuniz/GitHub/tamekuniz/TTT/tools/AppIcon-1024.png (1024x1024)
==> Preparing /Users/tamekuniz/GitHub/tamekuniz/TTT/Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset
...
  -> icon_16x16.png (16x16)
  -> icon_16x16@2x.png (32x32)
  ... (計 10 個)
==> Writing AppIcon.appiconset/Contents.json
==> Writing Assets.xcassets/Contents.json
==> Done. Asset catalog at: .../Assets.xcassets
```

#### 7.1.4 ファイルサイズ比較

**変更前**:
```bash
ls -lh Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png
```

記録しておく。

**変更後**:
```bash
ls -lh Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png
```

比較；ほぼ同じサイズであることを確認。

#### 7.1.5 Xcode ビルド＆実行テスト

```bash
xcodebuild -scheme TypeToTalk -configuration Debug
```

成功することを確認；ビルドエラーが出ないか。

```bash
open build/Debug/TypeToTalk.app
```

アプリを実行して Dock / メニューバーアイコンが表示され、以下を視覚的に確認：

1. 背後の T が完全に見える（透けていない）
2. 重なり領域で最後に描画された T のシルエットのみが見える
3. 全体的に「奥行き感」ではなく「単純な重ね」に見える

#### 7.1.6 不確か事項：Assets.car 検証方法

**Xcode ビルド成果物の確認**:
```bash
find build -name "Assets.car" -type f
```

Assets.car が生成されることを確認；内容の詳細検証は Xcode の Asset Catalog Viewer では難しい可能性がある。
（不確か: Assets.car を直接ダンプして alpha 値を検証する方法は不明）

### 7.2 段階的テスト実施順序

| 順序 | テスト項目 | 責任 | 判定基準 |
|---|---|---|---|
| 1 | Swift スクリプト実行成功 | 実行者 | stdout に「Wrote ...png (1024x1024)」が出現 |
| 2 | PNG ファイル生成確認 | 実行者 | `file` コマンドで「PNG image data, 1024 x 1024」を確認 |
| 3 | PNG 視覚的プレビュー | 実行者 | 全 T が完全に濃い（不透明）であることを目視 |
| 4 | build-app-iconset.sh 実行成功 | 実行者 | 10 個の PNG ファイルが生成される；Contents.json が書き込まれる |
| 5 | Xcode ビルド成功 | 実行者 | xcodebuild が exit code 0 で終了 |
| 6 | アプリ起動＆ Dock 表示確認 | 実行者 | TypeToTalk.app が Dock に表示；アイコンが重なり T を視覚確認 |
| 7 | メニューバー確認 | 実行者 | メニューバーアイコンも重なり T が見える |

### 7.3 ロールバック戦略

**変更内容**:
- `placements` 配列の 3 個の alpha 値を全て 1.0 に統一

**ロールバック手段** (不確か: スクリプトが git 管理下にあるため):
```bash
git checkout HEAD -- tools/generate-app-icon.swift
```

変更内容が小さいため、元の値へ即座に復帰可能。

---

## 終了時刻

- 調査完了: 2026-04-26 11:15 JST
- 実施者: みかんっち（Claude Haiku 4.5）
- 根拠: 5 段階の詳細確認（ソースコード行番号付き、git コミット履歴、build フロー、CGContext 制約、テスト戦略）

