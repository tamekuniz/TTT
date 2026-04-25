# Progress: Whisper hallucination 3層防御

**サイクル ID**: 20260425-1959-k7n1
**起票**: 2026-04-25
**プランナー**: メロン（フォK Step 4）

---

## ステータス

- [x] Step 3: 調査完了（ゆず → investigation.md）
- [x] Step 4: 計画完了（メロン → todo.md / progress.md）
- [x] Step 6: 実装完了（ぶどう）
  - [x] hallucinationPatterns static let 追加（18件）
  - [x] filterHallucinations 関数追加（trim + 完全一致）
  - [x] WhisperKitConfig 経由で EnergyVAD 設定（energyThreshold: 0.02、frameLength: 0.1）
  - [x] DecodingOptions の auto/言語指定 両分岐に noSpeechThreshold: 0.4 追加
  - [x] transcribe() return 直前でフィルタ適用、lastTranscription も統一
- [x] Step 7: 検証完了（sonnet 検証小人ちゃん）
  - [x] xcodebuild BUILD SUCCEEDED
  - [x] grep で全項目確認 PASS
  - [x] 品質セルフチェック OK
- [x] Step 8: ビルド番号 20260425C 更新、ビルド再生成、検証
- 実機シナリオ確認はズンジー側で実施予定
  - シナリオ A: 完全無音録音 → hallucination が出ないこと
  - シナリオ B: 通常発話 → 認識精度劣化なし
  - シナリオ C: 「ご視聴ありがとうございました」を実際に発話 → フィルタで削除されてしまう既知の妥協（次サイクルで Levenshtein 等の改良候補）

---

## 設計判断ログ

### 2026-04-25 メロン：3 層を 1 サイクルに集約

- **判断**: VAD / フィルタ / パラメータ調整を 1 サイクル・1 タスクに統合。
- **理由**: 3 層の効果は独立しないため、別サイクルに分けると「VAD だけ入れたが hallucination 残った → 次サイクルでフィルタ」という回り道が必要になる。1 度に投入して実機検証する方がトータルで早い。
- **代償**: コミット粒度が大きくなる（WhisperManager に 5 箇所変更）。レビュー観点を todo.md で明確化することで補う。

### 2026-04-25 メロン：DecodingOptions は Stage 1 のみ

- **判断**: noSpeechThreshold 0.4 のみ。compressionRatioThreshold / logProbThreshold は触らない。
- **理由**: シア指定。Stage 2/3 は日本語精度低下と再トライ遅延のリスクが大きく、Stage 1 + VAD + フィルタで足りるかを先に検証すべき。
- **次回**: 実機で「無音録音時に hallucination がまだ出る」現象が確認されたら Stage 2 を追加する。

### 2026-04-25 メロン：hallucination リストは static let（Set）

- **判断**: WhisperManager 内に `private static let hallucinationPatterns: Set<String>` で定義。
- **理由**:
  - Set にすることで O(1) lookup
  - static で 1 度だけ確保
  - private で他クラスからの誤用防止
  - 多言語化は将来 `[String: Set<String>]` への拡張で対応可能
- **初版件数**: 18 件（日本語 10 + 英語 8）。投入後にユーザー実測で増減。

### 2026-04-25 メロン：完全一致 trim 比較を採用

- **判断**: 部分一致や正規表現は使わない。`text.trimmingCharacters(in: .whitespacesAndNewlines)` してから Set.contains() で完全一致判定。
- **理由**: 部分一致は正常発話の誤削除リスクが高い（例: ユーザーが「ありがとうございました」を含む長文を話した場合）。誤削除より hallucination 残存を選ぶ。

---

## 実装中の発見 / 課題

(Step 5 開始時に小人ちゃんが追記)

---

## 自己検証結果

(Step 7 で実測を追記)

### シナリオ A: 完全無音 5 秒
- 結果:
- 判定:

### シナリオ B: 通常発話
- 結果:
- 判定:

### シナリオ C: 定型句発話
- 結果:
- 判定:

---

## 次サイクル候補メモ

- DecodingOptions Stage 2 (compressionRatioThreshold: 2.0)
- DecodingOptions Stage 3 (logProbThreshold: -0.8)
- 多言語ホワイトリストの言語別辞書化
- フィルタリスト編集 UI
- AudioRecorder 側のリアルタイム VAD
- ユーザー発話と hallucination の区別（前後文脈 / Levenshtein 距離）
