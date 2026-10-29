# 登録済み書類の新写真差替え：次工程の契約案

基準mainは`bcf6ab6b77ee07bde6b7ac6a9989d92c595f9bd4`。これは調査・設計のみで、
動く差替え機能、DB installer、クライアントprotocolの実装ではない。初回iPhone用の
PR1611へ混ぜず、既存`new_upload_available=false`と`allowNewPhotos:false`を維持する。
本番DB/Storage/RLS/Auth/GRANT/Edge/flag操作は0。原本の上書き・削除はしない。

## 現ソースで確定した不足

|現ソース|確認した動作|差替えへの不足|
|---|---|---|
|`worker_document_change_session_20261029/install.sql.review-only`|prepareの新pathsは正式rowの旧pathsの部分集合のみ。能力応答はnew upload false。承認時は旧snapshot一致＋apply ticketで正式rowをCAS更新|新objectの予約・bytes真正性・申請への帰属を持たない|
|`worker_document_change_repository.dart`|version1能力のnew uploadがfalseであることを厳密検証|trueを返すだけでは既clientも受理しない。既version1を黙って拡張しない|
|`worker_document_change_flow.dart`|既保存写真だけ編集し、固定commandを送信前に端末保存|新bytesをuploadした後の不明結果・再開の契約がない|
|`worker_document_repository.dart`の`saveManagedDocumentPhotos`|upsert:falseの新object upload後、正式statusへ直接保存|既登録内容の承認前変更になるため差替え経路に流用しない|
|`worker_document_change_review_page.dart`|変更前の何枚目かを表示して承認。新写真の画像プレビューなし|新pathは旧配列index=-1で「0枚目」になる。新画像を見た証拠もない|
|`20261010222524_worker_document_multiple_photos.sql`|正式row/historyが参照する写真をclient UPDATE/DELETEから保護|未申請・審査中objectには、その参照がない段階の保護が必要|
|`20261011033201` / `20261011053526`|5segmentのcompany/worker/requirement/status/fileを照合してupload。managed read追加は正式rowの現在pathに限定|単にuploadした新objectを全reviewerが安全に見られるとは限らない|

上記はrepository sourceの観測であり、現在の全本番policy/capabilityの証明ではない。
正規登録写真・署名・旧履歴を変更した検証は行っていない。凍結sourceのSHA256は
`source-pins.json`に記録する。

## 必要最小のサーバー契約（未実装）

既承認moduleを再利用するが、UIボタン追加だけでは不足する。以下を一体で隔離検証する。

1. **予約**：正式rowの現在snapshot/CASを取り、request UUID、upload UUID、company、worker、
   requirement、status、actor、作成SIDをserver側で固定する。本人/現在people管理権限、在籍、
   有効書類、account、live SIDを毎操作で再検査する。入力のhashは申告値として保持し、真正性とは呼ばない。
   新SIDでの再開は既module同様fresh capability＋明示操作を要し、作成SIDを書き換えない。
2. **新objectだけupload**：既5segment規則内で予約UUIDを含む新しいfilenameをserverが確定する。
   旧pathを選ばせずupsert:false。既Storage INSERT/feature/account条件を通し、予約専用の追加制限も必要。
   新namespace/予約objectに限りINSERTのactor/SID/対象/未使用状態を束縛し、UPDATE/DELETEを禁止する。
   既policy本体の置換・一般read拡張はしない。追加restrictive gateの具体SQLと旧操作への無影響は未実証。
3. **実体確定**：信頼できる限定server経路が実objectを上限付きで読んでbytes SHA256、size、
   許可MIME/画像decodeを検証し、bucket/path/object identityと一緒に固定する。client metadataやETagだけを
   bytes SHA256と見なさない。予約以外のpath、別request/対象からの流用、同UUID別bytesを拒否する。
   利用する信頼server権限・デプロイ先・最小権限poolはまだ確定していない。service keyをclientへ渡さない。
4. **申請**：旧snapshotと、新objectの確定manifest＋順序を一つの固定requestへ保存する。
   同一requestの不明応答はread-only receipt照合で解決し、別UUIDで再upload/再申請しない。
   正式rowには反映せず、旧pathもbytesも保持する。StorageとDBの跨ぎtransactionは仮定しない。
   logout/通信切断後の遅延uploadが孤児objectを作る可能性を認め、未確定objectは承認/正式表示に使わない。
5. **審査用読取**：現在の別actor承認権限とrequest/revision/object manifestに限定して旧/新画像を返す。
   既galleryの一般signedURL発行を無条件で新pending pathへ流用しない。即時権限失効が必要な新画像は
   長寿命signedURLでは満たせないため、live SIDを再検査する認証付き限定streamが必要。読み出し済bytesの
   回収は保証せず、画面/session/lifecycle失効で表示・cache・遅延応答を退役させる。
6. **承認後だけ反映**：本人承認不可を維持し、現在の依頼者/承認者権限、在籍/書類有効性、
   旧正式snapshot、request/revision、object identity/hashを再検査して既apply ticket/CASで一回だけ適用する。
   新写真を含むrowの`original_verified`を旧原本から引き継がない。新内容はsubmitted/未原本確認とし、
   旧確認状態はhistoryに保持する。これには既承認moduleのnext_row/status契約の明示変更と検証が必要。
7. **却下/取消/復旧**：正式rowは不変、旧/新objectとrequest証拠を削除しない。自動GCは追加しない。
   予約/実体/申請/承認履歴が1件でもあれば未使用復旧を拒否し、利用後forward recoveryを別途用意する。

## 実装着手・有効化の前提

- 現在catalogの対象関数/body/attrs、Storage policy全体、bucket設定、関連trigger、historyをprivateに保護し、
  sourceとの差分を確認する。source SHAだけでproduction一致を主張しない。
- 既module＋追加予約/immutable保護＋限定serverを実Storage/PostgreSQL/GoTrueの隔離環境へ組成する。
  mock uploadと合成DBを足して実Storage成功としない。新列/関数/roleの設計、所有者/ACL/公開schemaをレビューする。
- 期限や署名済文書・既登録写真のread/updateが従来どおりであることを検証する。一般RLSを緩めない。
- browser/OSに渡した既signedURLはlogoutだけで回収できるとはしない。既URL期限/既pathは変更せず、
  新pending readでは上記の限定streamとcache禁止・scope退役を実装する。

## 次の限定検証で必須の失敗ケース

- 別会社/別社員/別書類/別正式row/別申請/逆順序、失効SID、退職/権限取消、古いsnapshot、同UUID別bytes。
- upload成功後のACK消失、DB確定前後の切断、logout中の遅延upload、実体が欠けた予約、wrong MIME/oversize。
- 審査中objectのUPDATE/DELETE、既原本pathへのupsert、管理者の直接status更新による承認迂回を拒否。
- reviewerが表示した後のmanifest変更、自己承認、二重承認、submit/approveと権限取消の競合。
- 新写真への差替え後も旧bytes/history/notes/期限を保持し、新rowで旧original_verifiedを継承しない。
- 旧version1/既metadata-only申請/初回写真登録/社員portrait/銀行status同期の回帰とOFF時の無影響。

これらの試験や実装はまだ実行していない。次工程は限定serverとimmutable Storageの実現性を先に示し、
その後にreview可能なDB候補とclient接続を作る。最初のiPhone Releaseを待たせるための擬似完成UIは作らない。

## 参照した公式仕様（2026-10-30）

- https://supabase.com/docs/guides/storage/security/access-control ：uploadにはINSERT、upsertには追加のSELECT/UPDATEが必要。
- https://supabase.com/docs/reference/dart/storage-from-upload ：既存pinned SDKのAPIと実ソースを併読。依存更新なし。
- https://supabase.com/docs/guides/storage/serving/downloads ：private downloadの認証/期限を前提に設計する。
- https://supabase.com/changelog.md を取得。関連のCBC TLS1.2廃止告知
  https://supabase.com/changelog/cbc-tls-ciphers-deprecated を確認。TLS/証明書検証の回避を追加しない。
