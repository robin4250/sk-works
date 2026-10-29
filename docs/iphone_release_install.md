# iPhoneへ検証済みReleaseを上書きする

## 現在のXcode 27.1環境：所有者本人のRelease

ユーザーのXcode 27.1 / Flutter 3.47.5では、`tool/r31_local_release.py`を使う。
下の`device_day.sh`はXcode 27.0専用の別入口であり、27.1用の手順ではない。
バージョン検査を削除したり、環境変数で回避したりしない。

最初に必要な修正をmainへ統合し、そのexact SHAの必要なCIを確認してから、
レビュー済みの完全な40桁SHAと、同じSHAにあるhelperのSHA256を確定する。
`latest main`という名前だけで候補を承認せず、過去のcheckpointやbuild番号を
新しいソースの成果物として扱わない。最終SHA確定前にビルドを開始しない。

1. Macの元作業ツリー・未保存差分・生成済みiOS・既存署名Release・ローカル接続設定を保持する。
   helperを指定したSHAから取得し、レビュー時に記録したSHA256と照合する。
2. helperの`--reviewed-sha`へ確定したSHAを渡し、所有者本人用Releaseを一度作成する。
   元リポジトリは`/Users/ryuichi/Desktop/sk-works`、保存先は既定で
   `/Users/ryuichi/SKO-source-backups/r31-...`。元のdirtyな作業を破棄せず、
   指定SHAの独立worktreeを作り、元native設定と依存を隔離する。
3. `Owner Release build verified; NOT installed`と終了コード0を確認する。
   これは署名Release作成の結果であり、インストール成功ではない。
4. 同じhelperと、今回作成されたexact checkpointを再照合し、
   `--install-checkpoint`でinstall-onlyを行う。別ビルドや旧checkpointへ自動で切り替えない。
5. `Owner Release overwrite install/launch complete`と終了コード0、実際の起動を確認する。
   ケーブルを抜き、アプリ完全終了後にホーム画面から単体起動し、ログイン・データ・権限を確認する。

helperはXcode 27.1 / Flutter 3.47.5、Releaseビルド設定・payload、Bundle ID、
署名Team/application identifier/Keychain access groupsの既存アプリとの一致を検査する。
対象は`00008110-00120536010A801E`、Bundle IDは`com.skworks.skWorks`。
元の署名済み`Runner.app`やローカル接続設定がない場合は停止するため、削除や
再生成で検査を迂回せず、停止理由を確認する。Debug導入・アプリ削除・`flutter run`は行わない。

この入口は本人端末への署名Release上書き用で、IPA作成・Transporter upload・
TestFlight配布ではない。TestFlightを使う場合は、別途レビュー済みsource・配布署名・
IPA来歴・App Store Connectのbuild番号を照合する。pubspecの番号を次の配布番号と推測しない。

本手順はソース・元native・ローカル成果物の保全を確認するもので、iPhone内データや
本番DBのバックアップ、上書き後のデータ保持そのものの実証ではない。
Linuxの作業環境からMac/iPhoneを直接操作できないため、実Macで必要な操作は
最終SHAとhelper hashを確定した後に提示する。CI成功だけで実機完了とはしない。

## Xcode 27.0専用の既存device-day入口

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

## 直接入口とツールチェーンの停止条件

このdevice-day入口ではXcode 27.1は未検証です。厳密な27.0固定は変更して
いません。この入口は27.1では生成・ビルド・導入の前に停止します。Flutterは3.47.5を
要求します。バージョン差を環境変数で「検証済み」として回避できません。

`run_ios_device.sh`の直接入口も、生成前にMac・バージョン・cleanなmain・
新しく取得したmainとの完全一致を検査します。署名Releaseビルド後、導入の
直前にも開始時SHA・clean・main・最新mainを再照合します。ネットワーク取得
失敗も停止します。自動更新・reset・変更破棄は行いません。

ソースバックアップは上記の標準コマンドと`device_day.sh`の既存処理を使い、
直接runner内では同じ段階の大きなbundleを重複作成しません。直接runnerを
単独実行する場合も、先に`pre_install_source_backup.sh`を成功させてください。
そのbundleは保存済みGitソース用です。ignoredの接続設定・生成した署名設定・
iPhone内データ・Keychain・本番DBを保存するものではありません。

この検査はソース状態の照合であり、生成バイナリの完全なprovenanceでは
ありません。同時に他のプロセスでソースを書き換えないでください。Release
署名・Team/profile/entitlementsと既存アプリの適合、上書き後のデータとKeychain
保持、実インストール、ケーブルなし起動の証拠は実Mac/iPhoneで別途必要です。
`device_day_preflight.sh`は生成設定・接続確認・unsignedビルドも行うため、
read-onlyな診断コマンドとして実行しないでください。
