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

## 取得手段の不足照合（2026-10-16・追加調査のみ）

この節はツール定義と公式資料の照合であり、本番の権限・契約・バックアップ有無を実測した結果ではありません。秘密、実ID、実データ、Storageファイルを取得せず、本番SQLやdumpを実行していません。

PATH上ではSupabase CLI、Postgres各CLI、Dockerを検出しませんでしたが、既存の `/tmp/sko-reauth-cli/supabase` **2.121.0** は確認済みです。実行したのは `--version`、`db dump --help`、`functions download --help`、`secrets list --help` だけです。他の場所のPostgres/Docker導入有無や接続資格情報は未確認です。CLIが存在することは、DB接続・Docker・backup読取権限・実復元が揃った証拠ではありません。

| 対象 | 現在呼べるツール・確認済みの取得手段 | 足りないもの・取得前の条件 |
|---|---|---|
| schema/RLS/ACL/関数/拡張 | MCP `execute_sql` のcatalog限定SELECT、`list_tables`、`list_extensions`、`list_migrations`。CLI 2.121.0には `db dump` のschema/role/data各オプションあり | 接続権限を持つ担当、既存DB接続情報の安全な利用、Docker等の実行基盤、dump内容の棚卸し・時点整合。SQLのSELECT結果やmigration履歴を完全dumpと扱わない |
| DB roles/data/アプリ管理者ID・所属 | 公式はroles/schema/dataを分けて取得。現在のMCPにはファイルとして完全backupを取得する専用ツールなし | 全対象を読めるDB接続と非公開保存先。実user/company/membership/master IDは採取・比較未実施。custom LOGIN roleのpasswordは通常dumpに含まれない。既存passwordを無断resetしない |
| Authのユーザー・identity・関連行 | 公式の復元対象に `auth.users` 等あり。ただしCLI既定dumpはmanaged schemaを除外し、既定ではdata/custom roleも含まない | Auth行と既存IDが実際に含まれるdumpを確認。`auth`/`storage`の独自trigger/RLS、managed schema内独自function、migration historyは別の保存範囲として点検。元UUIDとアプリ所属の参照を復元後比較 |
| 自動backup/PITR | 公式DashboardのDatabase Backups、Management APIのbackup一覧/予定取得 | このセッションにbackup一覧/downloadの専用MCPは露出なし。Backups Read権限を持つ担当の確認が必要。プラン・保存時点・download可否は未確認。`restore_project(project_id)`は対象backup・隔離先を指定できない変更系ツールなので検証用に呼ばない |
| Storage bytes/metadata | 公式はS3/rclone等で別コピー。現在のMCP一覧にはobject取得ツールなし | 全対象を読めるサーバー側資格情報の安全な利用と保存容量。S3生成鍵はRLSを迂回する強い権限なので新規発行・取得は自動実施しない。DB内metadataだけではbytes復元不可。key/bucket/owner/会社参照・非公開設定とbytes digestを照合し、ファイルコピー成功だけで権限保持と扱わない |
| 配備済みEdge | MCP `list_edge_functions` / `get_edge_function`、CLI `functions download`。2.121.0のhelpでDocker不要の `--use-api` を確認 | Edge Functions Readが必要。実取得は未実施。CLI downloadだけではimport map/deno.jsonが揃わないという公式注意あり。Git原本・配備bundle・依存・verify_jwt・versionの一致が必要 |
| Edge secrets/Vault/暗号化 | 公式Management APIにsecret一覧権限等あり。CLIはlistのhelpのみ確認 | 一覧やdigestは値の復元用backupではない。元のsecret保管者・安全な復旧手段が必要。Vault/列暗号化がある場合は復号鍵の復旧方式も別確認。秘密値を本チャット・GitHub・標準出力へ取得しない |
| Apple/Google・Auth/SMTP/redirect設定 | 公式Management APIのAuth Config Read、provider各consoleの管理者による非公開確認 | 現在のMCPにはAuth config取得が露出なし。接続済みアプリの権限不足と断定せず、取得経路が未準備と記録。providerコンソール権限、client識別/redirect/鍵保管先を確認。実ログイン・account紐付け・復旧は未検証 |

取得に必要な権限は作業ごとに分けます。Management APIは対象project限定のBackups Read、Database Read、Edge Functions Read、Auth Config Read等を公式のscope表で確認し、所有者の権限を越えて付与できません。DB password接続はPATのscopeとは別の権限境界です。MCPに無い取得機能を、SQLからOSファイルを読んだり、別ツールの認証情報を取り出して代用しません。

隔離先は実Postgres/Auth/Storageのバージョンと拡張を合わせ、外部送信を遮断します。復元先のdefault privilegesによる予期せぬGRANT追加、custom role password、Realtime publication、Auth/Storage独自定義、Vault鍵、Edge依存を照合対象に含めます。公式の汎用復元例をそのまま本番へ実行せず、不足した定義を削って合格にしません。self-hosted復元はJWT鍵やprovider設定が別であり、元の管理者ID保持と旧JWT継続利用は別の条件です。本番Apple/Googleのredirectを隔離試験のために書き換えません。

一次資料（確認日2026-10-16）：[DB backups](https://supabase.com/docs/guides/platform/backups)、[CLI backup/restoreとmanaged schema注意](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)、[db dumpの既定除外とdefault privileges](https://supabase.com/docs/reference/cli/supabase-db-dump)、[self-hosted復元の範囲](https://supabase.com/docs/guides/self-hosting/restore-from-platform)、[Storage別コピー](https://supabase.com/docs/guides/self-hosting/copy-from-platform-s3)、[PATの権限表](https://supabase.com/docs/guides/platform/personal-access-tokens)。changelogの[2026-10-06 scoped PAT一般提供](https://supabase.com/changelog/scoped-personal-access-tokens-ga)と[2026-06-17 self-hosted PG17移行](https://supabase.com/changelog/46080-self-hosted-supabase-upgrading-from-pg-15-to-17-breaking-change)も確認し、古い例のPostgres版や一律権限を前提にしません。
