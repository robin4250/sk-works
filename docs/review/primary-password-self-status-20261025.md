# 自己第一パスワード存在boolean RPC — PREPARE ONLY

固定基準main `2ab1a420658983a682a51768852531fc3c997ac1`。build14凍結、PR1368/1370、メール導線候補2b4c22cとは独立する。本番適用・本人Auth操作・provider変更・実SMS/メール送信なし。

## 原本と採用条件

既存 `secondary_password_configured()` は第二pw専用。primary password status既候補は検索で特定できず、rootの本番catalog限定読取でpublic/private両 `primary_password_configured()` 不在を確認した。本人画像はGoogle連携とメール所有確認済み、電話未登録を示すが、第一pw未設定とは断定しない。

root catalog観測: authenticatedの既private USAGE=true。`private.account_access_allowed()` はowner postgres、SQL STABLE/SECDEF、search_path空、prosrc MD5 `aeca25db212c043c472334026bd98724`、EXECUTE ACLはpostgres/anon/authenticated/service_role。bodyはauth.uid非NULLかつ既account_deletion_access_restrictionsに本人行がないことの確認である。auth.sessions id/user_id/not_after等の型存在もcatalogで確認済み。Auth行やcredentialの本番読取は行っていない。

候補installはこの既helper body MD5、owner、STABLE/SECDEF、search_path、4 ACL完全一致と既private USAGEを検査し、変化時は停止する。既helper/ACL/schema USAGEを変更しない。prosrc hashとpg_get_functiondef全文hashを混同しない。

## 2 routinesだけの契約

- `public.primary_password_configured()` は引数なし、SEC INVOKER、booleanのみ返す。
- 同名private helperはSEC DEFINER、owner postgres、search_path空、STABLEの読取専用関数。実DB roleとJWT roleがauthenticated、auth.uid/JWT sub一致、非匿名、session_id UUID存在・本人との一致・not_after未経過、既account helper IS TRUEを要求する。本人auth.users行のban/匿名状態も拒否する。
- 現actor行のencrypted_passwordが非空かどうかをSQL内部のboolean式だけで判定する。raw hash値を変数・結果・JSON・ログへ取り出さない。行不在はfalseと誤認せず固定42501で拒否する。
- 新routineだけのEXECUTEをPUBLIC/anon/service_roleから外しauthenticatedへ付与する。auth.users SELECTやschema USAGE、既routine ACLを付与しない。
- actor/email等の引数がないため他者を指定できない。正規の別ユーザーは自分自身の状態だけを取得する。別actorのsessionとの組合せ、anon/service、missing/malformed/expired session、blocked accountを拒否する。

アプリデータ・認証データのINSERT/UPDATE/DELETE、ログイン/refresh/session発行、JWT生成は行わない。データmutationがないpoint-in-time読取なので、削除処理を進める新barrier機構や不要なwriter lockは追加しない。既restriction helperをそのまま適用する。snapshot開始後の並行失効を遡って即時拒否する保証までは追加しない。

## 実GoTrue fixture再利用

既存 `login_method_enrollment_gotrue_e2e.mjs` に固定hook `SKO_PRIMARY_PASSWORD_STATUS_REVIEW=contract-v1` を追加する。unknown hookはDB作成前に拒否し、元hook無しの検証とhosted資格情報拒否を保持する。新fixture moduleが隔離schema内でexact既helper body/属性/ACLを再現し、同じreview SQLを無加工で適用する。本番helperのテーブル行はコピーしない。

既real-GoTrue flowはGoogle-only合成identity＋空passwordを確立し、実JWTでstatus false→本人 `PUT /user`→同じ元JWTでtrue→同メール/passwordによる実sameUID loginでtrueを検査する。before/afterで元session存在・Google identity・会社所属・第二pw fixture、既schema/table/routine metadata/ACLが不変であることを検査する。新2routineの所有/引数0/boolean/INV+DEF/STABLEとACLも検査する。

SQL-role denialは実JWT由来claimをfixture内で限定改変し、missing/malformed/wrong session、他actorとの組合せ、匿名、ban/not_after/restrictionを拒否する。expired/banの合成変更はtransaction rollbackする。HTTP側では実anon/service呼出し拒否も確認する。authenticatedによるauth.users raw SELECTも拒否する。この負試験でJWT署名を偽造した成功とは扱わない。

実行（root所有remoteCIの既隔離GoTrue jobを再利用）:

```sh
SKO_PRIMARY_PASSWORD_STATUS_REVIEW=contract-v1 node tool/security/login_method_enrollment_gotrue_e2e.mjs
```

専用 `.github/workflows/primary-password-self-status.yml` を追加した。pull_requestの対象path変更時、PGlite synthetic SQL runtimeと実GoTrue optionalhookを別jobで実行する。既共有workflowは変更しない。read-only contents権限、checkout credential非永続、依存は既lockfileのnpm ci --ignore-scriptsを使用し、本番secretやAuth設定を渡さない。

既条件どおりCI=true/RUNNER_TEMP、Docker、CLI固定2.121.0、既fixture_dependenciesが必要。hosted URL/鍵/DB資格情報がある環境では開始しない。標準logはbool結果/固定段階のみでraw reply/password/hash/tokenを出さない。

## 到達点・未検証

Node構文検査3件とgit diff --checkは成功。PGlite用runtime runnerも追加したが、旧依存pathが消失し現在ローカルPGlite package無しのため実行未完（起動前MODULE_NOT_FOUND）。local Docker/nativePG/Flutterも不可で、実GoTrue/SQL runtime結果はroot remoteCI待ち。依存取得のnetwork制限迂回は行わない。

本番導入前にはrootが上記catalog pinsを再照合し、2routine追加だけの原本/restore条件を確認して別工程で適用判断する。既同名routineが現れたら上書きせず再レビューする。unused撤回は新2routinesのexact definition/owner/ACLがこの候補のままかを確認した後だけpublic→private順で削除し、既helper/schema/tableには触れない。

アプリでの三値表示接続はまだ含まない。RPC導入前/404/失敗を未設定falseへ落とさずunknown保持する必要がある。適用・接続・実機で本人の状態が判別できるまで、実登録機能完成とは扱わない。14配布をこの候補の待機条件にしない。


## CI到達点の再確認と撤回候補

2026-10-24 UTC再開時、PR1377 exact `d48ceb1fb24439ebb9b1b7e873a34217bcfca363` の10check全成功をGitHub read-onlyで確認した（synthetic-sql-runtime 120972605280、isolated-real-gotrue 120972605067、既isolated enrollment 120972605200を含む）。これは上記「ローカル未実行」を変更するものではなく、別のremote結果である。real provider/本人/本番導入の成功ではない。

同headのinstall SQLは準備済みsourceと全文一致。撤回候補 `primary_password_self_status_restore_20261025.sql.review-only` は新2routineの引数0/boolean/非SETOF/STABLE/owner/SECINV対SECDEF/searchpath/prosrc MD5/EXECUTE ACLをexact照合し、いずれか不一致・欠落なら全体停止する。合致した場合だけpublic→privateを同TXでDROPし、CASCADEしない。他routine/schema/table/Auth行には触れない。DROPに外部依存があればエラーでTXを戻す。

撤回SQLはローカル/remoteとも未実行で、適用済みとは扱わない。これはデータ変更のない新APIの撤回候補であり、実行済み金融操作のundoではない。rootがroutine DDLを直列化し、同時deployがないこととclientのAPI不在→unknown表示を確認してから別途実施判断する。メタデータguardだけで非協調の同時DDLを防げるとは主張しない。


## 撤回runtime専用候補

新 `tool/security/primary_password_self_status_restore.mjs` と専用workflowのPGlite step/nativePG17 jobを追加した。install/restore SQL本文、新2routine本文、既GoTrue proof本文は一切変更していない。runnerは既PGlite fixture内のpinned helper scaffoldをそのまま再利用し、固有の空fixture DBだけで実行する。native接続はloopback/専用DB名/fixture-only資格情報に限定する。

6往復を予定する: 正常install→false読取→restore、STABLE属性改変拒否後の復元、余分なanon ACL拒否後の復元、合成body改変拒否後のexact原本復帰、依存viewによるDROP RESTRICT拒否後の復元、public routine欠落拒否後の原本再作成。5つの拒否ではTX rollback後に拒否直前の状態が不変であることを比較する。合成tamperと修復はfixture内だけで、製品関数の代替実装として採用しない。

各正常往復後は元schema/relations/columns/routine definition・owner・ACL/configと元users/sessions/restrictionsのfingerprintをbeforeとexact比較し、新2routine不在を確認する。Auth raw行は結果に返さず、合成データも内部fingerprintだけを比較する。全catalogのOID採番状態や未列挙属性まで復元したとは主張しない。

この新runnerはNode構文/git diffチェック成功、ローカル依存なしによりSQL runtime未実行。remoteCIをrootが公開して結果を確認する必要がある。既1377のgreen結果を新restore成功へ付け替えない。本番DDLは引き続きrootの別工程のみ。
