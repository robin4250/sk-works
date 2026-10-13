# 所得税PDFのprivate Storage採用（未適用）

metadata registryに続く別migration `20261009155952_company_income_tax_private_pdf_storage.sql`。CLI migration newで生成。本番未適用、実PDF uploadや実Storage API試験をしていない。
既存company_required_documentsの旧PDFを消す差替フローを流用しない。

## Bucketと不変path

新専用bucket `company-income-tax-tables`はprivate、許可MIME application/pdf、最大10MiB（10485760 bytes）。既存同名bucketがあればmigrationを停止し、設定を上書きしない。
既存Storage objects RLSとstorage.allow_any_operation(text[])を必須前提にし、未対応環境へ既存schema helperを勝手に追加しない。
会社UUID/tableUUID/正のmetadata版/64hexSHA256.pdfの厳密path。版が変われば別pathとし、client uploadはupsert=false。
INSERTのみを会社owner/admin・account_access_allowed・現存companiesに限定。pathは下位UUIDとversionの形式も検証し、不正値やbigintoverflowではfalseにする。
PDFの意味内容や実bytesのSHAはこのRLSで検証しない。MIME/サイズ制限はBucket設定をStorageサービスが評価するもので、合成object行fixtureではbytes制限の実行証明にならない。

## 読取・上書き・削除

公式operation-aware helperでobject.get_authenticated/get_authenticated_info/head_authenticated_info/signだけをSELECT許可する。
object.list/list_v2/sign_many、空operationは拒否し、anonに読取/書込を許可しない。INSERTもobject.uploadだけを許可する。
このbucketだけを対象に追加のrestrictive guardを置き、既存の広いpermissive policyのOR経路でもlisting/UPDATE/DELETE/匿名アクセスを認めない。既存他bucketは条件を通過するため既存policyの判定を維持する。
既存policyをDROP/ALTERしない。新schema helperはempty search_path SECURITY DEFINERで必要な会社照合を行い、authenticated EXECUTEだけを付与する。

単体createSignedUrl発行は管理者のobject.signに含める。発行後のURLは短期bearerで、期限内にURLを持つ者が読める仕組みである。発行後のアカウント停止を即時反映するものではない。短いTTLとし、metadataにsignedURLを保存しない。
認証付きdownloadを選ぶこともできる。公開URLやanonymous listingを実装しない。
service_role/DB ownerの既存bypassを変更しておらず、clientの禁止をprivileged操作の禁止とは称しない。

## metadata登録と検証状態

income_tax_private.documentsのINSERT/UPDATE triggerはこの専用bucketの同一storage_pathのstorage.objects行をFOR KEY SHAREで確認し、存在しなければmetadata保存・version更新・履歴を成立させない。
会社rowからobjectrowへの順序で取得する。clientがmetadataを先行登録してPDF保存済みと表示することを防ぐ。
objectrow存在は実bytes、client hashの真正性、正式資料や計算規則の証明ではない。registered metadataは引き続き未検証、common_data_approved=false。
今後trusted verifierが実bytes/hash・正式PDF・年度/期間・解析結果と計算artifactを再検証する必要がある。bucket名やhashらしいファイル名だけで正式/計算済みへ昇格しない。

旧PDFpathにはclient UPDATE/DELETE権限がなく、新年度や訂正版のupload後も旧pathを消さない。upload後metadata登録が失敗したorphanも自動削除せず、成功不明の場合は同じtableID/versionでreadと照合する。cleanup/保存期間を勝手に定めない。
会社削除後の元membershipでは新たなPDF読取/uploadを許可しない。Storage object/bytes自体の保持/privileged cleanupは今後の正式保持仕様と検証対象。

## 実行確認と資料

隔離PGlite 0.3.14上でexact metadata migrationとStorage migrationを実行した。Auth/Storage tables/operation helperは合成で、意図的に広い既存permissive policyを付けて追加restrictive guardの効果を確認した。
private設定、owner/admin upload、他社/worker/anon/account停止、不正path、operation違い、upload重複、object未存在metadata拒否、旧新path保持、認証read/sign、listing拒否、overwrite/delete拒否、他bucket不変、削除会社stale membership拒否を確認した。
operation名のstorage. prefixあり/なしも確認した。実Storage HTTP、実PDFbytes、10MiB/MIME rejection、signedURL expiry、実JWT、全既存RLSとの結合、並列DB/Storage操作は未検証。
CLI local DB/advisorsはDocker/Podmanとlocal DB無しで利用できず、本番へ切り替えて試験していない。

確認した公式資料：
- https://supabase.com/docs/guides/storage/security/access-control
- https://supabase.com/docs/guides/storage/schema/helper-functions
- https://supabase.com/docs/guides/storage/buckets/creating-buckets
- https://github.com/supabase/storage/blob/master/src/http/routes/operations.ts

本番のreadonly catalog確認でstorage.allow_any_operation(expected_operations text[])とstorage.operation()が存在し、SQL/STABLE/SECINV・storage.operation GUC読取とprefix正規化によるexact比較を確認した。sourceのoperationリストも照合した。本番変更はしていない。
