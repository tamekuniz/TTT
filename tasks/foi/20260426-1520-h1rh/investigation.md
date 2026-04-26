# investigation: .foi-target 整備 + ビルドナンバー bump

## 1. 関連ファイル一覧

| パス | 役割 |
|---|---|
| `project.yml`（line 13） | XcodeGen 入力。`CURRENT_PROJECT_VERSION: "20260426E"` を含む。Info.plist の `$(CURRENT_PROJECT_VERSION)` 展開元 |
| `Sources/TypeToTalk/Resources/Info.plist`（line 7-8） | `CFBundleVersion` を `$(CURRENT_PROJECT_VERSION)` で展開 |
| `Sources/TypeToTalk/Views/SettingsView.swift:445` | `info["CFBundleVersion"] as? String ?? "-"` で読み取り、設定画面に表示 |
| `scripts/generate_build_number.sh` | Xcode build phase 用の自動採番スクリプト。`YYYYMMDD + 連番アルファベット (A→B→...→Z→AA)` 形式を生成 |
| `scripts/build_app.sh` | `xcodebuild` ラッパー。`./scripts/build_app.sh [Debug|Release]` でビルド |
| `.foi-target` | **未存在**（新規作成対象） |
| `~/.claude/skills/フォーメーションI/SKILL.md` Step 8 節 | `.foi-target` スキーマの正本 |

## 2. 既存実装パターン

- **バージョン書式**: `YYYYMMDD + アルファベット連番`（例: `20260425D` / `20260426E`）。`generate_build_number.sh` のロジックは `YYYYMMDD` 部分が変わると連番リセット、同日内は A→B→C→...→Z→AA→AB の base-26 ライク連番（実装は`(suffix_index % 26)` で 1 桁ずつ取り `prefix` を `+1` する）
- **手動 bump**: `project.yml:13` の string 値を直接書き換える（`sed -i` / Edit）
- **Xcode 採番との関係**: `generate_build_number.sh` は build phase で実行されるため、`xcodebuild` 実行時に `CURRENT_PROJECT_VERSION` を上書きする。手動 bump 後に Xcode が走ると Xcode の値で上書きされる可能性があるが、commit 時点では手動値が project.yml に残る
- **過去のフォK サイクルの bump 例**: コミット `a578b32 [フォK] fix: Bonsai 状態伝播＋自動ロード健全化＋ビルド20260425D` のように、コミットメッセージにビルド番号を含める習慣あり

## 3. 影響範囲

**書き換える箇所（2ファイル新規/編集）**:
1. **`.foi-target`**（新規作成）: プロジェクトルートに配置
2. **`project.yml:13`**: `CURRENT_PROJECT_VERSION: "20260426E"` → `"20260426F"`

**触らない箇所**:
- `Sources/TypeToTalk/Resources/Info.plist` — `$(CURRENT_PROJECT_VERSION)` で project.yml から展開されるので無編集
- `scripts/generate_build_number.sh` — Xcode 自動採番ロジックは並走させる方針（Constraints 3）
- `scripts/build_app.sh` — ビルドコマンド側に変更不要

**呼び出しチェーン**:
```
project.yml: CURRENT_PROJECT_VERSION
  → XcodeGen 展開
  → Xcode build settings の CURRENT_PROJECT_VERSION
  → Info.plist の CFBundleVersion ($(CURRENT_PROJECT_VERSION))
  → ビルド成果物 (TypeToTalk.app/Contents/Info.plist)
  → SettingsView (実機表示)
```

## 4. 過去の類似実装

- **既存フォK サイクルでのビルド番号 bump**: コミット履歴 `a578b32 [フォK] fix: ... ビルド20260425D` のように、フォK サイクル毎にビルド番号がコミットメッセージに記録されている。手動 bump の運用は確立済み
- **memory `[feedback_fok_step8_version_bump]`**: 「フォK Step 8 では .fok-target のバージョン値を毎サイクル必ず更新。飛ばすと .fok-target が無意味になる」と既に記録あり。フォI Step 8 にも同精神を適用するのが今回の意図
- **memory `[feedback_ttt_always_bump_version]`**（今回追加）: TTT は毎コミット ビルドナンバー必ず上げる。例外なし

## 5. 想定される副作用 / リスク

- **直前コミット (5c88970) との衝突**: 5c88970 が `20260426E` のままなので、F に上げる新コミットを別途打つ。重複ナンバーは生まれない
- **Xcode 自動採番との競合**: `generate_build_number.sh` が build phase で `CURRENT_PROJECT_VERSION` を上書きする可能性あり。ただし対象は `.app` 内の Info.plist で、project.yml には反映されないため commit 履歴への影響なし
- **`.foi-target` の VERSION_FILE_1_PATH "project.yml" がパス末尾一致で別ディレクトリの project.yml に誤マッチするリスク**: TTT には他に project.yml は無い（`find . -name project.yml` で確認可能）。リスク低
- **Picker UI への影響**: 無し（バージョン番号は SettingsView の info dict 表示専用、ロジックには影響しない）

## 6. 制約条件

- **既存ビルド書式 YYYYMMDDX 厳守**: `20260426F` は `20260426 + F`（前回 E の次）。日付は今日 (2026-04-26) のまま、suffix 文字を `E → F` に進める
- **`.foi-target` は KEY=VALUE bash source 可能形式**: スキル SKILL.md に厳格な書式定義あり。コメント `#` 可、文字列値はクオートしてもしなくてもよいが、空白を含む値（VERSION_FORMAT 等）はクオートする
- **VERSION_FILE_1_PATH のパス指定深さ**: SKILL.md 注意事項「`progress` phase の許可パターンは末尾一致も含むため、Info.plist のような短いパスだと別ディレクトリの同名ファイルも通る。**できるだけ深く指定**」。今回 `project.yml` はリポジトリルート直下で他に同名ファイル無いため `project.yml` のままで OK
- **コミット範囲**: ロジック変更は無いので Step 6 で `.foi-target` 作成と `project.yml` 編集の 2 ファイル変更のみ

## 7. テスト戦略

**Unit Test**: 該当なし（バージョン文字列のテストは存在せず、書式テストを今追加する価値もない）

**ビルド検証（手動、Step 8 でズンジー依頼）**:
- `./scripts/build_app.sh` Debug ビルド成功
- ビルド後 `.app/Contents/Info.plist` の `CFBundleVersion` が `20260426F` であること（Xcode 自動採番が後から書き換える可能性ありなので、commit 値が「最低限」`20260426F` に上がってる確認）
- 起動して設定画面でビルドナンバー表示が `20260426F` 以降であること

**ファイル整合性検証（シア自身が Step 7 で実施）**:
- `git show HEAD:project.yml | grep CURRENT_PROJECT_VERSION` で前回値 (`20260426E`) を確認
- 編集後 `grep CURRENT_PROJECT_VERSION project.yml` で `20260426F` になっているか確認
- `.foi-target` を `bash -n` または `source` で構文チェック
