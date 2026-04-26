# TODO: generate-app-icon.swift の alpha 値統一化

## 概要

`tools/generate-app-icon.swift` 内の `placements` 配列の 3 個の alpha 値（0.70, 0.85, 1.00）をすべて `1.0` に変更し、master PNG (1024x1024) を再生成。続けて `tools/build-app-iconset.sh` を実行して 10 個の派生 PNG を上書きする。Asset カタログ (Contents.json) は build-app-iconset.sh が再生成する。

描画順序（奥 → 中央 → 手前）は維持する。alpha が 1.0 でも、最後に描画される手前 T が背後の T を上書きするため、配列順序の意味は残る（誤って逆順にすると手前 T が背後 T で覆われない構図になる）。

## タスク（1 件で完結 — 小修正）

### Task 1: alpha 統一化と PNG 再生成

**対象**: 1 件のスクリプト編集 + 2 件のシェル実行

#### 1-1. tools/generate-app-icon.swift 編集
- **ファイル**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/tools/generate-app-icon.swift`
- **変更箇所**: 行 39-43 の `placements` 配列
- **変更内容**: 各 `TPlacement(...)` の alpha 引数を以下のとおり `1.0` に統一する

  変更前:
  ```swift
  let placements: [TPlacement] = [
      TPlacement(offset: CGPoint(x: -180, y:  180), alpha: 0.70),  // back (lower-left visually -> drawn first)
      TPlacement(offset: CGPoint(x:    0, y:    0), alpha: 0.85),  // middle
      TPlacement(offset: CGPoint(x:  180, y: -180), alpha: 1.00),  // front (upper-right visually -> drawn last)
  ]
  ```

  変更後:
  ```swift
  let placements: [TPlacement] = [
      TPlacement(offset: CGPoint(x: -180, y:  180), alpha: 1.0),  // back (lower-left visually -> drawn first)
      TPlacement(offset: CGPoint(x:    0, y:    0), alpha: 1.0),  // middle
      TPlacement(offset: CGPoint(x:  180, y: -180), alpha: 1.0),  // front (upper-right visually -> drawn last)
  ]
  ```
- **変更しない**: offset、コメント中の "back/middle/front" の意味、構造体定義、drawT 関数本体、CGContext のブレンドモード設定、描画順序（ループ順序）
- **使用ツール**: Edit

#### 1-2. Swift スクリプト実行（master PNG 再生成）
- **コマンド**: `swift /Users/tamekuniz/GitHub/tamekuniz/TTT/tools/generate-app-icon.swift`
- **期待出力**: `Wrote /Users/tamekuniz/GitHub/tamekuniz/TTT/tools/AppIcon-1024.png (1024x1024)`
- **生成物**: `tools/AppIcon-1024.png` が上書き更新される（1024x1024 RGBA PNG）

#### 1-3. build-app-iconset.sh 実行（10 PNG 一括再生成）
- **コマンド**: `/Users/tamekuniz/GitHub/tamekuniz/TTT/tools/build-app-iconset.sh`
- **動作**: master PNG を sips で 16/32/128/256/512 の @1x/@2x にリサイズし、`Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/` 配下の 10 個の `icon_*.png` を上書き。AppIcon.appiconset/Contents.json と Assets.xcassets/Contents.json も再生成される（既存と同内容）。
- **生成物（上書き 10 件）**:
  - icon_16x16.png / icon_16x16@2x.png
  - icon_32x32.png / icon_32x32@2x.png
  - icon_128x128.png / icon_128x128@2x.png
  - icon_256x256.png / icon_256x256@2x.png
  - icon_512x512.png / icon_512x512@2x.png

## 検証観点（実装小人ちゃんが Step 5 で行う）

1. `swift tools/generate-app-icon.swift` が exit 0 で完了し、`Wrote ... (1024x1024)` が stdout に出る
2. `file tools/AppIcon-1024.png` が `PNG image data, 1024 x 1024, 8-bit/color RGBA, non-interlaced` を返す
3. `tools/build-app-iconset.sh` が exit 0 で完了し、10 個の icon PNG と 2 個の Contents.json が更新される
4. `git status` で変更ファイルが以下に絞られていること
   - `tools/generate-app-icon.swift`
   - `tools/AppIcon-1024.png`
   - `Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png`（10 件）
   - `Sources/TypeToTalk/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`（差分なしの可能性あり）
   - `Sources/TypeToTalk/Resources/Assets.xcassets/Contents.json`（差分なしの可能性あり）
5. プレビュー目視: `tools/AppIcon-1024.png` を開き、3 個の白 T がすべて完全不透明で重なり合っていること（背後 T は手前 T に覆われた領域では見えない）

## 制約・注意

- **描画順序は変更しない**: 配列の要素順（奥 → 中央 → 手前）を入れ替えると手前 T が消える構図になる。順序維持必須。
- **offset は変更しない**: 位置調整は今回のスコープ外。
- **Asset カタログ Contents.json は手動編集しない**: build-app-iconset.sh が冪等に再生成する。
- **Xcode ビルド検証は Step 5/7 のスコープ**: 本プランナーは PNG 再生成までを 1 タスクとして定義する。

## 想定リスク

- **視覚的変化**: 重なり領域で背後 T が完全に隠れる。ズンジーの要件（全 alpha 1.0）と一致するため許容。
- **PNG ファイルサイズ**: わずかに増減する可能性（透明画素が減るため微増の可能性が高い）。実害なし。
- **Assets.car への影響**: ビルド時に再コンパイルされるが、サイズ・実行時挙動への影響は無視できるレベル。
