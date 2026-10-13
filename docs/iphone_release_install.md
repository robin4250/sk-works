# iPhoneへ最新mainのReleaseを上書きする

対象Macは `/Users/ryuichi/Desktop/sk-works`、対象iPhoneは
`00008110-00120536010A801E`。Flutter 3.47.5 / Xcode 27.0 を使う。
最新mainのFlutter・iOS・Secret Scanが成功した後に実行する。
Apple Developer会社登録やTestFlight公開の完了とは別の作業。

Macで実行する1行コマンド：

```bash
cd /Users/ryuichi/Desktop/sk-works && test "$(git branch --show-current)" = main && bash tool/pre_install_source_backup.sh && git fetch origin main && git merge --ff-only FETCH_HEAD && bash tool/device_day.sh 00008110-00120536010A801E
```

main以外のブランチ、未保存変更、分岐、バージョン不一致、署名不足の場合は
自動破棄や強制更新をせず停止する。停止した場合は原因を直して同じコマンドを
再実行する。接続値や署名のローカル設定を消したり上書き保存したりしない。
ソースバックアップはpull前と導入前に作成する。iPhone内のデータや本番DBの
バックアップを作成する処理ではない。

`device_day.sh` が静的検証・テスト・iOS生成設定・実機署名を確認した後、
Releaseをビルドする。Bundle IDが `com.skworks.skWorks` と一致する場合に
`devicectl` で既存アプリへ上書きし、同じアプリを起動する。
アプリ削除、Debug導入、`flutter run` は行わない。

`App installed` の実ログとアプリ起動を確認して初めて導入済みとする。
ケーブルを抜いてSKOを完全終了し、ホーム画面から単体起動も確認する。
カメラ・GPS、夜勤/月跨ぎ、日報、確認通知などの操作確認はCIの成功と別に記録する。
こちらのLinux作業環境からユーザーのMacやiPhoneは操作できないため、
コマンドを提示しただけではインストール済みとは扱わない。

鮮度チェックは `git fetch origin main` の取得結果 `FETCH_HEAD` とHEADを比較する。
狭いremote fetch設定では `origin/main` が更新されないことがあるため、
古いremote tracking SHAを最新mainの判定に使わない。
