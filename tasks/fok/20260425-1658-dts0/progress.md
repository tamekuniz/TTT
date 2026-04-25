# progress: マイクボタンパルス停止バグ修正

## ステータス

- [ ] タスク 1: `.animation(value:)` ベースへ切替（`TypeToTalkApp.swift` L42-80 周辺）
  - [ ] A. `.scaleEffect` / `.opacity` の条件式を `isPulsing` 単一参照に簡素化
  - [ ] B. `.animation(value: isPulsing)` modifier を追加（`isRecording` で repeatForever / easeInOut(0.2) を切替）
  - [ ] C. onChange を `isPulsing = recording` の値同期だけに簡略化
- [ ] ビルド: `swift build` がエラー/警告ゼロで通る
- [ ] テスト: `swift test` 16 件 PASS
- [ ] 実機目視: 受け入れ条件 1-4 を全て満たす
- [ ] スコープ外（色/アイコン/触覚/ProgressView/録音操作）に変更が漏れていない

---

## 実装ノート（小人ちゃんが書き込む欄）

### 試した modifier 順序

- （ここに、ZStack に掛けたか、Circle 単体に掛けたか等を記録）

### パターン2 で動作した / しなかった

- （動作したならそのまま完了。しなかった場合はフォールバック判断と理由を記録）

### 想定外の副作用

- （ProgressView / icon への干渉など、目視で気づいた点）

---

## 受け入れ条件チェックリスト

- [ ] 1. 録音開始でパルス開始（scale 1.08 / opacity 0.85 / 0.8 秒往復）
- [ ] 2. 録音終了から 0.2 秒以内に scale=1.0 / opacity=1.0 へ戻る
- [ ] 3. 戻った後 3 秒以上、パルスが完全静止（再開しない）
- [ ] 4. 開始 → 停止を 5 サイクル繰り返してもパルス残存なし
- [ ] 5. `swift build` 成功 / `swift test` 16 件 PASS

---

## 検証コマンド

```bash
cd /Users/tamekuniz/GitHub/tamekuniz/TTT && swift build
cd /Users/tamekuniz/GitHub/tamekuniz/TTT && swift test
cd /Users/tamekuniz/GitHub/tamekuniz/TTT && swift run TypeToTalk
```

---

## 完了報告（小人ちゃんが最終的に記録）

- 実装サマリ:
- 変更ファイル: `Sources/TypeToTalk/App/TypeToTalkApp.swift`
- ビルド結果:
- テスト結果:
- 実機確認結果:
