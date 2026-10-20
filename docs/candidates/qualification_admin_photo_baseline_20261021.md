# 資格写真の削除申請：表示済み写真とprepare時の写真を一致させる

基準: main d70b90b9 / ローカル統合候補 075b4004。担当E。新しいproduction migrationではなく、既存の `qualification_admin_saved_photos_20261019.sql.review-only` へ追加する隔離review候補。

## 実機の未反映と停止箇所

- `QualificationCloudPage._delete` は登録済み資格変更の案内を表示するだけで、直接deleteを呼ばない。
- `QualificationCertificatePage` も承認付き変更の準備完了まで編集を停止する。
- `support/admin-saved-photo-client-20261019` には管理能力読取とローカル選択画面が保存されているが、送信・本番導線は未接続。
- 既SQL候補は資格そのものを物理削除せず、保存済み写真の順番・保持する写真を同じ承認queueへ申請する。全写真除外も空の選択として扱う。写真ファイルはStorageに保持する。

## 接続前に見つけた欠落

旧prepareはサーバーで最新の資格rowを読み、その時点の全snapshotをpreviousに保存する。選択pathsが最新保存写真に含まれることは確認するが、UIが表示していた写真集合を受け取らない。そのため、UIが前面写真1枚を表示→別承認で裏面写真を追加→古い画面から「全写真を除外」を送ると、本人が見ていない裏面写真も除外申請に入る。submit/approveの既存snapshot CASはprepare後の変更を守るが、このprepare前の表示差は検出しない。

## 最小補修

別のreview-only patchは、既管理関数のprosrc MD5を完全照合し、既存のoldpaths取得直後に `expected_photo_paths` と正式写真配列のJSON一致を要求する。比較は既存のrequest→advisory→qualification行lock取得後。順序・枚数も一致しなければSQLSTATE 40001でINSERT前に停止する。

- 原SQL候補を変更しない。
- 新関数・表・権限・RLS・認証・uploadを追加しない。
- 元関数のOID/owner/ACL/security-definer/search_pathを維持する。
- 未知の本文・2回目適用は55000で拒否し、transaction全体をrollbackする。
- 既requestの同一actor/target/slots retryは既存の結果を返す。承認後の再送が新しい申請を作ることはない。

## 実行した検証

`node tool/verify_qualification_admin_photo_baseline.mjs /tmp/sko-validation/node_modules/@electric-sql/pglite/dist/index.js`

PGlite 0.3.14の既fixture（base photo / prepared capability delta）の2構成を再利用。旧候補が古い表示基準を受け入れるREDを確認後、patchで以下を確認した。

- 欠落・null・object・空・古い配列・逆順・重複・未知pathを40001で拒否。
- 拒否時に新申請rowが生成されない。
- 一致した基準で写真1枚除外、submit→別actor承認が成功。
- 承認済みrequestのretryはapprovedを返し重複申請しない。
- 写真を全除外しても資格rowとStorage.objectsの保存metadataを保持する。実ファイルbytesはこのfixtureの検査対象外。
- 既存DELETE拒否を維持する。
- 関数metadataと適用時の既存正式rowが不変。
- 既存fixture全体の権限、承認、CAS、互換、履歴検査も引き続き成功。

本検証は合成fixtureであり、native PG同時処理・実JWT・本番RLS・実Storage bytes・iPhone操作の成功を意味しない。

## 未完了・統合条件

1. 管理画面が表示したordered savedPathsを正規prepareの `expected_photo_paths` に送るクライアントを接続する。古いbaselineを最新で自動置換せず、40001時は再表示・再確認する。
2. 既管理能力読取・ローカル選択UIを再利用し、正式申請送信と結果確認へ接続する。旧personal capabilityへfallbackしない。
3. 本SQLpatchと新クライアントが対になるまで本番有効化しない。旧sourceとの競合や未知関数を無視して適用しない。
4. 資格登録そのものの削除は別契約が必要。写真削除と一緒に直接DELETEを有効にしない。
5. 既SQL候補の保守・会社/社員/Auth削除への影響、backup/restore、production helper照合、native検証など既存導入blockerは解消した扱いにしない。
6. 共通ヘルプ・翻訳・workflowはroot統合担当へ依頼。今回の製品画面・機能表示は変更していない。

本番接続・DDL/DML・外部送信・GitHub push・Flutter起動は実行していない。既build6の再作成・再導入は要求しない。
