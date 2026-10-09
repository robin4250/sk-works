# Release導入前の既知ローカル変更の保存

対象は、ユーザーが提示した `analysis_options.yaml` の先頭に `analyzer`、`exclude`、`build/**`、`android/**`、`ios/**` の5行だけを追加した変更です。現在のMacの状態は別途確認が必要です。

`python3 tool/preserve_known_analysis_options.py` は main ブランチかつその変更だけの場合に、制限付き権限のディレクトリへ原本を保存し、保存内容を照合してからGit管理版へ戻します。別の変更、ステージ済み変更、未追跡ファイル、異なるブランチがある場合は元の変更を保持して停止します。diff・接続設定・ソース内容を出力せず、自動stashは行いません。

このPRがmainへ統合され、対象mainのCIが成功した後のMac手順です。まず `git status --short` と既知ファイルのdiffを確認します。古いチェックアウトにはhelperがないため、fetch済みmainから作業ツリーを変更せず一時ファイルへ取得して使用します。fetchはソース変更を破棄しません。

```bash
cd /Users/ryuichi/Desktop/sk-works
test "$(git branch --show-current)" = main && git fetch origin main && sko_helper_dir="$(mktemp -d)" && git show FETCH_HEAD:tool/preserve_known_analysis_options.py > "$sko_helper_dir/preserve_known_analysis_options.py" && python3 "$sko_helper_dir/preserve_known_analysis_options.py" && bash tool/pre_install_source_backup.sh && git merge --ff-only FETCH_HEAD && bash tool/device_day.sh 00008110-00120536010A801E
```

既存のXcode 27.0・保存済みソース・生成iOS設定・Releaseチェックを緩和しません。導入はReleaseのみ、Bundle ID `com.skworks.skWorks` への上書きであり、既存アプリは削除しません。この保存コピーはソースの復旧用であり、iPhoneや本番DBのバックアップではありません。

既知diffを保存してGit管理版へ戻す処理は、使い捨てGitリポジトリで検証しました。現在のMacの処理・最新Releaseの導入・各機能の実操作・本番DB適用・TestFlight公開は、この検証では実施していません。
