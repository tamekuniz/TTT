# Progress: generate-app-icon.swift alpha 統一化

## ステータス凡例

- [ ] 未着手
- [~] 着手中
- [x] 完了
- [!] 問題あり / 要相談

## タスク進捗

### Task 1: alpha 統一化と PNG 再生成

- [ ] 1-1. tools/generate-app-icon.swift の placements alpha を全て 1.0 に Edit
- [ ] 1-2. `swift tools/generate-app-icon.swift` 実行（master PNG 1024x1024 再生成）
- [ ] 1-3. `tools/build-app-iconset.sh` 実行（派生 10 PNG + Contents.json 再生成）

## 検証チェックリスト

- [ ] swift スクリプトが exit 0 で完了、stdout に `Wrote ... (1024x1024)` 出力
- [ ] `file tools/AppIcon-1024.png` が `PNG image data, 1024 x 1024, 8-bit/color RGBA` を返す
- [ ] build-app-iconset.sh が exit 0 で完了、10 個の icon PNG が更新される
- [ ] git status で想定外のファイル変更がない（swift / master png / 10 派生 png / 2 Contents.json のみ）
- [ ] 目視: AppIcon-1024.png の 3 T が全て完全不透明、背後 T が手前 T に覆われた領域で透けない

## 実行ログ

（実装小人ちゃんが各タスク完了時に追記する）

## 課題 / 相談事項

（発生時に追記）
