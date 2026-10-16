# 本番権限変更前のバックアップ・隔離復元・承認

これは新しい隔離検査用手順です。本番DB、Auth、Storage、Edge、Apple/Google設定へ接続・変更するスクリプトではありません。参照mainは `04d90559c8929c71b0b91f743066795b28007067`。新しい変更は個別ブランチで保持し、既存UI、管理者ID、会社ID、所属、役割を作り直して復旧しません。

## 現在の証拠と不足

| 対象 | このPRで実行すること | 本番変更の前に必要なこと |
|---|---|---|
| ソース・未保存変更 | 合成GitでHEAD、staged/unstaged差分、未追跡ファイルをバックアップし、新規一時Gitへ復元、bytes/index/dirty状態一致を実行検査 | 実作業checkoutの別の安全な保存先での成功記録。既存の保護済みbranch/patch記録を維持 |
| 管理者ID・会社ID・所属・役割・権限 | 合成IDで比較器を実行。公開出力にIDを載せない | 実値を非公開で採取し、復元前後の同一ID・role・所属・機能権限を照合。**実値はこのPRで採取していない** |
| DBデータ・定義・ACL・RLS・関数 | 接続・dump・restoreを実装しない | スキーマ、データ、GRANT/DEFAULT PRIVILEGES、RLS、関数、所有者、拡張のバックアップと別DBでの復元。既知の移行だけでは不十分 |
| Auth・Apple/Google | 設定を読まず変更しない | provider有効状態、redirect、アプリ識別、認証資格情報の保管先、既存アカウント紐付けを非公開で確認。Apple/Googleの実ログインは未検証 |
| Edge・秘密設定 | 配備もsecret取得も行わない | 配備済み関数version/config/verify_jwtと元コードdigest、必要なsecret名・復旧可能な保管先を確認。secret値をGitHub・ログ・一般資料へ載せない |
| Storage | ファイル取得・URL発行なし | private/public bucket、ポリシー、object一覧・実ファイル、暗号化保管・整合・署名URLの扱いを確認。DB dumpだけではStorage bytesを復元できない |
| 本番許可 | 比較結果が一致しても許可しない | 差分、対象、exact SQL/Edge SHA、隔離復元結果、影響、戻し方を示し、**利用者の明示承認後だけ**本番権限変更へ進む |

実DB dump、実管理者ID/provider設定の安全な保存、Auth/Storageを含む隔離復元、Apple/Googleの動作、本番変更の承認は、現時点では**未確認・未実行**です。合成試験成功をその代わりにしません。

## ソースだけを保護・隔離復元する

Python 3.12以降とGitを使います。保存先は**どのGit checkoutにも属さない既存親ディレクトリ**の下で、まだ存在しないディレクトリを指定します。保存物にはコード中の秘密や個人情報が含まれる可能性があるので、暗号化ディスク等の適切な非公開保存先を選びます。ディレクトリ700、ファイル600を使用し、標準出力へ実ID・差分内容・パスを出しません。

```bash
python3 tool/security/recovery_source.py snapshot --repo /absolute/source --output /absolute/private-parent/new-snapshot
python3 tool/security/recovery_source.py rehearse --snapshot /absolute/private-parent/new-snapshot --parent /absolute/private-rehearsal-parent
```

元checkoutをreset/clean/stash/checkout/add/commitしません。復元先はhelperが作る新しい `sko-recovery-rehearsal-*` ディレクトリだけです。HEADのtar、binary差分、現在ファイルのSHAを保存し、変更が検出されたら不完全なsnapshotを使わず停止します。復元のbaseline commitは架空の新規commitであり、元Git履歴・署名の復元ではありません。元SHAはmanifestに記録します。復元検査後も元checkoutとsnapshotを保持します。

対象は追跡済みファイルとGitが無視していない未追跡ファイルです。ignoredファイル（ローカル認証設定等）、Git credential/config、Git全履歴、LFSの外部object、submodule、symlink、iPhoneデータ、DB/Auth/Storage/Edge、署名証明書、過去のArchiveは含みません。submodule/symlinkは黙って追わず停止します。別の安全なバックアップが必要です。設定差などでindex/statusが一致しない場合も自動修正せず停止します。

## 実DBの隔離復元は別の承認済み作業

最初に使用予定の実バージョンで `pg_dump --version`、`pg_dump --help`、`pg_restore --version`、`pg_restore --help` を読み、利用可能なオプションとSupabaseの現在のバックアップ範囲を確認します。このPRは未確認のCLIオプションや本番接続コマンドを提示・実行しません。DB dumpとロール定義・Auth設定・Edge secrets・Storage実ファイル・外部provider設定は同じバックアップではありません。

復元先はネットワーク隔離された新規の使い捨てPostgreSQLに限定し、外向きHTTP、通知、Webhook、cron、メール/SMS、外部provider認証を止めます。DB名は `sko_recovery_fixture_<32桁hex>`、接続は明示loopbackのみ。既存DB・本番project・remote host・資格情報入りURLを拒否します。実データを使う場合はコピー先のアクセス・保管・削除方針も確認します。

`recovery_source.py database-target-shape` はこのURL形状だけを検査します。許容形状でも終了コード2で**復元をBLOCK**し、freshness・catalog・権限・dumpの確認済みとは扱いません。接続/復元機能は存在しません。単なる `approved=true`、名前がfixtureらしいこと、利用者が選んだURLだけで実行を許可しません。

本当に復元を行う担当は、空の新規DBである実catalog、所有者、接続先、拡張、外部送信停止、バックアップdigestを確認した証拠を取得し、freshness不明なら停止します。復元後に実件数/ID/role/ACL/関数/Storage整合を照合し、既存の許可ケースと匿名・他社・権限OFFの拒否を実HTTPでも確認します。戻し方はその復元先で実行検証します。本番でrollback演習をしません。

## 非公開の重要状態比較

`recovery_compare.py` が使うartifact契約は `recovery_critical_state.schema.json` です。各sectionには観測した実値、`status=observed`、採取した証拠のSHA256を記録します。admin_identityには既存user ID、所属にはcompany/user/role、master割当と機能フラグは現在の実値を含め、以前と同じであることを確かめます。証拠と実値はアクセス制限した非公開ファイルへ保存し、公開するのはdigest・比較結果だけにします。

```bash
python3 tool/security/recovery_compare.py --before /private/before.json --after /private/restored.json --output /private/new-comparison.json
```

不足、unknown、空値、公開可能permissionなら停止します。比較器は渡されたexportの一致を確認するだけで、採取元の真正性・実DB復元・provider動作を認証しません。一致しても `production_change_authorized=false` です。実施担当による証拠レビューと利用者の明示承認を自動化しません。

## 承認の前に示すもの

1. 保護したsource SHA・未保存差分・バックアップdigest・非公開保存場所の管理者。
2. 変更するpolicy/function/Edgeとexact artifact SHA、変更しない既存ID・所属・role・UI・providerの範囲。
3. 隔離した実復元の結果、正常ケース維持と拒否ケース、復元前後の重要状態比較、戻す手順の実行結果。
4. 残るunknown、利用者影響、ロールバック条件。unknownを合格にしない。
5. 上記の具体的な変更に対する利用者の明示承認。別変更への包括承認として流用しない。
