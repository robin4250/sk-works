## ルート退勤日報→数量申請の導線反映（2026-10-13 02:40 JST）
- [x] #957head8f3全5CI成功後通常merge maina3e630c8c015bb16780bcc5c6d6fa975b59b4d90。tree982c1ed3は最新main955/954＋957対象5filesの期待tree一致。責任者署名保存後に数量申請へ進む、閲覧/印刷/キャンセル維持。
- [ ] 取引会社登録・単価3/3正常だが数量申請0。実機で選択/申請・承認後の生成確認は未完了。旧3訪問は勤務削除archiveの正規履歴を保持し、退勤有無は断定せず無断補完/確定保護変更なし。
- [ ] OpenWeather接続のserver設定に必要APIkeyを非表示登録するMachelper準備中。予報取得成功は未確認。

## 天気取得元はOpenWeather継続（2026-10-13 02:29 JST）
- ユーザー再指定によりWeatherKit切替はせずOpenWeatherで接続復旧を進める。
- [x] 正しいlogcolumn event_messageでv2の11失敗を特定：geocoding_provider_missing。住所→座標のGoogleprovider設定未完で予報API前に停止。
- [ ] 秘密値を出さない欠落設定名の診断v3を専用Node23/CI成功後導入し、既存Googlegeocode/OpenWeather API設定の不足を確認する。取得成功は未確認。

## 週間祝日日付位置の反映（2026-10-13 02:17 JST）
- [x] #954修正後head6b7b0e4全4CI成功、通常merge main3de969481f104fb51aa2adc743cef0beaf717bc1へ反映。treec877f191は#955maintree＋954対象2filesの期待treeと一致、請求読取復旧を保持。
- [ ] #958交通ボタン化/通常出勤tab再取得はFluttergreen・iOS進行中。天気Edgev2診断後ログ0件で、実機の新再取得要求が必要。取得成功は未確認。

## 交通ボタンと天気取得を優先（2026-10-13 01:57 JST）
- [ ] 交通ボタン化は#958の背景/枠/1行文字/側面icon保持修正を最終CIへ。初回失敗は既存footerconst文字列検証のみでcb62499a修正再CI。通常出勤tab再読込も同PR。
- [ ] 天気取得はswitchON/card表示済、backendHTTP422で成功0。秘密を含まない工程enum診断を追加し失敗工程を特定・取得成功まで進める。設定値や予報を捏造しない。

## 経費申請の領収書撮影（2026-10-13 01:54 JST）
- [ ] ユーザー追加：経費申請からカメラで写真撮影し領収書へ添付できるようにする。既存写真選択を保持。撮影キャンセル/権限拒否/保存失敗で入力・既存添付を失わない。経費フロー担当で競合を管理し実装・最新CI・Release実機確認へ。

## 経費承認・振り分けの見本フロー（2026-10-13 01:53 JST）
- [ ] ユーザー添付9C5BE04Eのpopup順を採用：承認/却下→承認時は負担先→精算方法→任意メモ→最終確認→確定。却下は理由メモ→最終確認。途中で書込みせず最後の原子確定と固定command再送で保持。
- 負担先：自社/下請け会社/取引会社/その他。精算：支払済み（対象外）/現金精算/給与精算/立替精算。既存未対応選択は旧cash等へ推測変換せず正規契約拡張を確認。
- 確定後：領収書/カテゴリ/金額/利用日/内容、承認済みor却下済みの色/日時/担当、負担先/精算/メモ（却下理由）、内容修正/履歴/一覧戻る。？ヘルプも更新。
- 精算対象月は申請月、給与生成Mac担当境界/原額計上月との区別/既存確定帳票/履歴を維持。実装・最新CI・本番反映・実機確認は未完了。

## 経費精算の対象月を訂正（2026-10-13 01:31 JST）
- [ ] ユーザー確定：経費精算は申請月。利用月/承認月と推測で置換せず、申請日の日本時間の月を対象月にする。現金精算/給料精算のUI・server契約を照合し修正。既存確定帳票/精算履歴を無断遡及変更しない。
- 請求/支払帳票の経費原額計上月は精算対象月とは別の契約として保持確認。給料精算の給与保存計算はMac担当境界維持。

## 個別給料設定：支給・控除の単位別枠（2026-10-13 01:29 JST）
- [ ] 支給枠内に時間支給/日支給/月支給、控除枠内に時間控除/日控除/月控除を明確な3枠で表示。単価入力と計算例を各枠に表示、UIはWorkの既存#944差分を保持して継続。
- 確定計算仕様：時間支給100円＝働いた時間×100円、日支給1000円＝働いた日数×1000円、月支給10000円＝月に10000円。控除は同じ数量×単価を控除として差し引く。
- 保存/数量/給与計算への接続はMac担当。Work側から既存給与DB/計算を変更しない。未接続UIを本番完成とは扱わず、今回仕様を接続契約として記録。

## ルート請求生成と通常出勤の実機不具合（2026-10-13 01:16 JST）
- [ ] 実機画像：10月請求書0件。12日のルートは出勤表に表示（出12:16退12:18）だが取引会社登録済3現場の請求へ未反映。生成/数量申請/承認/refresh経路を優先調査修正。
- [ ] 13日通常手動出勤・退勤01:13はホーム表示済なのに出勤表13日休み。保存/worker紐付/JST日付/出勤集計へ正式反映を別担当で調査修正。給与計算/認証復旧を変更せず、既存ルートを保持。
- 請求一覧角印直SELECT不備は別PR #955専用CI成功、本番未適用。表示と生成不足を別の原因として扱う。

## 実機の表示・操作不具合を優先（2026-10-13 01:04 JST）
- [ ] 請求書が表示されない：本番保存データと読取/画面条件を優先調査・修正。
- [ ] 交通カードを押せない：表示設定/タップ/外部起動条件を調査修正。
- [ ] 天気カードが出ない：表示設定と本番接続を分けて調査修正。API未接続でも虚偽予報は表示しない。
- 週間祝日日付位置#954は独立CI中、LINE並走は維持。

## 週間出勤表の祝日日付位置（2026-10-13 01:01 JST）
- [ ] ユーザー追加依頼：週間表示の祝日の日付を他の日付と同じ位置に揃える。祝日名全文/赤表示を維持し、独立修正・狭幅文字拡大の配置確認・最新CIへ。LINE/日報一覧の並走継続。

## 経費帳票連携：main/本番反映・iPhone導入準備完了（2026-10-13 JST）
- [x] #951 latesthead205236c8の全11CI成功（Flutter38267956339／iOS38267956507、専用PG/PDF38267956294他）。通常merge後main c2b405e9a8ca7ea133c966122eb5fe75c27d738f、tree9c6d94e1382c44a1645ad2525a82251c1e330889は成功headと完全一致。
- [x] バックアップ後forward migration expense_document_original_costs本番適用成功。既存9表行digest不変、42関数body期待値完全一致、既存33関数owner/securitydefiner/searchpath/ACL保持。消費/振分receipt/明示cost選択/承認backfillは0件。6trigger有効。
- [ ] Macで最新mainを取得し、既存Bundle ID com.skworks.skWorksの署名付きRelease上書き。物理iPhone導入/ログイン保持/帳票操作確認は未実施。
- LINE#952/#953日報改善/LINE第2段階は独立継続し、この導入を完成待ちにしない。main push CIは別実行として確認する。

## 日報一覧の識別改善（2026-10-13 00:41 JST）
- [x] 同日/同現場/同種類の日報が同じ表示になる不足を確認し、独立PR #953 headfa41c9e8/treea8351178へJST作成時刻＋件目番号、日別文言修正を実装。DB変更なし。保存ID別のPDF・ZIP経路の既存保持を確認。
- [ ] #953最新Flutter/iOS CI確認中。経費#951のiPhone導入をこのPR待ちにはしない。
- [x] 経費#951最新head：Flutter全体CI成功、iOS解析/全test/署名なしDebugbuild成功。署名なしReleasebuild進行中。対象9表digest/33関数owner・ACL・検索pathの本番適用前基準を保存、10関数preflightは再照合一致。main/本番未変更。

## LINE第2段階の過去合意を再照合（2026-10-13 00:29 JST）
- 第1段階は公開標準のトークボタン/自動受信/グループ閲覧。トークは常時表示・受信を保つ。
- 第2段階はトーク下の出勤表/請求書ボタンをマスター権限で個別ON/OFF。販売先は追加機能OFF、OFFでも保存データを削除しない。トーク/出勤表は一般閲覧可、請求書は管理者のみ。既存権限境界を確認して接続する。
- 過去履歴→月別/個人別出勤表→確認修正→LINEノート集計照合→確認済み現場別/月別請求書。読取不能項目は要確認。過去履歴は提供された履歴取込を使い、LINE過去本文APIがあると扱わない。
- 自社初期指定の福利厚生15%/税10%/PC鉄骨手当/現場単価は既存会社設定との整合を確認し、全社設定を固定変更しない。給与のMac担当境界は保持。

## LINE第2段階の追加着手指示（2026-10-13 00:27 JST）
- [ ] ユーザー明示指示で第2段階も開始。出勤表/請求書の個別ON/OFF、抽出/修正/集計/再取込を既存実装・確定仕様と照合して独立branchで進める。
- 第1段階#952は保持し最新CI確認を継続。給与処理はMac担当のまま。iPhone導入はLINE着手前の経費等完了時点で実施し、第1/第2段階の完成待ちにしない。

## 経費反映前確認とLINE第1段階（2026-10-13 00:25 JST）
- [x] #951最新head205236c8/tree9c6d94e1の実Flutter生成4PDF/8頁を抽出・金額照合・目視確認。対象9表/33関数定義ACLを限定backup保存、42関数の適用後期待body hashを本物migrationから準備。旧データの原額保持、税/福利費への非加算、旧内訳/承認権限保持の専用CI成功。
- [ ] #951 Flutter/iOS全体CI継続中（iOS解析成功、Test進行）。main統合/本番適用/iPhone導入は未完了。
- [x] LINE第1段階Draft #952 head ae87d8b5/tree1c09641c公開。受信停止returnと本番uniqueキー不一致を修正、保存失敗は503で再送、LINE受信一覧/本文閲覧/既存管理者連携RPC入口・ヘルプを追加。Node9件/PGlite再送復旧/専用CI成功。
- [ ] #952全体CI/レビュー/本番Edge deploy/実LINE連携と投稿確認/iPhone確認は未実施。LINE完了を先行作業のiPhone導入条件にしない。

## 継続方針（2026-10-13 00:14 JST）
- [ ] LINEトーク第1段階（既存受信復旧・閲覧・実投稿保存/表示）を経費PR #951と独立して並走。第2段階は未着手。
- [ ] iPhone Release上書きはLINE着手前の経費等の作業完了時点で実施。LINE第1段階完成を待たず、実機手直しの確認後に次段階へ進める。
- [x] #951 head205236c87fca5ceff4c92a7c0dce9ed17470ed3cへ権限/移行ロック修正を公開。既存承認権限保持/金額振分限定のローカルmigrationテスト成功、専用経費/PDF/実PG17 CI38267956294成功。
- [ ] 最新head Flutter/iOS CI進行中。本番migration未適用、main未マージ、実機未導入。

## 経費の帳票接続を継続（2026-10-12 23:27 JST）
- [ ] 既存Draft #951を継続、head1de1ace739a627a2f892e710ce843f053472b5bc／tree8ff61d9bfa9af6929f7a707dae9062388630d799は隔離checkoutと一致。最新main28154579を親に保持し、天気/交通のmain修正を保持。
- [x] 明示cost snapshotの読取/保存と別途経費行を請求・支払共通PDFへ接続。表紙と明細をID/revision/原額/合計で照合、不一致は印刷前拒否。経費だけの支払帳票は作業行を作らない。承認ページの振分/？ヘルプはserver capabilityに応じて説明。給与の保存計算はMac担当のまま不変更。
- [x] 本番10関数をread-only照合、準備済みfoundation6関数body一致。CLI2.58.5で20261012142138_expense_document_original_costs生成、10関数hash事前条件を付与。本物migrationのPGlite0.3.14実行・金額/内訳/旧command/確定保護検証成功。本番DDL/データ変更なし。
- [ ] 実PG17二接続の振分再送/確定競合と実Flutter生成4PDFの合計/PDF PNG描画をCIへ追加。最新CI/目視確認、保護backup/本番保持照合、main反映/本番適用、iPhone Release確認は未完了。旧head44f0b116のCI成功を最新head成功とは扱わない。

## 天気・交通の見本合わせ：main反映（2026-10-12 23:00 JST）
- [x] #950最終head2db0c901の全4CI成功後、通常マージ。最新main2815457921d87fcf7d5b23638de97ebb9aabd23f／treea7e5762435344cbad2273e0f56f41c3fc1514968はCI成功head/隔離checkoutと一致。
  Flutter38255693241：1596成功/1skip、Release gate1565成功/32skip、解析/APK成功。iOS38255693466：解析/1565成功/32skip、署名なしDebug/Release98.7MB成功。Secret38255693418/Route38255693151成功。
- [x] 天気の参照配置、薄い交通1行とアイコン右ラベル、側面電車/バス停の側面バス、4枠目個人追加・編集解除・利用者会社別端末保存、地域取得エラー重複/async後mounted修正をmain反映。ヘッダー/給与計算/DBは不変更。
- [ ] main push CIはPR成功と区別して確認する。iPhone署名付きRelease導入/実機操作は未実行。物理Mac/iPhoneはこのクラウド環境から操作できない。
- [ ] 経費原額帳票加算はDraft #951最新44f0b116で隔離保存、6SQL/境界CI成功、Flutter/iOS検証中。本番migration/全PDFUI/PG競合未完了。Mac担当給与保存計算接続、天気実予報取得も残る。元worktree・未保存差分保持、専用セキュリティ/Web未開始。

## 継続作業：経費内訳の追加修正（2026-10-12 22:52 JST）
- [x] 前スレッドexpense-cost-connection差分を保持し隔離checkoutで継続。選択999円＋未選択688円が同じ内訳へ混ざる不具合を再現。新monetary snapshotだけID/revision/原額と合計を照合、旧詳細のみ帳票と既存アクセス条件を保持。draft／確定支払証明書／金額不一致拒否と既存の二重加算・税福利費・旧command・確定保護のPGlite0.3.14テスト成功。
- [ ] Draft #951（feat/expense-cost-connection-20261012）、head44f0b11643340b879219820db540e690292ba1e9／tree946e82ec90077ac5ad936d53661253252d28ad1bはローカルff063588と一致。全10filesの独立差分を保存。SQLはsupabase/testsの隔離準備だけで本番migration未作成。金額contract/Expense SQL/Payroll境界/Staged SQL/Route/Secretの6CI成功、Flutter/iOS進行中。実PG17競合・PDF/？ヘルプ接続・本番適用・実機は未完了。
- [x] #950最新2db0c901のFlutter38255693241全成功（通常テスト・Release gate解析/テスト・APK）。Secret/Route成功。iOS38255693466の解析・テスト成功、ビルド中。カード未マージ、Release実機未確認。
- 大きな残件4つ：カードmain反映／経費帳票加算の本番接続／Mac担当給与保存計算接続／天気実APIとiPhone Release確認。既存mainと元worktree/未保存差分を保持。

## 最新の残件・継続結果（2026-10-12 22:31 JST）
- [x] 最新main d36219ccを確認。#929ルート会社別請求数量申請/承認接続、#947保存済み複数日報読取、#948現金/給料精算選択、#949ホーム表示改善は通常マージ済み。本文下部の未完了表記は当時の記録。
- [ ] #950最新head 2db0c9019c13a9c7721c60055e70398846ff8cc2／tree a7e5762435344cbad2273e0f56f41c3fc1514968、隔離checkoutと一致。地域エラー重複・mounted解析2件を修正、参照バス停内を側面の3窓へ。Secret Scan38255693418/Route38255693151成功。Flutter38255693241とiOS38255693466実行中。未マージ・ローカルFlutter/実機未確認。
- [x] 前スレッドexpense-cost-connection既存head5b2709e8の隔離PGliteテストを再実行して成功。原額1234円を一度だけ、税/福利費非加算、下請けへの移動、経費のみ下書き、却下で既存下書き保持、確定済み原額/精算/振分保持、旧commandで遡及加算なしを確認。元worktree/差分保持、本番変更なし。
- [ ] 経費の帳票接続は隔離作業段階。実PostgreSQL競合、表示/PDFと計上額の一致、migration/本番適用は未完了。給与保存/計算接続はMac担当、天気実API取得とiPhone Release導入/確認も残る。専用セキュリティ/Webは未開始。

## 前スレッドから作業再開（2026-10-12 22:24 JST）
- [ ] 「給与UI実装再開」の末尾を引継ぎ。天気・交通の見本合わせPR #950（head df9677e9）を継続、重複PRを作らない。
- 最新CIはSecret Scan／Route visit成功、Flutterは住所取得失敗メッセージ重複のテスト失敗、iOSは交通個人追加のasync後BuildContext解析2件で失敗。ログ確認済み、修正と再CIを進める。
- 元作業ツリー・差分を保持し、このスレッドの隔離checkoutで作業。完成済みヘッダー・認証権限・給与DB/計算は変更しない。給与接続はMac担当、実予報取得・iPhone Release実機確認は未完了。

## 交通カード並走開始（2026-10-12 12:01 JST）
- [ ] ユーザー指定で交通カードを独立担当/worktreeで並走開始。天気担当の共通ホームファイルと同時編集しない。
- 確定仕様：天気カード直下・LINEトーク上、横一列4枠に「最寄駅」「電車乗換」「バス停」、4枠目は将来追加用に空ける。最寄駅/バス停はGoogleマップ、電車乗換はYahoo!乗換案内へ。SKOは入口のみ、位置情報・現在地判定・地図処理は外部サービス側。項目別ON/OFFはマスター管理。親しみやすいアイコンとSKO既存配色を使う。実装/接続/CI/実機を区別して記録する。
- 天気PR #945 Draft最新head `281ef1404725316c6a221b89e49cf62f50343907`のFlutter4失敗を修正中。ローカル接続の一時遮断後、pwd成功で復旧確認。表示修正とfixture修正はローカルcommit済み、公開/再CI待ち。実予報APIは未接続。

## 給与UI検証と天気カード並走（2026-10-12 11:10 JST）
- [x] 統合main `d5733458f21a2be7504b1eb73c2fc840ec4db901`のpush全4CI成功：Flutter38191749267／iOS38191749268／Secret38191749269／Route38191749317。実機Release確認は未実行。
- [x] Workの独立単位別給与UI：PR #944 Draft、head `0f90ef055d77563e378eebd8230bbc0a8d0a4bda`、tree `5e5cbf9e9c9280510b22a6e50b7ae078779ea020`がローカルacc6cc50と一致。支給/控除×時間/日にち/月、単価・日報表示チェック、追加/編集/削除、選択先追加、入力保持、固定フッター、閲覧者/未接続の登録不可を実装。全4CI成功：Flutter38192834551は1530成功/1skip、導入前1499成功/32skip、解析/APK成功。iOS38192834654は1499成功/32skip、解析・署名なしDebug/Release成功。Secret/Route成功。
- [ ] 給与UIの既存画面組み込み・保存/数量/日報/給与接続：Mac担当の契約未接続。Repository/DB/計算/既存給与画面に変更なし。Draft未マージ、アプリ機能完成とは扱わない。
- [ ] 天気カード：ユーザーが並走開始を明示指定。専用weather-card worktree/担当で実装中、未CI。SKO共通の青/背景/文字色、ホームの本日の出勤と要対応の間、要対応と同寸、長押し並べ替えと表示/非表示。会社未登録時は枠＋会社住所設定案内、登録後会社周辺、社員本人住所登録後は出勤前自宅周辺・出勤後登録済み現場周辺。既存住所は読み取りのみ。予報は現在天気/気温/アイコン/降水確率/雨接近、0〜24時3時間9区分。11:07 JST追加：カードの◀︎/▶︎で今日/明日/明後日を切替、選択日と地域の古い応答が新表示を上書きしない。通常予報OpenWeather初期、WeatherKitへの提供元選択はマスターのみ。日本の雨雲レーダーYahoo!、非対応国ボタン非表示、差替可能。API認証/実取得・提供元切替の本番接続は未完了、見本値を本当の予報として表示しない。

## 表示修正の反映結果（2026-10-12）
- [x] #943：head `383579ea775f2e2c8d988dc8ab62e2e750b86d01`の全4CI成功後、main `d5733458f21a2be7504b1eb73c2fc840ec4db901`へ通常マージ。tree `3bf76283b7233bfedc070f9f8b437c61a0459d99`はCI成功head/ローカルと一致。週間祝日名の全文表示、短い画面のスクロール、時刻列の収まり、月間祝日名非表示・文字倍率に応じたセル高、上部/下部の既存A4プレビュー導線、戻り時フッター復帰、？ヘルプを反映。
  Flutter38189735476：1526成功/1skip、導入前1495成功/32skip、解析/APK成功。iOS38189735499：解析・1495成功/32skip・署名なしDebug/Release成功。Secret/Route成功。ローカルFlutter未実行。main push CIは別実行として確認する。
- [x] #942：全4CI成功後マージ済み。既存IDの書類共通選択とiOS ja/en言語宣言を含む。既存の別ID同名書類は自動統合していない。
- [ ] 実機：TOP1〜4列、写真ボタン日本語、週間祝日、カレンダープレビューのRelease確認は未実行。実機プレビュー不表示の原因を解消済みとは扱わない。
- [ ] 給与の時間/日/月項目・日報チェックはUI/保存/数量/単価/給与接続が未完了。保存・計算はMac担当、同ファイル/DBの競合変更なし。#929/経費追加仕様も未完了として保持。専用セキュリティ/Webは未開始。

## 再開後の検証状況（2026-10-12）
- [x] #942：最新head0f942835の全4CI成功後、main `27e92e4ce5d807cf299ff88ba5c780bd658a8b2c`へ通常マージ。tree `95e8c2a0fb249a8f061f0ea169872df5067d92ab`はローカルと一致。必要書類の既存ID選択、ダイアログ終了後のcontroller破棄、iOS ja/en宣言を反映。既存別IDの同名書類は自動統合しない。写真ボタンの実機日本語化は未確認。
- [ ] #943：最新head `383579ea775f2e2c8d988dc8ab62e2e750b86d01`、tree `3bf76283b7233bfedc070f9f8b437c61a0459d99`。旧CIの3失敗（古い色source契約／時刻列・月セルoverflow）を修正。Flutter38189735476は1526成功/1skip、導入前1495成功/32skip、解析/APK成功。Secret/Route成功。iOS38189735499は解析/テスト成功、ビルド中。ローカルFlutter未実行、未マージ。実機プレビュー不表示の原因は未確定。
- [ ] 給与単位別UIと日報チェック：保存/数量/単価/給与接続はMac担当、未接続。専用作業ツリーは保持、アプリ機能の完了とは扱わない。実機Release導入・確認は未実行。

## TOPボタン復旧と追加修正の現在地（2026-10-12 09:16 JST）
- [x] TOPボタンの縮み：PR #941 head90a9524d8071bd9c59c07f914cb7b505ac950137の全4CI成功後、main `30149d465ebf0c7fb908a45bd87bc3ce757cb385`へ通常マージ。tree `24210d6e9e512563969d1ab205bd0efe0719a467`がCI成功headと一致。StackFit.passthroughでグリッド寸法を保持。1〜4列/4権限の寸法・持ち手位置を検証。ヘッダー不変更、実機は未確認。MacのRelease上書きコマンドを提示。
- [ ] 必要書類の既存一覧からの共通選択・撮影日本語：PR #942最新 `0f9428358c8e9a360fa923d0ae93ef44b4f33f1d`、tree95e8c2a0fb249a8f061f0ea169872df5067d92ab。既存ID/必須/期限を保持、同名新規入力を案内。既存の別ID同名書類を自動統合/削除しない。ネイティブiOSにja/enを宣言・既存他言語を保持。旧CIのsuper parameter解析指摘とTextEditingController早期disposeをログに沿って修正。最新main30149dのTOP復旧を取り込み再CI、ローカルtree一致。未マージ/実機未確認。
- [ ] 出勤表の祝日・プレビュー：PR #943最新 `0d6468d1668083721a475256cfbdfff700e99d32`、tree7eed0e0f2a4619d50d35e47d52e8eee45c22b12b。週間は日付/曜日を11px同一行、祝日名を12px/幅110へ。小さい画面/文字拡大時は行高確保して縦スクロール、手当は横に確認。月間祝日名を撤去して赤い日付を保持。右上から既存プレビューへ遷移/戻り時フッター復帰。PDF/帳票レイアウトは変更なし。白画面等の実機原因は未確定。最新mainのTOP復旧を保持して再CI、ローカルtree一致。未マージ/実機未確認。
- [ ] 個別給与の時間/日/月・日報表示：保存/数量/単価/給与契約はMac担当を維持。直接金額へ単位を推測保存せず、Workの未接続UIを完成扱いしない。#929/経費追加仕様の差分は保持し、今回の実機表示復旧を優先。専用セキュリティ/Webは未開始。

## 個別給与UIのCI・main反映（2026-10-12 08:14 JST）
PR #940最新head `dc064971d625e1f241257834412206e326fc6a47`の全4CI成功後、通常マージ。最新main `15c80dd05165dd68231fce00d1e35424a34ff022`、tree `dc9635f6310415f3e42cc08cf3e3f279494b9419`はCI成功headのtreeと完全一致。Flutter38182142366：1516成功/1skip、導入前ゲート1485成功/32skip、Analyze/APK成功。iOS38182142363：Analyze・1485成功/32skip・署名なしDebug/Release成功。Secret/Route成功。旧headの静的テスト2件と英語リソース1件の失敗を修正。3widgetテストの入力保持/選択先追加/両タブ保存/既存金額/320px文字1.3倍/閲覧者/月給詳細保持も最新headで成功。
今回のUI表示範囲だけを完了。保存/_serializeCustomMoneyは変更前と完全同一、Repository/DB/給与計算/日報/帳票不変更。時間/日/月自由追加・日報チェックの保存/数量/給与接続は未実装でMac担当を維持。iPhone Release導入・実機確認も未実行。main push Flutter38183483623/iOS38183483527/Secret38183483635/Route38183483585は開始直後で結果未確認。PR成功とmain push進行を区別。
既存worktree/差分を保持、ローカル2b43b99cのtreeは統合mainと一致。Macの担当稼働/analysis_options.yaml差分はこの環境から確認できない。導入はその差分を対象指定stashで保持してmainをff-only取得し、既存device_day.shによるsource backup/署名付きRelease/Bundle ID com.skworks.skWorks/上書きと起動を実施する。物理端末操作はユーザーのMacで必要。

## スレッド移動の引継ぎ（2026-10-12 07:46 JST）
個別給与UIの専用PR #940（Draft、未マージ）、最新head `32649c409f17644476d0b2d5cda76ec5e6badb05`、tree `09697767b73883fd33a23ca3bcb86c98294f704e`。作業ツリー `/workspace/scratch/7ba5ee58a182/individual-payroll-ui`、branch `ui/individual-payroll-tabs-20261012`。ローカルstage/treeとGitHub treeの一致確認済み。社員→給与形態→単価→支給/控除、青い選択タブ、個別給与のみ詳細折りたたみ、ヘッダー右側更新日、追加/登録固定フッターを実装。保存/serializationは元と同一、Repository/DB/給与計算/日報/帳票は未変更。タブ切替の生入力保持/追加先/両タブ保存/既存単価・社会保険・住民税保持、320px/文字1.3倍、閲覧者編集不可、月給詳細保持の3widgetテストを追加。ローカルFlutter未実行。最新Flutter38181684998・iOS38181685096は実行中、Secret/Route成功。結果取得→失敗修正→最新head再CIを優先。時間/日/月自由追加・日報表示チェックは保存/数量/給与接続が未実装で、全面整理の完了とは扱わない。給与計算は引き続きMac担当。
直前のGitHub保存呼出しはユーザー割込みで中断と表示されたが、再取得でPR #940作成・branch更新がサーバーで完了済みと確認。重複PR作成なし。
最新main63fbcfbcのFlutter38180407179成功、iOS38180407075実行中、Secret/Route成功。iPhone導入は未実行。既存の完了/本番反映/履歴と残件は以下を保持。

## 個別給与設定UIの追加作業（2026-10-12 07:37 JST）
- [x] Work側UI専用：社員→日給/時給/月給タブ→単価→支給/控除タブの順に整理。選択中を青表示、残業等の計算式は詳細設定へ折りたたみ、追加/登録を固定フッター、最終更新日をヘッダー右側に表示。直感で触れる見た目を優先。
- [ ] 時間/日/月の自由追加、日報表示チェックと実際の日報利用：現行custom項目は直接金額のみ。数量・単価・日報チェックの保存/計算契約が未接続のため、給与担当Mac側との接続対象として区別。既存社会保険/住民税/保存済み単価と未保存差分を保持し、WorkのUI変更で給与計算・DB・日報数量接続を変更しない。
最新main63fbcfbcからUI専用worktreeで着手。Open PRに同画面の実装変更はなし。Macローカル差分はクラウドから確認できず、UIファイルに限定して差分を公開する。実装/CI/main反映/実機はまだ未完了。

## 最新統合・本番反映（2026-10-12 07:26 JST）
最新main `63fbcfbcd1da0f8db9837aa76fcbc8f62e6c2203`、tree `acf0743d68eb85d2071ae3576b9c5a270a4c3707`。統合treeはPR #939全7CI成功headと完全一致。main pushはSecret/Route成功、Flutter38180407179・iOS38180407075実行中。
- [x] GPS＋写真ルート出勤：PR #933最新5d65065fの全4CI成功、main8da18b16へ通常マージ。保留の数値15桁再表現だけ許容、ID/写真等の厳密照合を保持。実機は未確認。
- [x] TOP上下スクロール：PR #935最新8a6eda6bの全4CI成功、main907d2363へ通常マージ。持ち手以外で縦スクロール、0.9秒停止スクロールと持ち手操作を検証。実機は未確認。
- [x] 必要書類の自社・取引会社共用：PR #936最新b0d45d8b全7CI成功、最新main70a7635dへ通常マージ。本番ledger20261011213143 worker_document_shared_scope適用・照合。送信関数hash1cdade431386654aaf123955b5fc49b2が隔離検証と一致、scope置換3箇所のみ。書類30/提出2/社員8/プロフィール6/家族0/会社3の全行hashとaccount guard hash不変。既存項目・添付の自動統合/削除なし。実機未確認。
- [x] 振り分けUI：PR #934全4CI成功、mainへ通常マージ済み。現金/給料精算・別途金額追加は未実装。
- [x] 社員個別の表・顔写真・家族扶養：PR #937最新2e6b8adc全7CI成功、main db2280f4へ通常マージ。本番ledger20261011214941 employee_personnel_read_view適用。5関数のbody hashが隔離検証と一致、anon不可/authenticated可、既存6表の全行hash・4保護関数hash不変、新規advisoryなし。社員一般/他社/停止/匿名拒否、閲覧者編集不可を隔離検証。実機は未確認。
- [x] 取引会社/協力会社の住所・電話・備考電話リンク/代表者二項目：最新head116ff34e全7CI成功、main0ae7a910へ通常マージ。最初のGitHub405 merge conflicts拒否は、同じtree66dc732cを保持して最新mainを親に取り込み解消。SQLは手順確認ミスでマージ前に先行適用したが、本番ledger20261011215416を照合、既存6表hash（会社は新2項目を除く）・4保護関数hash不変、新9関数hash一致、権限と新規advisoryなしを確認。既存3社の代表者二項目は空文字。実機未確認。
- [x] 会社データの書類写真・削除・プレビュー：PR #939最新cfd962bc全7CI成功、main63fbcfbcへ通常マージ。写真ごとの文字付きプレビュー/削除、書類全体の確認付き一覧削除、狭い画面で操作折り返し、保存前写真も拡大、？ヘルプ更新。320px/文字1.3倍の操作と最後の写真削除HTTPを検証。元ファイル/送信済み履歴を保持する既存処理を再利用し、Storage DELETE・新DB処理なし。統合mainのtreeが全CI成功headと一致、実機未確認。
- [ ] iPhone Release上書きと実機確認：未導入。Mac未保存analysis_options.yamlを対象指定stashで保持し、最新mainをff-only取得してdevice_dayを実行する手順を準備。現行scriptの署名付きRelease・Bundle ID com.skworks.skWorks・devicectl上書き導入/起動、shell構文を確認。クラウドからMac/iPhone操作は実行していない。main pushCIを確認中。
既存main・ブランチ・作業ツリーを保持。#929は未完成Draftのまま。既存PR #929の最新head c77e0257に最新main70a7635dと再送修正を保存。申請1人工を0.5人工で承認後に元の1人工を再送すると承認待ちへ戻る問題を隔離テストで再現・修正。申請数量と承認数量を分離し、版/現場/単価/履歴を保持。PGlite成功、最新実PostgreSQL17二接続CI38177109521成功。最新head全7CI成功（Flutter/iOS/実PG17を含む）。請求接続、通常退勤申請、改訂後の古い送信識別、本番導入は未実装。給与処理・給与接続はMac担当を維持。未検証の実機成功を完了扱いしない。

## 経費の追加依頼（2026-10-12 05:09 JST）
- [ ] 経費の承認時に管理者・サブ管理者が「現金／給料精算」を選択。給料精算は申請者の支給へ追加（給与処理はMac担当を維持し、連携契約を確認）。
- [ ] 承認後に自社・取引会社・下請け会社へ振り分け。外部会社分は請求書／支払証明書へ経費として別途追加し、福利厚生費・消費税を加算しない。確定済み帳票は保持。
- [ ] 振り分けページ全体を整理。承認状態・精算方法・費用負担先・帳票への反映先を分かりやすく表示し、リンクと？ヘルプを確認。
既存の経費4一覧・帳票実装を再作成せず、今回の追加仕様との差分を対象とする。現状確認中、実装・CI・本番反映の完了とは扱わない。

## 現在のWork作業リスト（2026-10-12 03:12 JST）
- [x] PR #932：フッター整理・現場管理への改名、出勤説明1行、要対応1.25倍/通知3行、TOPスクロール、履歴化済みルート出勤復旧。最新head80cbc531の全9CI成功・main b83a3d1fへ通常マージ。
- [x] #932の新しい読取RPCを本番反映・照合。ledger 20261011181136 archived_attendance_capture_recovery。検証済み2関数body hash一致・authenticated許可/anon拒否、既存archive12件/全行hashとaccount guard hash不変。
- [ ] 最新mainのiPhone Release上書きと実機操作確認。
- [ ] PR #929：取引会社別の承認数量/単価を請求へ接続し、未承認時の確定防止と通常退勤後の申請を完成。
- [ ] LINEトーク第1段階：既存受信の復旧、受信トーク閲覧、実投稿の保存/表示確認。
- [ ] LINEトーク第2段階：出勤表/請求書の個別ON/OFF、抽出/修正/集計/再取込連携。
- [ ] 本番DB/Storageバックアップの保存先・取得日時・復元確認。

ユーザー指示で経費4一覧/振り分け/帳票連携と給与/手当/日報数量の給与連携をこの作業リストから削除。給与のMac担当という境界は維持。以下の過去仕様・完了記録・履歴は保持し、古い未チェックを現在の進行状態として扱わない。

---

## 最新main：今回のソース統合完了（2026-10-10 JST）
- 最新main `0d5204621512c3c8ea0da0bc4b07d9bee2bebf89`。#864 atomic通知修正（全6CI）、#865会社設定→管理者共通手当UI（全7CI）、#867有休PG17取得元修正（全3CI）、#866添付/通知sink/給与確定の限定統合検証（全7CI）を、それぞれ最新exact-head成功とレビュー後に通常merge。
- #866 head `8c73dfe2f8e01184eff19b41f23c4f4ccb3b58aa` の実PG17/PGlite、実二接続、Flutter test/analyze/gate/APK成功。将来default設定変更は許容し、確定時の条件・5表を保持。sink失敗8表rollback。4登録trigger/17選択FKの限定範囲であり、全入口/24trigger/134FKの完了ではない。
- #865統合main `649291a1df168e9b041221ae6233ef86e8015519` のpush全7CI（Flutter/iOS含む）成功も確認。最新mainの新規push CIは別途進行として扱う。
- 統合後も#852給与PDFの保護済みblob `c3167613057487c67ccacb408fef8eaae01b5822`、設定画面blob `ea7b8574c2eb3015069335c0f59cc8c071d778d0`、依存lock `3da84530377bf4a167526d33d4d9f6a744f5777f`、有休公式ECR画像修正を保持確認。#861は同一中核を#865で採用し履歴保持でsuperseded close。
- 未完了：本番migration適用/実JWT、日報数量→給与接続と適用期間、全入口/FK、実機確認。既存設定・正常動作・過去給与を保持して継続。専用セキュリティ追加/Webは開始していない。本番DDL/DMLは実施していない。

---

## CI取得元修正と通知／確定の実同時操作（2026-10-10 JST）
- 最新main `14c5a3aee8a6a57bb576a5d09c823f0a7565b9cb`。#867 exact `fa6e142f171852f8d61d8bc7cad23f3a15468b1d` 全3CI成功後に統合。有休workflowの公式ECR image/commentだけ変更、実PG17.11既存preflight・Flutter test/analyze/gate/APK成功。原典SQL/app/本番不変更。
- #866 exact `8c73dfe2f8e01184eff19b41f23c4f4ccb3b58aa` は実PG17/PGlite・住民税・有休・Secret・union・snapshotの6workflow成功、Flutter最終APK待ち。4登録trigger/17選択FKの添付境界・親cascadeを限定検証。全24trigger/134FKや本番全体の完成とは扱わない。
- 実二接続で通知sink/給与確定の両順序を確認。settings先行→古いrevision確定拒否。確定先行→将来default設定320000への更新を許容し、保存条件310000とPS/reviews/audit/doc/history5表を保持。通知保存失敗は8表rollback。実first backendのblockingPid照合あり。誤った『確定後WPS全拒否』期待と分離会社の確認者未登録をfixtureだけ修正、製品DDLの拒否条件は追加していない。
- #864/#865は統合済み。手当統合main649291のFlutter push成功、iOS push継続。各PR exact-head成功とmain pushの進行を区別する。本番migration/実JWT/数量給与接続/実機は未完了。専用セキュリティ/Web未着手。

---

## 再開後の統合結果（2026-10-10 JST）
- 最新main `649291a1df168e9b041221ae6233ef86e8015519`。#859（会社料率・所得税閲覧・初期手入力・保存結果確認）、#862（回数条件の独立モデル）、#863（native PG17 CI取得元修正）は統合済み。
- #864 exact `efa2fe8fd6e432c687f9d5db98317ea590d222ee` 全6CI成功＋独立レビュー後、main `002049b68c0d81f4c672e74586a488b92eff7466`へ統合。通知は初回1・再開1・active再操作0、実PG17二接続と通知失敗時rollbackを検証。既存関数契約・宛先権限を保持。
- #865 exact `b88f404c5b5059500445eab790c99bbd50c95225` 全7CI成功（Flutter/iOS/実PG17含む）後、最新mainへ統合。会社設定のowner/admin入口から選択会社の共通手当へ接続。#861中核8files同一blob確認、#861は履歴保持でsuperseded close。既存VAT・閲覧者料率経路を保持。
- #866旧headのresident/PaidLeave失敗はDockerHub匿名pull制限でSQL前停止。専用実PG17probeは成功。最新mainの取得元修正を保持するrestackと、PaidLeave専有1file修正、通知sink/給与確定の二接続検証を並走中。失敗CIや分離検証を製品完成とは扱わない。
- 本番DB migration未適用、実JWT・実機・日報数量/給与連携・全入口/FKの確認は未完了。専用セキュリティ追加/Webは未着手。過去給与と既存設定保持方針を継続。

---

## CI取得元修正の着手（2026-10-10 JST）
main `f43bbbc696137d27752e5e5548fe6f9df00cc1f8` のnative PostgreSQL4 workflowは、attempt2もDocker Hub匿名pull取得制限によりSQL実行前に失敗。公式Docker publisherのECR public配信へservice imageだけ切替する独立PRを開始。実PG17・全harness・2接続の最新head成功を再確認するまでmain CI成功とは扱わない。#861専有lifecycle workflowも同じ1行修正でhead `4bd0c1b6ab6f88efbee7e5a0bd45c5b5d7edd6ce` に再CI。既存app/SQL原典/本番DBは保持。

---

## 最新main：給与明細source統合（2026-10-10 JST）
- #858 exact `9a5ece4e421d3c0c884d408eed83df578ba5059c` の全13CI成功・独立reviewを確認し、main `f43bbbc696137d27752e5e5548fe6f9df00cc1f8` へ通常merge。住民税・保存snapshot・通常更新scope・個別確定UI・再取得中/失敗時PDF停止の累積sourceを統合。
- 実merge後に#854設定blob `85c13630`、#852 PDF blob `c3167613`、#860手当identitymigration保持を確認。古いbranch treeでmainを置換していない。
- #860統合後main ea9d80dの全6push CIも成功済み。新main f43bbbcのpush CIは継続確認。
- #859最新977ca500は最新Test/解析修正後gate成功、APK/iOS継続。#861最新efcfad2はUI lifecycle guard修正済み、再CI継続。#862最新510a80dはFlutter全体/Secret成功、iOS継続。
- 実通知sink結合で初回generation-setting通知欠落を再現。別新migration/source修正と初回/再開/rollback/実PG17競合検証を開始、他のDB source担当と分離。
- 本番DB未適用・実JWT/Storage bytes・全入口/FK・物理iPhone Release未検証。source統合を製品完成と扱わず、管理画面導線と数量/料率/給与接続を継続する。専用セキュリティ追加/Web未開始。

---

## 管理画面・回数basisの継続（2026-10-10 JST）
- #861 共通手当管理UI/API・履歴100件cursor・送信前file journalを公開。会社切替/ABA/旧ダイアログ入力を世代とsource identityで拒否し、全3枠の保存値応答照合とcursor版順序検証を追加。0e8f00cまで独立レビュー重大blocker解消、最新CI継続。設定画面の導線は料率source統合後に一担当で接続する。
- #862 head `510a80d8061cb574fa37d202aafb1dbd6c3edf2e` は新3filesのみのcount純粋domainと6境界tests。独立レビュー重大欠落無し、Secret成功、Flutter/iOS進行中。回数を出勤日数へ偽装せず固定精度・明示丸め・旧金額保持。DB/日報/給与にはまだ未接続。
- #859最新 `f9b7e20b0c525befa9e8ced8f9ff41fcacef17a7` は隣接entry fixture引数追従漏れを修正、製品sourceは独立レビュー済み19edと同一。新head再CI中。
- #860実merge後のmain `ea9d80d` を再照合し、settings_pageの#854修正とpayroll_pdf_serviceの#852修正はblob/contentとも統合前と完全同一で保持。

---

## 次の実装境界・CI更新（2026-10-10 JST）
- #858最新9a5ece4のiOS Test成功、Debug/Release build確認中。
- #859最新ca2745dのFlutter CI failureを確認し、ログに基づく修正と新head再CIを担当が継続。旧head成功を代用しない。
- 会社共通手当の管理UI/APIに加え、数量の純粋count basisを非競合レーンで実装へ。既存hours/attendanceDays/monthlyFixed/directAmountへ「回数」を偽装しない。
- 日報worker保存はdelete→reinsertを行うため、将来quantityの省略保持/明示[]解除を同transactionで接続する。別RPCの後付けだけでは旧client再保存で失われる。適用期間resolver・同日複数現場合算・旧個別手当二重加算は次の接続条件、過去単価を推測適用しない。
- 給与確定DBの全入口点検で、meter/group/evidence/journey、一括raw更新、親FK/cascade等は残検証。本番DDLは適用せず、source/main統合と全入口の本番採用保証を分けて継続する。

---

## 最新main統合（2026-10-10 JST）
#860 最新60c754bの対象6CI全成功・独立再レビューを確認し、sourceをmain `ea9d80d96e16314906cc87e3ad1e16bc089a98e7` に通常merge済み。#854の既存修正を保持。本番DB未適用、管理UI/数量/給与/実機は継続中。#858/#859は最新Flutter/iOSの残結果を確認中。

---

<!-- SKO_CONTINUE_858_859_860_SOURCE_REVIEW -->
## 継続進捗（2026-10-10 JST）
- 最新main: `c409e0c753af1b2b09c3b11e225ccabc219833fd`。#854統合済みの消費税率一本化を保持。
- #858 head `9a5ece4e421d3c0c884d408eed83df578ba5059c`: 給与明細の再取得中・失敗時のPDF/共有/印刷停止、保存済み明細の取得分離。独立レビュー重大欠落無し。Flutterを含む12 CI成功、iOS最終結果確認中。
- #859 head `ca2745d9b53f96324a58283fa0982f331ee03d11`: 料率変更の送信前記録、会社/利用者別復元、厳密照合後の解除。製品コードは独立レビュー済み19ed9dbと同一、最新差分はテストfixture修正。SQL/PG17/Secret等10 CI成功、Flutter/iOS確認中。通常のアプリ再起動で復元する設計であり、突然の電源断までの絶対耐久保証ではない。
- #860 head `60c754b7ea506b6099083cf1ab49e43c5c3d921a`: 手当枠の改名は同ID、廃止後再使用は新ID。履歴actor/時刻・company→settingsロック順を修正。実PG17/PGlite/Flutter等、対象6 CIすべて成功。最新差分の独立再レビューと管理UI・ページ単位の履歴読取を並走。
- CI・レビュー完了範囲から通常のPRマージでsourceをmainへ統合する準備を進める。既存main全体を古いブランチのtreeで置き換えない。
- この記録時点で本番DB反映・実JWT/HTTP/PDF原本検証・iPhone Release実機確認は未完了。過去給与と既存会社設定を変更していない。専用セキュリティ追加・Web版は未開始。

---

<!-- SKO_CI_COMPLETE_855_856_857 -->
### 最新headの最終CI確認（2026-10-10）

- #855 `eabce192c4318c1d098ff76b778912d854c42f34` 全12CI成功。
- #856 `85fb9210b1beb7b0dbd84a1ee8537d74d361d0a5` 全12CI成功。指定初期料率の新規編集・既存0保持・明示折半・キャンセル書込0の確認を含む。
- #857 `139b3da30fab1cfd185d2b808ff0cec9d4abd419` 全13CI成功。実SQL finalize応答→Dart consumer、結果不明時の保存source/版/capability再照合、旧draft PDF停止、閲覧不可時の操作禁止、送信直前再検証の修正を含む。既報欠落は独立レビューで解消確認。

上記はFlutter・iOS Analyze/Test/Debug/Release・関連SQL/PGlite/実PostgreSQL17・Secret/contractの最新head検証結果。前head成功やcancelled runを代用していない。mainは `c409e0c753af1b2b09c3b11e225ccabc219833fd`（#854統合済み）のまま。

3PRはDraft・本番未適用・実機未検証。全入口/一括確定、公式自動取得/資料正式検証/実給与連携などの残件があり、製品完成とは扱わない。本番DB・既存設定・過去給与・iPhoneを変更していない。専用セキュリティ追加とWebも開始していない。以下の既存仕様・履歴は全保持。

---

<!-- SKO_PROGRESS_FINALIZATION_139b3da -->
### 最新継続結果（2026-10-10）

- mainは `c409e0c753af1b2b09c3b11e225ccabc219833fd`。#854統合済み、既存PDF数値メタデータ除外修正・ローカル税率編集を保持。
- #855 exact `eabce192c4318c1d098ff76b778912d854c42f34` 全12CI成功（Flutter/iOS Debug・Release/SQL/PG17/Secret）。独立レビュー成功。本番・実HTTP/JWT/bytes・実機と実給与連携は未完了、Draft保持。
- #856 exact `85fb9210b1beb7b0dbd84a1ee8537d74d361d0a5` Flutter/SQL成功。iOS Analyze/Test成功、Debug/Releaseビルド継続。指定初期値・既存0保持・明示折半・キャンセル書込0を保持。
- #853 exact `e02fc385b47bf949d37b2ac1d0f63e2f9b77c9df` 全13CI成功、通常API限定のレビュー成功。Draft・本番未導入。
- #857 個別給与確定UIを接続。最新 `139b3da30fab1cfd185d2b808ff0cec9d4abd419` のSQL/PG17/contract/Secret全11CI、Flutter Testと実機更新前gateが成功。Android APK/iOSは継続。
- #857は実SQL応答→Dart parser検証、保存済snapshotの名称/金額表示、応答不明時の再送禁止と再照会、保存明細未取得時の旧PDF停止、閲覧不可時のcached capability無効化を追加。独立レビューの既報欠落解消。前head1040tests成功・analyzer3箇所失敗は最新で修正し、iOS Analyze成功も確認。

本番DDL/DML・既存設定/過去給与・実機を変更していない。専用セキュリティ追加とWebは開始しない。Draft/分離検証を製品完成と扱わない。以下の既存仕様・進捗・履歴はすべて保持。

---

<!-- SKO_CONTINUE_20261010_0418 -->
### 継続状況（2026-10-10 04:18 JST）

- [x] #854 消費税率入力の一本化と一般設定の旧値書戻し除去は全CI成功・差分再レビュー後、main `c409e0c753af1b2b09c3b11e225ccabc219833fd` へ統合。ローカル編集は保持。
- [x] #855 最新 `eabce192c4318c1d098ff76b778912d854c42f34` は最新main修正を保持して競合解消。料率/所得税metadata/単体PDFの閲覧者境界のSQL・PG17と読取レビュー成功。Flutter/iOSの最終CIは継続、Draft・本番未適用。
- [x] #856 最新 `85fb9210b1beb7b0dbd84a1ee8537d74d361d0a5` に指定初期料率を未設定の手動編集だけへ追加。既存0保持・キャンセル書込0・支援金標準折半の明示選択を含む追加7widget。初回構文エラーを修正し、最新Flutter Test step成功（run37978447247）。Release gate・iOSは継続。既存設定/給与を自動上書きせず、適用月/情報元/確認後保存を維持。
- [x] 支援金はこども家庭庁の被用者保険・2026年度0.23%/基本折半を公式照合。新規編集で標準折半値を明示選択すると本人0.115%/会社0.115%を入力。標準を一律採用した給与計算の完了ではない。
- [x] #853 latest `e02fc385b47bf949d37b2ac1d0f63e2f9b77c9df` 全13CI成功。通常API限定の読取レビューで重大欠落なし。全入口/任意bulk/本番JWT/FKの保証ではないためDraft維持。
- [ ] 給与確定UIの独立レーンを開始。単一明細、明示readonly capabilityと正確なrevision、DBの給与設定編集権限、再計算変更時の再確認、保存snapshot表示を接続。旧DBはmissing RPCだけ未導入扱い。既存『確認登録』は確定と混同せず保持。
- [x] 本番をread-only再照合。ledger最新は `20261009114722 license_document_upload_pilot_contract`、料率/所得税/確定snapshotの3schemaは未導入。新DDL/DML・既存設定・過去給与を変更していない。今回のiPhone更新も未実施。

セキュリティ追加とWebは開始しない。以下は過去履歴としてすべて保持。

---

<!-- SKO_PROGRESS_20261010_0145 -->
### 継続状況（2026-10-10 01:45 JST）

- [x] #847：給与レビューを「確認登録」と表示し、実給与確定と混同しない文言へ修正。最新headのFlutter・iOS Debug/Release・seal・Secret Scan成功後mainへ統合。main 0fafbc36bef0194303ebdb3af78967e180af6d5e、統合treeは独立予測と一致。給与確定snapshot自体の完了とは扱わない。
- [x] #844：最新head271e6b54のFlutter・iOS Debug/Release・SQL registry・snapshot・PG17・Secret Scanすべて成功。
- [ ] #844は公式候補取得/検証登録・実給与接続と正式導入が未完了のためDraftを維持。
- [ ] #846：PDF登録応答不明後の再確認成功時に古い警告表示が残る問題を修正。テスト待ち時間を延ばさず成功表示へ置換し、解析指摘も除去。head a33d6186でCI再実行中。
- [ ] #848：住民税開始月の実給与結合は独立SQL・SQL CI成功。個別給与の専用保存UIへ接続中。一般給与保存で住民税timelineの選択額を旧固定欄にコピーしない。
- [ ] 次のDBレーンは、確定時に調整込み結果・採用条件・文書情報を原子的snapshot保存し、以後の本人/管理取得・PDFを保存値から表示する実装。家族人数条件/単価/旧支給移行は管理者による明示設定が必要な設計として整理し、未設定を推測で給与採用しない。

本番DBは変更していない。スリムな主操作と、既存給与・過去明細保持を優先して継続。

---

<!-- SKO_FINAL_PAYSLIP_GAP_20261010_0143 -->
### 確定給与明細の保持で追加確認した実装課題

- [ ] 確定時に使用料率・計算条件・結果だけでなく、調整額と明細表示用情報もsnapshot化し、再表示・PDF再生成で同じsnapshotを参照する。
- [ ] 現行の本人明細RPC my_payroll_statement_rows_with_adjustments と給与確認workspaceは、workflow_stateを問わず有効なpayroll_adjustmentsを合算する。基礎明細のfinalized行を保持するだけでは、後の調整登録・取消で表示額が変わり得る。
- [ ] private.payroll_document_metadataは現在の会社・従業員・給与設定・確認者情報を返し、表示detailへ合成する。現行PDFは保存済みbytesでなく現在RPC情報から再生成するため、確定後の情報変更から過去明細を守る参照切替が必要。

調査のみ。本番データ・既存権限は変更していない。既存「確認登録」と実際の給与確定を区別したうえで、確定とsnapshot保存を一つの操作で行う設計を継続する。

---

<!-- SKO_PROGRESS_20261010_0137 -->
### 継続状況（2026-10-10 01:37 JST）

- [x] #845：介護保険の40〜64歳対象月の境界判定と、家族・住民税・所得税保存の結合契約をmainへ統合。最新mainは28325e3d196c164dc02dc220a2b269076906bf1d。Flutter・iOS Debug/Release・Secret Scan成功。生年月日から実給与への接続は継続。
- [x] 住民税の開始月設定を実給与計算・明細詳細・控除正規化へ直接接続したsourceを独立SQL検証。旧12000円、新15000円、0円、開始前保持、将来予定だけの変更による現在明細全field保持、手入力／確定明細保持、履歴・給与audit失敗rollbackを確認。
- [ ] #848：上記住民税sourceを最新main基準のDraftとして公開。CI・スリムな個別給与UI接続・本番導入は未完了。本番DBは未変更。
- [ ] #844：会社共通税率設定の現在値／確認値比較、単項目確認適用、会社条件、履歴を実装。最新headのFlutterおよびSQL検証成功、iOS継続。公式情報自動取得・検証候補登録・給与連携は未完了。初期料率は推測していない。
- [ ] #846：所得税の年度別PDF・適用期間・専用private Storage登録sourceを公開。SQL/Storage検証成功。画面の登録応答不明後の再確認テストと静的解析を修正中。資料検証・税額計算・共通化承認は未完了。
- [ ] #847：「確認登録」と給与確定を区別する表示修正。Flutter・seal・Secret Scan成功、iOS継続。実際の確定snapshot実装は別途継続。

仕様全体の完了とは扱わず、既存の正常動作と過去給与を保持しながら、実給与と画面への接続を続ける。詳細・履歴は折りたたみ、主操作を簡潔にする。

---

<!-- SKO_PROGRESS_20261010_0113 -->
### 継続作業（2026-10-10 01:13 JST）
- [x] PR #843 最新headのFlutter/iOS/Secret Scanが成功。独立計算条件・家族人数auto/manual/reset・個別住民税開始月モデルをmain `a0c0101af5f2c458333bf8aa3f2670bdc6cd7a03` へ統合。review済み6ファイルだけの予測treeと実merge tree一致。実個別保存／給与接続は次工程。
- [ ] PR #844：スリムな料率比較、資料／履歴の展開、確認popupを維持。展開時のURLスクロール状態衝突を修正。表示候補は項目ごとの最新確認1件だけに絞り、旧候補と全変更履歴を保存。最新 `421d373504098b1f9029f38399f2e5af181a979d` で再CI。本番未適用。
- [ ] PR #846：所得税年度・種類identity保持、未検証非選択、専用private版別PDF Storage／会社管理者upload・read／上書き削除禁止をsource追加。metadata登録は実object行存在必須。root独立SQL fixture成功、最新 `e3e6fb91a59e411149b16f05a2fbb49c475a6b19` でCI。PDF登録UIを統合中、実HTTP／bytes／本番JWTと税額計算は未検証・未接続。
- [ ] PR #845：生年月日から40歳開始／65歳終了の保険月境界を実装。1日／1月1日／うるう日を検証。Flutter成功、iOS確認中、個別画面・計算は未接続。
- [ ] PR #847：revision確認の操作を「確認を登録」、未登録を「未確認」に整理。最終確定と混同しない表示、既存RPC・計算変更なし。CI確認中。
- [ ] 次のDBレーンは個別住民税の開始月・月額保存と実給与計算への直接参照。旧固定額、未来登録前の給与、手動／確定明細を保持して進める。

<!-- SKO_SLIM_UI_20261010_0057 -->
### UI方針（追加確定）
- [ ] スリムで直感的に操作できる画面にする。通常表示は重要値と次の操作に絞り、資料詳細・履歴・補足説明は必要なときに開ける。支給／控除は明確に分け、日報は名称と回数／有無だけを表示する。
- [ ] PR #844 は現在値／確認値の比較、編集／適用、資料・履歴の折りたたみ、日本語の条件表示に整理済み。適用前の全情報・必須本人確認は維持。最新 `fead7061fefe040ce9ad1edfeb21a14d56c9c9ca` でCI確認中。

<!-- SKO_PROGRESS_20261010_0049 -->
### 継続作業（2026-10-10 00:49 JST）
- [x] 最新main `ae80103101f303291cc84c6094b02df5bcf3b15d` を確認。PR #841 の会社料率・所得税年度モデル、PR #842 の確定／手動給与境界の実SQL回帰検証を統合済み。既存内容・今回の追加仕様は保持。
- [ ] PR #843：支給／控除の独立計算条件・家族人数上書き／自動復帰・住民税月額適用開始モデル。テスト成功後の静的解析4件を修正し、最新 `ebaa458def8f749d152d76a2196cc708b715290c` でCI再実行中。実DB・個別設定・給与計算への接続は未完了。
- [ ] PR #844：会社共通料率画面／手動保存／項目別確認適用／変更履歴／会社条件。確認ダイアログ待ちに読み込み表示が動き続ける不具合を修正し、最新 `28bb201345b83311c8f59814e3a284fadc857473` でCI再実行中。
- [x] #844 の実migrationを独立検証。会社削除時は現在設定・候補・条件を削除、旧新値の変更履歴を保持し、削除済会社は旧membershipが残っても全RPCを拒否。権限・version・単項目適用・会社条件変更による候補無効化・監査失敗rollbackも成功。本番DBへ未適用。
- [ ] 公式資料の自動取得／検証候補登録、所得税PDF・年度画面、家族情報との接続、介護年齢判定、給与計算連動、確定時の料率／条件snapshot、共通手当の数量入力は継続対象。確認済み給与と確定給与は別であり、#842 は確定機能の完成を意味しない。

<!-- SKO_PROGRESS_20261010_0026 -->
### 現在地点（2026-10-10 00:26 JST）
- [x] main `1dc5411e7db1f137d878e4ad8efc1609a3f097df` のpush CI全成功：Flutter37949281839（解析／985テスト／Release gate／APK）、iOS37949281827（解析／958テスト27skip／署名なしDebug・Release）、Secret37949281871。今回のiPhone更新は未確認。
- [ ] #841 最新head13af6a0：所得税civil-date registry（新年度事前登録／旧版保持／official・計算ready・共通公開承認の分離／部分重複拒否）と境界テストを追加、解析・テスト通過後APK/iOS進行。DB/UI/給与への自動切替は未接続。
- [ ] #843 独立basisの純粋Dart実装：時給／日給／月給に依存しない時間×単価・出勤日数×単価・月額固定・直接入力、明示丸め、固定精度数量、旧直接金額互換、0円明細非表示判断、家族人数auto/manual/reset。6testsとCI進行。対象家族判定・UI/DB/明細接続は未完了。
- [x] #840最新head41119b23のproposal専用CI37950212575成功、旧legacy名称変更からの逆方向重複防止・2 UPDATE transaction rollbackをroot独立再実行確認。本番未適用。
- [ ] 税率設定ページと永続化レーン着手：Supabase CLI2.120.0を固定導入、CLIで `20261009151946_company_payroll_rate_registry.sql` を生成。既存会社単価／invoice税率には触れず、標準kind単一ID・custom UUID、管理者手動保存／検証済候補適用・原子的履歴を実装中。新migration本番未適用、UI連携と分離権限／競合検証後に公開する。
- [ ] 従業員別住民税の月額／開始年月／履歴の純粋契約を次laneで実装中。既存給与設定を勝手に書換えない。

<!-- SKO_PROGRESS_20261010_0014 -->
### 継続実装（2026-10-10 00:14 JST）
- [ ] #841 会社料率ドメイン実装：固定精度の全体／従業員／会社率、候補と現在値の分離、選択項目・候補ID・version・本人確認・資料検証・actor/timeの明示適用と旧新履歴を追加。所得税は率enum外の資料参照型。root review済み、Flutter/iOS CI中。DB／画面／給与計算／履歴永続保存は未接続。新年度資料registryは次作業。
- [x] #842 確定snapshot導入前の実SQL境界検証：固定月額互換、draft条件変更でrevision増加・確認解除、finalized／manualの全明細行と当該監査保持を実migrationでPGlite確認。root独立再実行と専用CI37949914541成功。確定操作・snapshot本体は未実装。レビュー確認APIはworkflow_state確定を行わないことを明記。
- [x] #840導入条件の本番metadata read-only確認：rate table RLS有効、anon/authenticated SELECT/UPDATE false、PUBLIC等のcolumn grants0。既存6RPCの実行権限／security mode／membership条件を確認。現時点の価格露出は検出されず、将来追加JSONへのgrant継承は再確認条件。本番データ・権限・関数は不変更。実JWT HTTPと製品操作は未検証。
- [ ] #840旧legacy名称変更→extra重複の逆方向穴をproposalのみで検証・解消中。既存同名枠は消さず、旧slot再利用・新UI・確定給与連携の導入停止条件は継続。
- [ ] 新main1dc5411eのFlutter/iOS push CI進行、Secret成功。実機Release更新は未確認。

<!-- SKO_PROGRESS_20261010_0008 -->
### 現在地点（2026-10-10 00:08 JST）
最新main `1dc5411e7db1f137d878e4ad8efc1609a3f097df`、tree `ed8ce6fdf00825f8c686aec51797c02ede969c80`（事前予測と一致）。
- [x] #837 支給／控除別枠・住民税分離表示：exact head730aa25f Flutter/Secret/iOS全成功。iOS解析成功、958テスト成功27skip、署名なしDebug/Release成功。root reviewとexpected-headでmain統合。料率連動等の未実装項目は継続。
- [ ] 新main push CIと今回のiPhone Release更新は未確認。
- [ ] #840 会社共通手当のDraft：追加SQLは本番未適用。既存grant/RLS/RPCのrepo上の境界を調査し、旧名称変更による重複、旧slot再利用時ID維持、combined saveでversion2回更新の停止条件を追記。新head0f401c39はdocs追加、CI再確認中。
- [ ] #838 GPSDraftに写真upload／cleanup／管理修正／本人申請とservice-role／lifecycle未検証範囲をsource path付きで追記、新head65c8dd5c。本番変更・gate ONなし。
- [ ] 給与確認revisionとworkflow_state確定の関係を調査中。「確認済み」を自動的に再計算不可と扱わず、実sourceで境界を検証する。

<!-- SKO_PROGRESS_20261010_0006 -->
### 継続作業追記（2026-10-10 00:06 JST）
- 会社共通手当は既存 company_rate_settings の3枠を再利用し、既存データを別マスターへコピーしない方針で Draft [#840](https://github.com/robin4250/sk-works/pull/840) を追加。追加項目のみのSQL設計案・価格を返さないラベルRPC・安定ID・競合version・RPC履歴の分離検証に成功。専用CIも成功。本番migration／UI接続は未実施。既存table-wide権限の追加JSON列継承を導入停止条件として、実際の既存grant/RLS/RPC経路を調査中。
- GPS保全 Draft #838 の最新head 64e90f3 は専用境界検証・SQL union・Flutter・secret scanすべて成功。UUID再送、cascade前snapshot、Storage参照保護の分離fixtureであり、本番機能完了・gate ONは意味しない。
- 個別給与の支給／控除の別枠表示 #837 はFlutter/secret成功、iOS Debug成功、Release確認中。確認成功までmainへ統合しない。
- 給与形態はworkerごとのkeep-aliveと親draft復元が既存実装に存在することを確認。料率連動・家族自動計算・住民税開始年月・日報数量保存・給与確定snapshot連携は未完了のまま扱う。

## 現在地点（2026-10-09 23:49 JST）
最新main `c6b51faa2faa3aca30706336b08eee9b9f0df686`。以降の旧SHA／未完了CI記載は当時の履歴。
- [x] #839 公式料率資料と年度／適用月の照合条件docs：Secret成功・root review後main792ea5fへ統合。製品料率／給与条件不変更。初期指定値は検索エラーで未取得。
- [x] #836 日報の手当金額入力非表示＋既存金額保持をmain c6b51faaへ統合。head968aa41c exact Flutter37944467461成功（985テスト／解析／Release gate／APK）、iOS37944467444成功（958テスト27skip／解析／署名なしDebug・Release）、Secret成功。会社共通手当ID／回数入力／新給与計算は未実装、iPhone更新未確認。
- [ ] #837 支給・控除別枠と住民税分離：head730aa25f Flutter37945301607／Secret成功、iOS37945301633進行中。日報変更とmerge-tree競合なし、保存／有給／controller／追加項目serialize不変。iOS成功後に最新版mainとの再照合・統合。
- [x] #838 GPS原記録保持次境界のprototype専用CI成功（37945588520）、SQL union／Secret成功。製品実装ではなく、本人／会社限定archive照会、写真bytes保持、本番適用／ONは未完了。
- [ ] #838へ本人／管理者Storage DELETEの28組対照を追加中：local6f1d22f3 PGlite成功、非owner RLSで旧欠落と候補のlive／archive保持・orphan cleanup・lookup失敗abortを検証。root review後公開CIへ進む。製品policy変更無し、Storage API／service role／同時参照／bytesは未証明。
既存GPS保持・日報・通知・Releaseを優先し、セキュリティ追加／Web開始・本番gate ONは行わない。

<!-- SKO_PAYROLL_SPEC_20261009_2305 -->
## 追加確定仕様：給与計算・会社共通手当（2026-10-09 23:05 JST）
既存GPS原記録保持・日報・通知・Release作業を優先し、その内容と履歴は保持。最新main確認時点は6e9e1b25。以下は未実装の追加要件であり、完了扱いにしない。

- [ ] **税率設定ページ（会社共通料率マスター）**：健康保険・介護保険（生年月日で40〜64歳判定）・厚生年金・雇用保険・子ども／子育て支援金・所得税資料管理・将来項目の自由追加。全項目を管理者が変更／保存。雇用保険は全体／従業員／会社負担を別管理し、単純÷2禁止。会社の都道府県・事業区分／業種から公式料率の対象を確認。初期値はユーザー指定値を照合する（今回本文には数値なし、推測登録禁止）。
- [ ] **最新料率を確認**：現在値の横に最新確認値・適用年月・情報元、差異は「変更あり」。項目ごとの「適用」のみ更新し、自動取得だけで給与へ反映しない。毎回確認ポップアップに「表示された料率・適用年月・情報元をご自身で確認したうえで適用してください」と明記。誰が／いつ／何％から何％へ変更したか履歴保存。
- [ ] **所得税は固定税率にしない**：国税庁源泉徴収税額表を年度・適用開始／終了・PDF付き管理。新年度版の事前登録、承認済み期間の開始日自動切替、旧年度履歴保存。公式新年度版の将来自動検出／取得を考慮。利用者アップロード資料は正式資料・年度・期間等を検証したものだけ共通化し、無検証全社適用禁止。PDFだけから未検証の税額を推測計算しない。
- [ ] **個別給与設定を計算条件の設定画面へ再構築**：時給／日給／月給の選択・生入力保持（既存#810を壊さない）。支給／控除を明確に別枠化。給与形態に依存せず、各支給は時間×単価／出勤日数×単価／月額固定／直接金額入力を選択。既存直接入力追加支給を保持。
- [ ] **家族手当**：標準項目、登録家族から対象人数自動取得、管理者手動上書きと「自動に戻す」。0人は0円、不要な0円項目は明細非表示。対象家族の条件を確認して計算する。
- [ ] **控除を2区分**：社会保険／料率連動は会社料率を参照し、健康／介護／年金／雇用等の適用する／しないと現在料率の確認表示のみ（個別画面で料率編集禁止）。その他会社独自控除は時間×単価／日数×単価／月額固定／直接入力。既存直接入力追加控除を保持。
- [ ] **住民税**：会社料率マスターに入れず、従業員別月額の手入力・保存、適用開始年月を保持して毎月自動反映。
- [ ] **給与明細の直接参照・確定snapshot**：会社料率＋個別計算条件＋出勤実績＋必要家族情報から自動計算。会社料率から個別設定へ計算済み金額をコピーしない。確定時に使用料率／計算条件／結果を保存し、後の変更で過去確定明細を変えない。既存確定明細の再計算／backfillなし。
- [ ] **会社共通手当一元化**：会社データ／会社設定を大元とし、日報・個別給与・明細が同一マスターIDを参照。同名手当を現場等へ重複登録しない。個別には必要時だけ従業員専用追加手当を保持。既存データの名寄せは名称のみで自動統合せず参照を確認。
- [ ] **従業員向け日報**：会社共通手当名の選択と1／2等の回数・有無のみ。金額／単価／合計額を表示しない。裏側で管理画面・給与計算・給与明細へ反映。画面・プレビュー・PDF／共有の露出も確認。
- [ ] 実装時は既存main／Open PR／本番契約を照合し、同一ファイル・DB・認証／権限変更の担当を一人に限定。既存正常機能と？ヘルプを保持／更新。ソース・CI成功と本番適用／実機成功を区別。

### 追加仕様の着手状況
- [x] 6項目の追加仕様を既存本文・履歴を保持して登録。
- [ ] 日報の手当金額入力非表示：main6e9起点でローカルcommit2108cd07を作成。金額controllerと金額代入を撤去し保存済み金額を保持、？ヘルプ更新、diffチェック成功。Flutter SDKなし、CI/実機は未確認。GitHub pushは自動承認レビューにより未確認remoteへのsource公開として拒否され、PR作成/main反映は未実施。回数入力/共通マスターは未実装。GPS保持作業の優先順位は維持。

### 日報金額非表示の公開状況（23:28 JST）
- [x] ユーザーの指定repositoryへの反映許可後、接続済みGitHub経由で #836 Draftを作成。head968aa41c/tree0930dc47、ローカルtreeと完全一致。日報金額欄/controller/金額代入を撤去し既存金額保持、？ヘルプと移行設計更新。shell pushは認証情報不在で失敗したが、接続済みGitHubの公開操作は成功。
- [ ] #836 Flutter CI37944467461・iOS37944467444・Secret37944467754実行中。ローカルFlutter SDKなし、main統合/実機は未完了。共通マスター・回数入力・税率ページは未実装。先のpush拒否記録は当時の履歴として保持。

### 継続実装・検証（2026-10-09 23:38 JST）
- [ ] #836 日報の手当金額入力非表示：head968aa41c、保存済み金額保持／？ヘルプ。Flutterテスト通過・Androidビルド中、iOSテスト進行、Secret成功。main統合／iPhone更新は未実施。
- [ ] #837 個別給与の支給・控除別枠：head730aa25f、住民税・税／社会保険月額・その他控除を分離。保存／有給計算／追加項目controllerとserializeは前後同一をroot静的照合、？ヘルプ／英語更新。料率連動・計算方式選択・家族自動・住民税開始年月は未実装。Flutter/iOS CI進行、Secret成功。
- [x] #838 GPS保持の次境界隔離検証：headbedc2213、root全source review済。PR829のfull Git SHAを再利用し、同一／変更payloadでarchive UUID再INSERT拒否・途中写真payload／元日報ID／撮影者と実変更者のcascade前保存を検証。ローカルPGlite／Node／YAML／diff成功、専用CI37945588520とSQL union37945588335／Secret成功。
- [ ] #838は隔離prototypeのみ。製品archive／本人・会社限定照会／本人・管理者双方Storage DELETE保持／実PG競合／Storage bytes保持／本番変更は未実装。capture/journey OFF維持。Draft保存と機能完成を区別。
- [ ] 公式料率の取得元を調査：国税庁2026税額表（月額／日額／賞与別）、協会けんぽ都道府県別・介護・支援金、厚労省年度別雇用保険、年金機構標準報酬。初期数値は指定照合前に登録しない。現行家族ageOnだけを介護月判定に転用しない（公式の年齢到達月ルールを別途検証）。

---

<!-- SKO_LATEST_STATUS_20261009_0931 -->
## 最新の作業一覧（2026-10-09 22:42 JST確認）

この先頭節と最新コメントが現在地点です。下のSHA・チェックリストは当時の履歴です。ユーザー最新指示を優先し、**GPS・日報・通知・Releaseを継続。セキュリティ追加実装とWeb制作はまだ開始しません。** 下に残る古い「セキュリティ→Web」順序は現在の実行指示ではありません。


### 免許証登録403の修正（2026-10-09 22:42 JST確認）

- [ ] 本番20260926191548の正式書類upload停止が直接原因。本人draftも同bucketのため回避不可。登録成功の実機確認は未完了。
- [x] #832最新6cfd29：写真選択/bytes前のsubmitted先行保存撤去、キャンセル0保存、失敗時誤成功防止、旧/通信不明写真保持、管理者でも本人専用読取。9widget＋6loopback HTTP。Flutter985成功/解析/APK成功、iOS958成功27skip/解析/署名なしDebug・Release成功、Secret成功。main d7dcd723へ統合済み。
- [x] 22:42 JST最新main `6e9e1b25a95bd1289d52992c6d323ac4a1a0e4a8` と全Open PR/Issue本文・最新コメントを再確認。pushCI Flutter37926525555/SQL union37926525635/代理退勤37926525554/Secret37926525576は全成功。#834はiOS対象file変更0のため新main iOS起動なし。同一アプリsourceの直前main d7 iOS37924923699/job113801457704も21:21 JST成功、解析問題0/958テスト成功27skip/署名なしDebug・Release成功を完了ログで確認。d7→6eのlib/test/ios/pubspec/Release導入script差分0。iPhone導入・起動は22:52ログ成功、単体起動/写真登録は未確認。
- [x] #833最新6143b8f4の比較59件PGlite/PG17成功。全active要件を一括許可せず、会社/要件ID/名称の明示対象リスト方式を採用。
- [x] #834最新7e4b5f08実SQL（SHA3187f1f5）18停止rollback＋55権限/path/保持＋4非official anon/auth before-afterをPGlite/実PG17成功、root独立確認。旧444の匿名許可巻込拒否をPUBLICとauthenticated専用RESTRICTIVE条件分離で修正。20:47 JST本番ledger20261009114722へ適用し、空OFF確認後、会社・免許証要件1組のみ別操作ON。最新backupから既存データ/ACL/RLS/保持guard/trigger/他bucket停止を維持。root本人read-only許可true/他要件0、status2/history4/objects0不変。Auth/会社role/Master付与なし。
- [x] #834全5CI（Flutter37925157901/専用PG1737925157726/union/代理退勤/Secret）成功、追加境界review後expectedheadでmain6e9へ統合。実アプリsourceは#832統合d7と同一。
- [x] 22:52 JSTユーザー実Macログで今回のRelease上書き導入・devicectl起動成功（App installed / Launched application、Bundle ID com.skworks.skWorks）を確認。22:49の接続失敗後、作成済みRunner.appをUDID指定で再導入成功。main6e9固定手順で案内したbuildだが実機binaryのcommit埋込照合は未実施。
- [ ] ケーブルを外した単体起動・免許証の写真付き登録を実操作確認。main6e9固定Release手順と既知analysis_options変更保存helperは照合済み。DB SQL許可確認をStorage HTTPや実機成功とは扱わない。#835本番報告docs-only Draft保存（最新ea917268/Secret37927613573成功）、sourceと実ledger番号を区別。
- [x] 20:21 JST対象限定復旧snapshotを非公開保存。初回preflightがworker1行の通常登録更新を検出しDDL前中断、20:46 JST最新snapshotを保存し直して更新内容を保持。既存status2/history4/Storage objects0を取得。対象は報告時刻に対応する免許証1組のみ照合。全DB/Auth/Storage bytes backup・復旧演習ではない。保存済みsubmitted/写真未添付は勝手に変更しない。

### GPS原記録保持の次作業（21:03 JST・最新main照合）

- [x] #829のfixture archiveだけでは足りない3境界を独立read-onlyレビュー。根拠はmain6e9のforce_manage_attendance、_recoverCaptureDraft/recoverOrInsertCaptureDraft、attendance_evidence_delete、journey source_clock_in CASCADE。商品archive未実装・本番追加DDLなし、capture/journey OFF維持。
- [ ] 管理修正/有給切替後の固定UUID再送：public照会nullから同日同UUIDを再INSERTできる欠落。archive済UUIDは同payload/別payloadとも再登録を拒否し、本人・会社限定照会で「登録済み・管理修正で無効化」を識別。現在勤務へ復活させず、照会失敗/23505で新UUIDへ変更しない。
- [ ] raw/reportに加え途中写真payload・元リンク・実actorもcascade前に保持。会社/worker/site削除は保持/削除方針を定めて別ケース検証し、archive失敗は業務変更もrollback。保持期間を勝手に決めない。
- [ ] Storage写真：本人のorphan判定はpublicだけ、管理者ORは参照確認なしで削除可能。archive参照を追加するだけでは不十分。本人・管理者双方のDELETEへ保持条件を適用し、途中写真の別bucketと未登録写真cleanupを別検証。SQL snapshot保存をbytes保持・復元完了と混同しない。

### 角印の本番反映（2026-10-09 13:44 JST・最新）

- [x] 対象限定の復旧snapshotを保存後、main a086828の角印関連4本（agreement base/v2・真正隷書style・3帳票snapshot）を1 transactionで本番適用。ledger `20261009044454 company_seal_reisho_dependency_and_document_contract`。canonical計算は既存実定義と一致し再適用なし。
- [x] 会社旧列・既存請求書2件/給与明細2件/支払証明書0件の全row照合は不変。会社2件は既存legacy維持、過去印影backfillなし。既存ACL/RLS/trigger保持、空JWTの新設定RPCは拒否。
- [x] 真正隷書1種類の設定保存と新規3帳票連携の本番契約が利用可能。親子合意gateはOFFのまま。角印反映時点の記録。有給は19:05に適用済み。GPS/通知/車両等の新migrationは未適用。
- [ ] 最新ReleaseのiPhone上書き導入ログ、新しい書体選択→PDF確認→保存→新規帳票の実操作確認。5書体全完成・TestFlight公開は未完了。
- [x] #818のcanonical未導入という判定を訂正し#823 Draftへ保存。実ledger番号とrepoファイル名が異なっていたため、関数本文・契約を照合した。以下の未適用表記は当時の履歴であり、この節を優先する。

### 完了（ソース統合・検証）

- [x] #782 GPS/写真の失敗記録DB契約、#785 GPS＋写真/UI/固定UUID再送/日報PDF・通知導線・tutorial・Release準備をmainへ統合。実PDF生成と目視確認済み。実機通し確認・本番新migrationとは別。
- [x] #786 車両/GPS勤務日/グループ退勤/日報source/meter/通知serverの依存を重複せず統合。隔離PGlite・実PostgreSQL競合検証成功。新migration本番未適用・rollout OFF。
- [x] #787 管理者「利用機能のON/OFF」に太い青枠。#789 明示日報登録後の保存ID固定通知発行・通知だけ再試行を統合。#801で再起動後の固定ID再送保存もソース統合済み。実機再起動確認は未完了。
- [x] #788 日給有給/時給×8・手動/月給非加算の計算と明細連携、#793 適用前確認・復旧資料を統合。全CI成功、最新実PDF目視済み。半日有給そのものは未対応。
- [x] #791 現場別平米/請負・内訳提案revision・双方確認・immutable合意PDF、#795 任意追加/削除・税手動理由を統合。実PG競合・4PDF目視・全CI成功。現場共有元/先・親子関係を検証し相手登録は上書きしない。
- [x] #792 車両通知先1〜3名/初期1名提案・停止受信者、#796 受信者の削除アクセス制限を統合。選択/台帳/roles保持、独立ACL/受信者検証成功。共通auth/RLS/削除実行を変更しない。
- [x] 19:22確認時のmain（現在は上の免許証節を優先）：`a086828bb46819d74ca1bf9bd245e8f94a90dbdf`、tree `14a8e9f6f85b25b02411a2c58df12f8e39befd8f` 予測一致。#819最終unionはexact85fb全8CI成功・実PDF目視/照合・review後統合、#816da39を含み重複終了。統合後main push全7CI成功（Flutter37876903313/iOS37876903312/Secret37876903356/union37876903406/group37876903317/角印37876903423/合意PDF37876903579）。角印/有給は本番適用済み、GPS/通知/車両等は未適用。
- [x] ユーザーログで以前のRelease上書き導入・起動を確認済み。今回追加変更のiPhone更新は新ログ未受領で未確認。

### 未完了（継続）

- [x] #827 GPS取得記録/有給修正の交差レビュー（03fbb7cf、Secret37917492370成功）と#828 通知/車両/代理退勤依存順（cc245224、Secret37917571452成功）をDraft保存、root全文review PASS。新GPS契約UPDATE不変guardはDELETE保護ではなく、現本番force_manage_attendanceにも削除経路を確認。保持/アーカイブ/写真bytes復旧未完了でcapture/journey有効化は未実施。本番追加DDLなし。

### 有給の本番反映（2026-10-09 19:05 JST・最新）

- [x] #826 本番適用報告をDraft保存（f4f75e9、docs1file42行、root全文review PASS）。authenticated role capability1実確認、変わった37関数中のsignatureは意図した7だけと追検証。main/製品は変更しない。

- [x] `20261009100557 paid_leave_wage_contract` 本番適用。main a086のexact `20261008200018` のみ、独立review PASS/PG17＋Flutter等全4CI成功/限定backup一致を15表share lock内で再確認後transactional適用。
- [x] post差分は7関数とmigration ledgerのみ。既存明細2全row・計算入力・旧ACL/RLS・角印3trigger/reader・cronは不変。新7関数prosrcはsource完全一致、private直接実行拒否・authenticated capability1、日給/時給8/手動0/月給内訳の合成read-only4例成功。
- [ ] 実機の設定・新明細操作確認。既存draftの手動再計算は行っていないため保存済みの金額・旧警告は今回更新しない。会社別OFF gate無し、通常操作/既存cronは以後新契約を使う。manual/finalizedを再計算しない。


- [x] 有給の対象限定復旧backup実取得・非公開保存（18:42 JST）：同一REPEATABLE READ READ ONLYでscope3、明細2/設定2/実関数37・角印導入後依存/対象入力/trigger/ACL/RLS/cron/ledger。scope異常・不存在worker・範囲外scheduler候補・必要関数不足は0、JSON検証/0600/保存成功。SHA256 `53eb82630c9189441225a77d19dbea9860e8991a24e83408727759ace1bdf93b`。実行scopeは設定＋保存明細の全pairから取得。全DB/Auth/Storagebackupや復元演習ではない。後に19:05の有給適用に使用済み。

- [x] #825 有給適用前の対象限定backup取得SQLをDraft保存：056e51b/tree4e25bd、Secret37912267834成功。同一READ ONLY snapshot、実target5+guard6/角印/全対象trigger実定義、cron、全保存期間明細と入力・会社全payroll計算元・変更履歴。root空scope EXPLAINのみ成功で実列/関数/構文解決を確認。作成時点は未実行。後にrootが18:42対象限定backup取得・19:05適用を実施、復旧演習は未実施。scope異常/範囲外scheduler候補/不足間接依存で停止。

- [x] #824 有給＋本番角印snapshotのPG17組合せ回帰：最新343b564をDraft保存（未統合）。実PostgreSQL17 run37911435292/job113757271489成功・root log確認、Secret37911435233/union37911435408成功。旧明細への印影後付け拒否・新明細印影保持・社名/書体変更後の同期/scheduler・有給DDL復旧で角印helper/3trigger保持を検証。初回fixture重複42723を修正しassert強度保持。合成reader/非給与generator stubの制約明示。Flutter37911435307も成功、PR対象全4CI成功。本番19:05適用済み、実機未確認。

- [x] #794 ソース統合・CI完了／実運用未完了：途中現場GPS/写真：専用bucket/元出勤・実stopスコープ/固定UUID保存・生証跡保持/日報連携。所属解除後参照と非有限metadataを修正・独立検証済み。最新Flutter/iOS全成功・5PDF目視後main統合済み。新bucket保持・削除連携/実機/全競合は未完了、OFF。
- [x] #797 合意帳票に会社住所/電話/FAX/共通角印ONOFFを新規snapshotへ保存、旧snapshot再生成・backfillなし。全CI/独立SQLレビュー成功。#800 社名/角印の重なり修正、短/長社名ON/OFF4PDFを目視後main統合。5書体角印は未完成。
- [x] #801 通知再送永続保存：92a8395全3CI成功・独立レビュー後main統合。実保存rowから会社/本人/日報ID固定、照会前persist、通知のみ再試行。保存直後の既存再読込失敗・0件結果の未確認保持の制約はコメント参照。実機未確認。
- [x] #802 親子会社内訳差異表示：a687d88全3CI成功・rootレビュー後main統合。各社の最新共有提案を照合し、一致を合意扱いせず、相手元データを上書きしない。実機未確認。
- [x] #803 現場別・双方確認済み帳票導線：fecafd6全CI・独立レビュー後main統合。exact月次会社、最新双方確認、tap時のみsnapshot、旧月次合算なし、非同期旧応答棄却。実機/本番新migration未確認。
- [x] #804 ON/OFFを既存Master設定へ読み取り専用保管、#805サイン一覧ホームボタン削除：翻訳修正後全CI・独立review成功、main統合。保存設定/署名/DB/権限保持。Master本人限定登録の実DB人数は未照会、既存server ID許可リスト維持。iPhone更新未確認。
- [ ] #806 従業員登録＋初回案内1画面：最新a7dbfd5全6PR CI成功を再確認（Flutter37868426882/iOS37868426567/Secret/SQL3系）。current招待v2 marker・個別unknown処理を検証済み。ただし画面を閉じた後の作成済み案内『送信だけ』再開は正式な本人確認契約が未実装。Auth再発行/秘密再構成を行わずDraft維持、未統合・実機未確認。
- [x] #807 限定初回状態/明示手動送信履歴：f993全5CI・独立SQL/PGlite追加UUID/ACL検証後source統合。本番未適用gateOFF。過去複数招待UIの曖昧結合拒否が必要、実送信/安全な再発行は未完成。
- [x] #810 個別給与設定のスクロール戻り修正：52ee138全CI成功・独立review後main統合。時給/月給・生入力保持3widget検証、別社員の保存済み月給尊重。DB/計算/登録処理不変更。iPhone更新・実操作は未確認。
- [x] #809 請求書名字のみ印：ea72dace全6CI・実PDF5例目視・独立review PASS後main統合。明示姓/承認時immutable snapshot、別RPC世代不一致/通信/契約不正は生成停止、真未設定/未導入だけ旧印保持。新gate OFF・本番未適用・iPhone未更新。
- [ ] #808 真正隷書1種類の研究：実FlutterPDF生成成功、3PNG目視済み。実帳票サイズ2頁PDF/PNG目視済み、短名可読・長名小枠未合格。原文許諾/説明同梱の無償社内試験phase1会社設定preview/style保存/共通rendererを実装開始。既存legacy/過去snapshot保持、3帳票future-only連携が次工程。5書体完成・iPhone反映・有償配布許諾とは別。
- [ ] 有給の実機警告09:57：本番契約は19:05適用済み・capability1。既存保存明細の金額/旧警告は手動再計算していない。最新Releaseで設定保存・自動draft/新明細の通常操作と表示を確認する。manual/finalizedは再計算しない。
- [x] #814 真正隷書phase1：53999ad全6CI・実寸PDF目視・独立review後main統合。会社名自動印影/preview/限定style保存RPC/正規TTFと原文条件同梱、既存ONOFF/legacy/過去印維持。欠字/小枠16字超は拒否。本番13:44適用済み、3帳票連携#816も本番配置済み。iPhone更新・操作は未確認。5書体完成ではない。
- [x] #813 本番相当有給PG17隔離検証：dcdae91全Flutter/実PG17/Secret/union成功・独立review後main統合。保護対象/旧定義ACL復旧を確認、DDLだけでは変更済みdraft金額が戻らないことも検証。lib/既存migration/本番不変更。18:42対象限定backup・19:05本番適用完了。実機未確認。
- [x] #816 真正隷書3帳票連携：最新da39全7CI成功・8実PDF/PNG目視/照合・独立review後、#819に含めmain a086828へ統合。重複終了。旧snapshot/v8配置保持。本番13:44配置済み、実機未確認。
- [x] #815 Release導入の既知analysis_options5行変更：560145a全対象CI・root fixture成功後main統合。未知diff/staged/他dirty/非mainは拒否、制限権限backup/照合後の対象1fileだけrestore。Mac実行/新インストール未実施、main CI完了後案内。
- [x] #818 角印本番read-only preflight/復旧資料：f227ae17全対象Secret成功・root review後main統合。必要依存/計算fix順序/既存migration番号差異を記録。当時のpreflight。後に対象限定backup取得/本番角印適用済み、canonical誤判定は#823で訂正。
- [x] #819 最終union：85fb全8CI成功、専用7PDF/PNG目視・最新生成物照合・source review完了。main a086828/tree14a8e9f6へ予測一致統合。v1/v2/v3『双方確認済み』、実status/月次3states/DB/権限保持。統合後push CIと本番/実機は別確認。
- [x] #822 dd255a19：ソースbackup復元/新snapshot読込資材保持/古い2関数JSON代用不可の補足資料をDraft保存。合成復元PASS・Secret成功・root review PASS、main未変更。
- [ ] #820 篆書の同一作品別Unicode coverage比較99bb074d、#821 正規書体購入経路と組込み条件85fdcdcdをDraft保存・root review済み。会社名の欠字・SKO用途許諾が未解決。購入/契約/業者連絡無し、製品5書体とは別。
- [ ] 全新migrationの適用前依存/実定義/データsnapshot/復旧手順/全体連携確認。ソース統合を本番適用や機能ONと扱わない。
- [x] 最新main a086828の全push CI・Release導入経路・SHA guard確認、Mac用1行コマンド準備完了。実行ログは未受領。
- [ ] Macバックアップ・Releaseのみ同Bundle ID `com.skworks.skWorks` 上書き。Debug/flutter run/既存アプリ削除/無断変更破棄なし。
- [ ] iPhone単体起動、GPS撮影、日報、通知、給与、請求・支払、印刷/共有の通し操作。保存済みデータ・認証・権限・RLSを保護。
- [ ] 新外部メール送信基盤/実送信、削除フロー全体/保持分類、Master登録案内は未完了。

### 外部待ち・別確認

- [ ] Apple Developer会社登録、TestFlight署名/アップロード/公開。
- [ ] 本物の角印5書体の組込み・電子印影許諾/日本語字形。会社共通ONOFF・既存自動印影と5書体完成を混同しない。購入/業者連絡未実施。

同じファイル・DB・認証の変更担当は1人。競合しない作業を並走し、完了後は次の未完了へ進む。以下の記録は履歴として保持します。

---

## 最新追加（2026-10-09 02:17 JST）

- **完了**：#768 fef8 実Postgres16.15でAttendance Races37814256287・Activation Guard37814256558成功。OFF開始/有効化4順序・代理/本人退勤競合を確認。
- **完了／保存**：#776 車両メーター日報snapshot・承認修正復元・全署名入口serverguard、独立PGlite＋SQL CI37814401868成功。#773 新RPC/ledger/必要列が揃わない限りmeter false、SQL CI37814539144成功。
- **未完了／CI中**：#759最新ff16b、#774最新d022b、#755最新349ef0b、#761/764/765新SQL＋Intel、#756 Release案内修正、#777写真capturecontroller。#777はUI/DB未接続。全機能完成・実機導入ではない。
- **未完了／監査中**：#778 disposable PGで会社削除・管理者修正との交差lockを独立確認。既存成功CIは保持、原本SQL未変更、main merge禁止の調査PR。
- **未完了／保存準備**：同現場メンバーの日報通知・設定済み車両担当者通知のserver実装は独立権限検証成功。初期admin1 UI・停止受信者・通知導線・並走・本番適用・外部メールは未完了。
- **最新main**：8ee196949（#772統合）。push Flutter37813940076/iOS37813940181実行中、Secret37813940091成功。PR成功とmainの実行を別管理。新migrationは本番未適用、全新rollout OFF、iPhone最新Release未導入。

---

<!-- SKO_SECURITY_WEB_SEQUENCE_20261009 -->
## 追加実行順序：多層セキュリティ完了 → Web版（2026-10-09 ユーザー確定）
**白いタブレットの既存ChatGPT Workが、このIssue #273を単一の作業管理場所として実行する。** 新しい独立Workに分けない。既存TestFlight/Release作業を消さず、同一ファイル・DB・認証を競合変更しない。既存main巻き戻し・Debug導入・既存SKO削除は禁止。

- [ ] **先行A：セキュリティ監査・設計** — 詳細は #775。Supabase RLS、会社間/従業員間の権限、Storage、RPC、Edge Functions、認証、重要操作の再認証、サービス鍵・秘密情報、ログ、バックアップを棚卸し。侵入・越境・権限昇格の否定テストを作る。
- [ ] **先行B：多層防御の実装・検証** — 外側のWAF/レート制限/重要操作のサーバー側検査と、内側のRLSを両立。直通APIが外側を迂回し得る点を踏まえて経路・権限を検証。監査ログ、異常検知、通知、復旧/ロールバックを整備。
- [ ] **先行C：隔離ハニーポットとMTD** — 本物の情報を複製しない架空データ・ハニートークン、登録規模に応じた合成データ拡張、攻撃状況に応じた防御ルール/デコイの変化。実DB構造は変えない。本番への接続を隔離し、誤検知・負荷・復旧を試験。
- [ ] **セキュリティ完成ゲート** — 他社データ・給与・請求・個人書類の越境拒否、直接API/RPC/Storage不正アクセス拒否、監視・復旧・負荷・第三者レビュー等を検証。層の数だけで完成扱いにしない。実装・本番適用の前後を明確に記録。
- [ ] **上記完了後：Flutter Web版の開発・社内試験** — Apple Developer登録待ちの従業員全員向け。既存iOS機能は保持。WebのみGPS自動**出勤**を無効にし手動出勤固定、退勤時の日報必須は維持。GPS＋写真は撮影時取得としてWeb実機検証。通知・PDF・カメラ・QR・認証・RLS・ホーム画面追加を検証し、安全性確認後に社内配布。
- [ ] **並走：iPhone Release/TestFlight準備** — Apple登録・署名待ちを明示し、競合しない作業は継続。実機インストール/配布の未確認を完了扱いにしない。

現時点で #775 は設計課題であり、上記セキュリティ実装・検証・Web版は未完了。Workはこの順番を遵守して進捗を #273 に追記する。

## 最新チェックポイント（2026-10-09 02:07 JST）

### 完了
- PR #772 を main `8ee196949c8a4c7f038937a384326e9838535449` に統合。Intel macOS/Xcode26.6で iOS CI37809051448：解析・全テスト・署名なしDebug/Release成功。Flutter37809051187・Secret Scan37809051315成功。#766は同一修正を含む#772に統合済みのため重複終了。
- #770 最新a4d49b5：Flutter／iOS／Secret Scan／Viewer approval invitation SQL・Deno検証すべて成功。本番migration/Edge未適用。
- 車両開始・切替・メーターとグループ退勤の会社→現場→出勤ロック順修正、統合PGlite3系統成功。ローカル53b24fc保存済み、本番未適用。

### 未完了・作業中
- #759 最新e9e6：832テストとReleaseゲート成功、Android NDKダウンロード破損でビルド失敗。失敗jobを再実行中。
- #774：グループ退勤Widget testのテスト用認証タイマー残存、車両画面のlint2件、実SQLとのRPC名を修正中。
- 車両メーター日報attachment SQLは独立PGlite成功。CI保存・実Postgres並走・承認修正との交差検証・本番適用判断は未完了。全サーバーフラグOFF維持。
- 最新main push CIは統合後あらためて照合する。署名・iPhone導入・実機GPS/写真/Face ID・通知/外部メール送信は未確認。

### 外部待ち
- Apple Developer会社登録／TestFlight、実機Release署名と導入、本物の角印5書体利用許諾。

---

## 現在の作業状況（2026-10-09 01:39 JST）

### 完了（ソース保存・隔離検証／実機とは区別）
- [x] 最新main a2a0ad26cebfbcc39ec99fe49f8b78d4ceb6c202・Open PR・本Issue・全main push CIを再確認。main Flutter37786431506/Secret成功、追加iOS37786431585失敗。#753最終PRのiOS成功と区別。
- [x] GPS #753 main統合・本番20261008134105適用、登録件数/RLS/旧NULL保持。
- [x] 削除関連183件の隔離試験成功。全削除機能完成ではない。
- [x] #754対象ID/月付き通知導線、#755選択者1〜3名限定SQL、#757勤務モデル、#758車両モデルを保存。Flutter/Secret成功、実機未確認。
- [x] #768実PostgreSQL16.15の2接続試験成功（0d2cf2e/run37807799111）：同車両1winner/23505loser勤怠rollback、meter同時再送1event/1warning、meter対車両DELETE no deadlock/partialsave、2人同時proxy checkout/source毎1件/retry不変。
- [x] 実PGで検出したFKロック40P01を#761/#764 NO KEY UPDATE＋vehicle→claim順へ修正、独立レビュー/PGlite/実PG成功。
- [x] #771日報の限定source結合と#773限定read-only capabilityの専用SQL CI成功。全staged gates OFF、本番未適用。
- [x] #770 viewer確認者招待のNode/PGlite/Deno型チェック成功。一般管理権限は追加なし。
- [x] #763書体許諾/欠字・#767SKOサポートGmail送信元根拠を監査保存。5書体完成/メール実送信なし。

### 未完了（作業継続）
- [ ] #772 iOS CI容量対策：GitHub annotationsがarm64 runner未取得/容量不足と明示。公式macos-26-intel/Xcode26.6に固定、全check保持。実run37809051448開始、解析成功/テスト進行中。ユーザーMacXcode27は変更なし。
- [ ] #766 lock保持：Flutter/Secret成功、旧arm64 iOSは容量不足で開始前cancelled。#772にも同じ修正を含む。
- [ ] #759 TOP保存データ連動％＋統合要対応：5f713dc Flutter/Secret成功。会社給与方針/確認者raw証跡・必要書類指定/資格推奨を追加、重複翻訳を修正してIntel CI込みe9e6fe5で再CI。
- [ ] #770古いsource-contract（確認者選択でmanager強制）を新role保持契約へ修正、a4d49b5で再CI。
- [ ] #774代理退勤→日報roster/source結合＋運転者meter/OCR確認/手修正/減少時手入力＋同snapshot画面/PDFを保存、CI待ち。運転者以外のmeter編集は禁止。
- [ ] 車両event→日報の限定attachment/context RPC実装。旧writerがONで拒否される箇所の実接続・署名/再保存/管理者承認修正の統合検証。
- [ ] OFF出勤とrollout ON切替の競合、安全なcompany lock順、車両付きmember proxyの複合実PG検証。全gate OFFのまま修正中。
- [ ] GPS/写真未登録・取得失敗の即時確認popup、capture時刻/GPS/address保存と日報表示。現状は取得失敗で登録停止するgapを監査、独立controller準備。まだ現画面/DB未接続。
- [ ] 車両開始/日報登録メンバー通知、1〜3名vehicle担当、繰返し整備間隔、外部メールdispatcher。
- [ ] #769本人read-only削除状況UIはFlutter/Secret成功、iOS未完了。受付false/POSTなし。正式書類分類/保持/実削除ライフサイクルは未完成。
- [ ] main統合・安全なmigration判断・最新Release上書き・夜勤/月跨ぎ/給与/帳票の実機通し確認。

### 外部待ち／本人操作
- [ ] Apple Developer会社登録・提出書類対応。TestFlight upload/配布は登録後。
- [ ] Mac/iPhone署名・Release上書き・実機確認。既存アプリ削除/Debug/flutter run禁止。
- [ ] 角印5書体の正規許諾と会社名glyph coverage。未許諾5種類を完成扱いにしない。
- [ ] sko.support@gmail.com現役OAuth/送信元設定は未確認。実外部メール未送信。
- [ ] 会社固有給与規則・正式書類保持期間を勝手に確定しない。

GPSのみ新規本番適用済み。新staged機能OFF、その他migration/メール/削除未実行。最新実機導入成功は未確認。以下は過去履歴です。

---

<!-- SKO_CURRENT_STATUS_START -->
## 現在のやること一覧（2026-10-15 08:38 JST）

> この節を現在の正とし、旧節・コメントは当時の履歴として保持する。  
> **ソース保存／PR CI／main統合／main CI／本番反映／導入SHA付きReleaseログ／機能別実機確認／TestFlight試験を別々に判定する。**

### 完了済み

- [x] 最新main：`364cbd2d3e29ea5f7870d93858b0330b72de23bf`（#1040統合）。tree `3ec774dd6ffef0ca65c03d97316ad3bcbd125a4c` は最終検査済み期待treeと一致。
- [x] 最新main自身の全10 push CI成功。[Flutter 38621955701](https://github.com/robin4250/sk-works/actions/runs/38621955701)・[iOS 38621955829](https://github.com/robin4250/sk-works/actions/runs/38621955829)・[Secret Scan 38621955552](https://github.com/robin4250/sk-works/actions/runs/38621955552)と、4段集計/PDFKit/注文書・請書/印影/Routeの検査が成功。
- [x] #1039 head `ef7fc6f789b5a5dc2726c11b5765d63120d5a6ef`：最終Flutter/iOS/Secret/LINE専用CI成功後に通常統合。LINE月別表・現場別単価の参考額と帳票を既存InvoiceEngine/InvoicePdfServiceへ直接接続。別デザインの請求書は作らない。
- [x] #1040 head `a65589ed670af95896d92c15666fd1d13d6135ff`：全12 workflow成功・実PDF目視後に通常統合。SKO請求書/LINE請求書/支払証明書は「小計→福利厚生費→消費税→請求/支払金額」の4段。途中の福利/税行を非表示、保存額・現場別料率/丸め・控除・経費原額を保持。検証例は32,800＋4,920＋3,772＝41,492、控除1,000の支払額40,492。
- [x] #1036月次注文書/注文請書：全13CI後にmain統合、検証SQLの本番反映・既存関数/権限保持を照合。月/revision別の明示保存snapshot、注文書/請書は第2頁、経費は第3頁以降。工期初期値は対象月1日〜末日、編集可能。実契約の発行完了ではない。
- [x] **#996の旧ブロック解消**：ユーザー再承認後の公式適用成功を11:55 JSTコメントで確認。本番履歴 `20261014025146 route_signed_checkout_customer_billing`、4関数新定義・契約/ACL照合済み。退勤正式日報サイン→取引会社ごと1人工、別数量承認不要。旧却下のままの残件へ戻さない。
- [x] 12:05:25 JSTの株式会社秀中/2026-10保存invoiceは正規再計算と整合するversion 1、blocked/pending=false、41,492円への更新を本番読取で確認済みと記録。実機プレビュー/印刷成功とは別。
- [x] 給与 #1017/#1019/#1024/#1030 は統合済み。支給/控除の時間・日・月タブ、旧月額保持、手当1〜3の日単位、家族/交通費の月単位編集、固定控除6項目の修正/0円/自動復帰、設定導線・権限制限・未設定表示。控除overrideの本番定義/契約/権限照合済み。個人の税保険条件未登録を自動計算済みとしない。
- [x] チャット/LINE #1008/#1018/#1023/#1025/#1026/#1038 は統合済み。#1004と #1020/#1021/#1022は統合候補へ含めてcloseされた履歴を保持し、単独merge済みとは記さない。本文古上/新下、一覧最新、同group共有、TXT/ZIP＋受信統合、月別手直し、単価/正式名称、手動from接尾辞重複修正を保持。
- [x] LINE第1段階の実受信・本文表示成功、既存「すみだ建設出勤」の写真/連携は確認済み。新たな月別取込・正式請求発行とは区別する。
- [x] 非WEBセキュリティ #1027/#1028/#1031/#1032 はmain反映、必要な本番適用・ACL/既存保持照合済み。合成検証記録の保存通知/再認証出力、本人の実監査ログ読取、復旧コードNULL拒否/失敗回数保持を実装。実攻撃の全量収集や防御全体の完成ではない。
- [x] LINE一般非開放の準備 #1034/#1035/#1037 はmain/必要本番反映済み。現在 `general_enabled=true` で利用状態維持。一般停止・封印はまだ実行していない。
- [x] 04:57 JSTに最新mainのRelease上書き「導入可能」を通知済み。同じ案内を完了通知として繰り返さない。署名・実機起動の成功証拠とは別。

### 作業中・未確認

- [ ] 08:38 JSTの新依頼：給料一覧上部を左から「税率設定」「社内共通手当」「個別給料設定」の等幅・同高・均等間隔3分割へ。社内共通手当は既存会社共通手当への入口を再利用し、管理者/閲覧者権限を維持。UI追加のみの未実装・未CI・未統合依頼。給与計算/手当反映/DBのMac担当作業と競合させない。
- [ ] 最新main `364cbd2d…` のMac署名Release上書き、iPhone起動・ログイン保持・単体起動をSHA/logで確認する。過去 `25d9c1d7` のinstall/launch成功を最新導入へ流用しない。信頼許可の操作だけでも起動成功とは扱わない。
- [ ] 最新実機で請求書表示/承認ボタン→保存→印影、退勤署名→請求再計算、4段集計、注文書/請書の保存・版保持・印刷共有を確認する。
- [ ] 給与の個人税保険条件・適用月・単位数量・固定控除の実設定と明細連携、経費5段階保存/精算/原額帳票、チャット順序/最新preview/共有/送受信/写真入替の実機確認は残る。
- [ ] LINE実ファイルは5,089投稿。2026/09は94候補（日勤93/夜勤1）が参考計算可能だが、18行の1人工仮置き、訂正原文、手当47行対ノート51日等の未照合あり。4,254,955円は未確定参考額。94人工の総数一致だけで月全額確定にしない。
- [ ] 対象2024/01〜2026/09の月別表へ本人UIで取込/保存/修正し、原文・配置/終了・訂正・半日・手当・正式宛先・登録経費を照合する。10月勤務の正式請求は後回し、10月投稿の9月訂正は対象に含む。
- [ ] 本番LINE一般停止は未実施。TestFlight/無料公開で一般へLINEを開放しない方針を配布前に実権限で検証する。先に自社過去請求の形を整え、確認前に日程だけで封印しない。
- [ ] 会社別の無料/有料/ハイグレード・追加機能権限、Master全体切替UIは未完成。今後の新機能ON/OFF、OFF時データ保持、同一会社/アカウントでプラン変更する方針のみ確定。
- [ ] セキュリティの実取込feed/相関/対応履歴、実MTD/永続台帳/鍵復旧、実監視配置・実機Face ID/共有検証は残る。合成データを実不正検知として表示しない。
- [ ] Open PR39件。旧 #1015（UI）/#1016（保存）の設定済みCIは成功だが、後続 #1027/#1028で必要差分を採用済み。重複mergeしない。#1013/#1014は検査成功の隔離候補で本番統合ではない。#1000はCI成功の旧資料Draftで、後続記録では使用しない方針。Openのままでも現在の導入必須残件と混同しない。
- [ ] 未保存作業・Mac差分の状態はこの整理から確認できず、保存完了/破棄済みと扱わない。

### これから

- [ ] 最新Releaseで上記機能を実機確認し、不具合を直した後にTestFlight試験・配布へ進む。現CI成功をTestFlight完了としない。
- [ ] LINEの一般非開放を表示だけでなく直接REST/RPC/共有本文/preview/通知/送信の各経路で確認。実Realtime、既取得URL、送信in-flightの残条件を照合し、OFF時も保存データ/受信を保持する。
- [ ] ベータ資料は #977/#984の5PDF/180頁検査済み版を基礎に、最新の給与・LINE・4段帳票・注文書/請書・セキュリティ画面の対応章と？ヘルプを更新する。ベータ表記、機能別目次/分冊/章追加、固定ページ上限撤廃を維持。実PDF全文/A4/切れ/リンク/日英案内/実機閲覧を確認する。
- [ ] プライバシーポリシー・サポートURL/メール・運営会社は既存資産を照合し、未発見を未作成と断定しない。Apple申告・配布条件と実際のアプリ機能を合わせる。
- [ ] DB/Storage全量・iPhone内データ・復元確認と、HEAD bundle/限定SQL backupを区別し、保存先/日時/復元可能性を記録する。
- [ ] Web版は対応範囲のread-only調査まで。現在のiPhone修復を優先し、Web実装/公開・有料契約へ先行しない。TestFlight期間はSupabase Free、プラン要否は公開直前に再検討する。

### ユーザー操作・外部条件が必要

- [ ] Macの既存未保存差分を保持し、正規device_dayによるRelease上書き・起動結果を確認する。Bundle ID `com.skworks.skWorks`、既存アプリ削除なし、Debug/flutter runなし。
- [ ] iPhoneの信頼/署名状態を確認し、実起動後にログイン・帳票・承認・給与・経費・LINE操作を試す。クラウドが端末を直接操作済みとは説明しない。
- [ ] 本人の認証付きアプリUIでTXT/ZIP取込、月別数量・訂正・単価・宛先確認、正式下書き/承認/発行を行う。特権SQLで本人になりすまして保存/承認しない。
- [ ] Apple Developer承認、契約/署名、App Store Connect、TestFlight配布と複数権限/複数端末試験。Master端末登録成功も本人実機確認まで未完了。

### この整理の範囲

- Issue現在節と前回スナップショットのみ更新。コード・DB・Edge・権限・PR・main・インストールは変更しない。
- 最新main CI成功と導入可能通知は確認済み。最新Release実機起動、LINE全月請求の確定、一般非開放、全面セキュリティ、TestFlight完了は先取りしない。

<!-- SKO_CURRENT_STATUS_END -->

<!-- SKO_STATUS_ARCHIVE_20261014_0807 -->
<details>
<summary>過去スナップショット：2026-10-14 08:07 JST</summary>

## 現在のやること一覧（2026-10-14 08:07 JST）

> この節を最新状況の正とする。旧節・コメントは当時の履歴として保持する。  
> **コード保存、PR CI、main統合、main CI、本番反映、導入SHA付きReleaseログ、機能別実機確認、TestFlight試験を別々に判定する。**

### 完了済み

- [x] 最新main：`eed5175218294eb2b20916bf7506510fd757fee1`（#1012統合）、tree `88f1c8161b4e177331feb3001ce36bc8ac61919b`。
- [x] 前回作業中の #961/#964/#965/#966/#967/#968 はmain統合済み。日報の月カレンダー、書類文字縮小、経費5段階確認・撮影、天気表示、内部取引先の一覧除外等を未保存作業へ戻さない。
- [x] 請求書 #983：iPhone標準PDFKitによる元PDF直接表示を全9CI成功後に統合。#995：名字設定入口・承認中ガード・RPC結果確認・保存承認再読込を全10CI成功後に統合。実機白紙解消と承認成功は別途未確認。
- [x] 経費 #982/#985/#990：確認済み白いカード、編集/取り下げ、横並び絞込み、領収書・精算方法・未設定時の入口をmain反映。精算方法は利用者の明示選択で保存し、未設定を推測補完しない。
- [x] 給与 #993 head `a8a8c26b6d735f0027c57e96c0eb8865575851db`：全14check成功後にmain統合、本番 `payroll_unit_conditions` contract_version 1反映済みとコメント照合。時間/日/月の支給・控除保存再読、実数量、旧直接額、税計算、確定snapshotの検証・既存行保持記録あり。実機未確認。
- [x] **給与担当の更新**：02:36 JSTのユーザー指示で単位別UI/既存保存接続はWork着手へ変更され、#993で実装済み。旧#944の未接続部品/Mac待ちへ戻さない。税率・他担当の計算差分や未保存差分は保持する。
- [x] LINE：公式参加一覧の実機更新成功、既存「すみだ建設出勤」への写真保存/連携成功、本番origin=lineの実投稿と投稿者/日時を確認。05:03 JSTにユーザー「SKOの方に文字出た」と報告。第1段階の実受信・本文表示成功を未完了へ戻さない。
- [x] LINE #1005送信backendと #1006作成起点metadataはmain/本番反映済み。新規投稿outbox・冪等retry・送信名設定、同group ID共有、LINE起点1一覧/SKO起点2一覧の基盤。アプリ画面接続・実LINE送信は別残件。
- [x] セキュリティの本番反映記録：#997初回配布のアカウント/権限制限、#998 webhookサイズ/timeout/redirect制限、#999写真Storageパス修正、#1002/#1003招待失敗ログ縮小・既存社員保持、#1007招待期限。#1009隔離MTD/デコイlabと #1010再認証境界検査資料はmain済み。本番防御全体の完了ではない。
- [x] #1011天気の間隔・雨雲レーダー・青い開いた傘、#1012現場赤/出勤方法紫の採用色は全4CI成功後に統合。ホーム全体配色案は保留。
- [x] ベータ資料 #977/#984 はmain反映、実PDF5件180頁・本文範囲/目次リンク/PNG検査記録あり。最新機能追随 #1000 は未統合。
- [x] **実機導入の確認済み範囲**：00:01 JST受領ログのソース `25d9c1d7` は署名Release build、Bundle ID、install/launch、終了コード0を確認。これより新しいmainの導入成功は未確認。

### 作業中

- [ ] 最新main push：Secret Scan `38481147614` とRoute `38481147715` 成功。Flutter `38481147622`・iOS `38481147714` は実行中。PR成功を最新mainの3CI成功として代用しない。
- [ ] #1004 head `767c6bdec1da8083d20c374b183b80bd53bef752` と #1008 head `f78c83e232ce0e1e6002573c2b0a353079114ee0` はDraft・未統合。最新headのFlutter/iOS CIは失敗。チャット最新preview、古い本文上/新規下、対象groupだけイベント更新、起点別共有一覧、送信名選択/同message ID再試行の修正・再検査が必要。
- [ ] #1015 head `07271a9f56d5e2003068c6c5e487d05bea85a22a` はセキュリティ記録UI/PDF/JSON。旧headの失敗修正後、最新Flutter/iOS検査中、Secret/Route成功。未統合、合成記録用で実監視取込は未接続。
- [ ] #1016 head `b4bea77e78fa3815749b56cecc6c1d779326a435` はDraft。設定された専用/Flutter/SQL/Secret検査成功、未統合・本番未適用。合成metadataの限定保存・通知・版管理まで。実取込、実JWT/複数接続検証、対応状態書込は残る。
- [ ] #1013隔離checkpoint、#1014単回再認証証跡候補は設定された検査成功のDraft。実インフラMTD、永続台帳/鍵復旧、primary再認証・Face ID復旧接続は未実装。
- [ ] #1000 head `64a05456ceae6d534632efdd1625889a057cf914` は最新headのFlutter/iOS/Secret/Route成功Draft。実統合仕様と本番条件の再照合・最新5PDF QA・main統合・実機閲覧は残る。
- [ ] **#996本番適用ブロック**：退勤時の正式日報サイン→取引会社ごと1人工、別数量承認不要のsourceは全15CI成功/main済み。しかしmigration要求が「Migration was declined.」で停止。07:08の本番読取も未適用を確認。権限要求を別経路で迂回せず、本番適用済みとしない。
- [ ] 最新新Releaseは未導入。請求書白紙・承認印、経費振り分け、給与6区分、チャット順序/preview、写真入替、天気・交通の修正後実機確認を継続する。
- [ ] Open PRは41件。過去の調査/隔離Draftは最新製品の未完成項目と同一視せず、旧仕様の再実装や無理な統合をしない。

### これから

- [ ] #1004/#1008の失敗ログ修正→最新head再CI→レビュー/安全な統合、#1015/#1016の保存/表示契約と権限・通知rollback・出力を照合する。
- [ ] #996は承認却下の解消に必要な方向確認後のみ本番へ進む。旧pendingを架空approved化せず、旧退勤/人工を推測補完しない。請求書自体の印影承認は維持する。
- [ ] 最新mainのFlutter/iOS完了と必要な本番反映を確認し、導入前バックアップ、署名Release、同Bundle ID `com.skworks.skWorks` の上書き/起動へ進む。
- [ ] 新Releaseで承認ボタン→保存→印影、退勤サイン→会社別請求、給与数量/内訳、経費精算/原額、3帳票のPDF/印刷/共有を実データ確認する。
- [ ] LINE新画面で共有起点/重複防止、最新本文2行、履歴閲覧位置、対象groupだけ更新を確認。SKO新規投稿からLINEへの自動送信は、氏名/ニックネーム/会社名＋固定「 from SKO」、同message ID再試行、ループ防止を確認する。
- [ ] 多層防御は06:40承認に従い隔離合成環境から継続。実監視・相関・誤検知解除・鍵/台帳復旧・実配置・費用条件は未完了。合成記録を実侵害の検知証拠と説明しない。
- [ ] **資料の最新確定仕様**：ベータ版表記を維持、固定ページ数上限を撤廃、先頭機能別目次＋分冊/末尾章追加。実機確認後の機能・操作・権限に対応章/？ヘルプを更新し、実PDF本文/A4/切れ/リンク・日英案内・実機閲覧を確認する。
- [ ] プライバシーポリシーURL・サポートURL/メール・運営会社は既存登録資産を探索照合し、無いと決めつけて作り直さない。TestFlight配布、最終修正、公開前最終確認は未完了。
- [ ] ソース/限定SQLバックアップと、DB/Storage全量・iPhone内データ・復元確認を区別し、保存先/日時/復元可能性を揃える。

### ユーザー操作・外部条件が必要

- [ ] #996の本番migration拒否について、必要な承認/方向を確認する。現時点では実行を迂回しない。
- [ ] 必要修正・検査・反映後、Macの未保存差分を保持して最新mainをff-only取得し、既存device_dayでRelease上書き。新しい導入SHA/logを確認する。
- [ ] iPhoneで上記修正の実操作と新規SKO→LINE投稿確認を行う。既存「すみだ建設出勤」と写真/連携を作り直さない。
- [ ] Apple Developer登録/契約/署名、App Store Connect/TestFlight配布条件、複数権限/複数端末試験を確認する。Master端末登録成功は本人実機確認まで未完了。

### この整理の範囲

- 最新mainの3CI全成功、最新Release導入、各不具合解消、全面セキュリティ完了、TestFlight完了を先取りしない。
- コード/未保存差分/DB/Edge/権限/マージ/インストールは今回変更しない。Issue現在節と過去スナップショット保存だけを更新する。

</details>

<!-- SKO_STATUS_ARCHIVE_20261013_0834 -->
<details>
<summary>過去スナップショット：2026-10-13 08:34 JST</summary>

## 現在のやること一覧（2026-10-13 08:34 JST）

> この節を最新状況の正とする。過去の記録は下に保持する。  
> **コード保存、PRのCI、main統合、mainのCI、本番DB/Edge反映、iPhone実機確認、TestFlight試験は別々に判定する。**

### 完了済み

- [x] 最新mainは `1e2b4d545d9aa56b0e3e86f941071ec03752830f`（PR #956統合）、treeは `7b8f122dce5c599504b4dd8516c08cb6e177f2aa`。
- [x] 前回整理後、#929・#941・#942・#943・#947・#948・#949・#950・#951・#953・#954・#955・#957・#958・#952・#956は各PRの成功CIと差分確認後にmainへ通常統合された。
- [x] #951「経費原額の帳票加算」は全11CI成功後にmain統合し、限定バックアップ後に `expense_document_original_costs` を本番へforward適用。既存行・関数・権限保持の照合記録あり。物理iPhone確認は別。
- [x] LINE第1段階 #952は全6CI成功後にmain統合。受信HMAC、再送、保存トーク閲覧、既存管理者連携入口を反映。
- [x] LINE本番webhookは旧version 12を保存後、同関数だけversion 13へ更新。ACTIVE、mainのhandler一致、署名なしPOSTがHTTP 401で署名検証へ到達することを確認。
- [x] LINE第2段階 #956は全9CI成功後にmain統合。出勤表/請求書の個別Master設定、確認済みデータ取込、初期OFF、保存データ保持、既存認証・承認・給与関数を置換しない構成を確認。
- [x] 給与・手当・日報数量→給与の保存・計算接続はMac Codex担当を維持。Workの未接続UI #944や未保存差分を、この定期整理から変更しない。

### 作業中

- [ ] 最新main `1e2b4d54…` のpush CI：Secret Scan・LINE Stage Two・SQL系・Routeは成功。Flutter CI `38322382471` は実行中、iOS CI `38322382324` は待機中。PR #956のCI成功を最新mainのFlutter/iOS成功として代用しない。
- [ ] PR #966「日報を現場別の月カレンダーと保存ID別プレビューで開く」：Open、head `434c5ec38f0c9edf0be204676991d56331dd84aa`。専用契約/Secret/Route成功、Flutter/iOS検証中。main・実機未反映。
- [ ] PR #961「経費の5段階確認・原子確定・領収書カメラ添付」：Draft、head `fe4542a19981b0fc6258514c63eadce0033608b2`。専用SQL/UI検証は成功、Flutter/iOS検証中。申請月・原子確定・写真添付の3migrationは本番未適用、実経費保存未確認。
- [ ] PR #965「請求書PDF白紙/描画待ちの再試行」：Draft、head `fdd05dc205c15416cef1d4fd221cba191a14be62`。Flutterと請求読取契約は成功、iOS/追加検証中。空描画時の再試行を追加したが、実機白紙の根本原因解消は未確認。
- [ ] PR #968「内部の自動下書き取引先を一般一覧から除外」：Draft、head `6f729195de86f9767caf78c5516b249aba83e2b6`。marker範囲・既存データ保持の専用CI成功、Flutter/iOS検証中。本番migration未適用。
- [ ] PR #967「書類登録の文字を小さめに揃える」と #964「晴れをオレンジ太陽、雨を青い傘へ統一」：Flutter/Secret/Route成功、iOS CI継続。Open・未統合・実機未確認。
- [ ] OpenWeatherは表示設定と診断まで進行。実予報取得成功は未確認。PR #962の非表示設定helperは全CI成功Draft、Macでの秘密値設定が必要。
- [ ] ルート退勤後の数量申請導線はmain反映済みだが、本番実機では取引会社/単価3件に対し数量申請0件。選択・申請・承認後の請求生成を未完了として追跡。
- [ ] LINE第1段階は本番webhook復旧済みだが、binding、署名済み実投稿、本文保存、アプリ表示は未確認。第2段階の本番migration・実JWT・実取込も未実施。

### これから

- [ ] 最新mainのFlutter/iOS CI完了を確認し、main SHAと3CI成功を結び付けて記録する。
- [ ] #966・#961・#965・#968・#967・#964の最新head CI、差分、競合を個別確認し、成功した範囲だけ安全に統合する。
- [ ] 請求書白紙の実機原因を生成・読取・font・native raster・画面寸法まで切り分け、同一PDF bytesによるプレビュー/印刷/保存/共有を実機確認する。
- [ ] ルート数量申請→承認→取引会社別請求下書きの実データ経路を確認し、取引先未設定の内部行露出修正と混同しない。
- [ ] 経費5段階フロー、申請月、領収書撮影、原子確定を本番反映前後で照合する。給与精算の給与保存/計算はMac担当境界を維持する。
- [ ] LINE第1段階は署名済み実投稿→保存→アプリ表示を確認。第2段階は本番migration/実JWT/権限別ON/OFF/確認済み出勤・請求取込を確認する。
- [ ] 本番DB/Storage/Edgeのバックアップ保存先・取得日時・復元可能性を揃え、migration/Edge deploy/main統合と区別して記録する。
- [ ] 同一Bundle ID `com.skworks.skWorks` の署名付きRelease版を既存iPhoneへ上書きし、起動・ログイン・登録データ保持を確認する。既存アプリは削除しない。
- [ ] TestFlight実機試験と最終修正が完了した証拠の後、？アイコン、ヘルプ、一般10頁・サブ管理者15頁・管理者20頁の説明書、20頁パンフレットを公開前最終版へ改訂する。

### ユーザー操作・外部条件が必要

- [ ] Macの未保存差分を対象指定stashで保持し、最新mainをff-only取得して `tool/device_day.sh` でRelease上書きする。
- [ ] iPhoneで請求書白紙、日報月カレンダー、書類文字、天気アイコン/実予報、交通、ルート数量申請、経費、LINE表示を実データで確認する。
- [ ] OpenWeather/住所変換に必要な設定値をMacから非表示入力し、秘密値をチャットやログへ貼らず取得成功を確認する。
- [ ] LINE公式アカウントとのbinding後、署名済み実投稿を行い、保存本文とアプリ表示を確認する。
- [ ] Apple Developer会社登録、契約・署名、App Store Connect、TestFlight配布、複数権限/複数端末試験。
- [ ] Master初回端末登録は通常の会社管理者権限と区別し、SKO運営者専用Master本人の実機登録成功まで完了扱いにしない。

### 完了扱いにしないもの

- 最新mainのFlutter/iOS CIは進行中。
- Open PRのコード保存や一部CI成功は、main統合・本番反映・実機成功を意味しない。
- LINE webhook ACTIVE/署名なし401は、binding・実投稿・本文保存・アプリ表示の成功を意味しない。
- 最新mainのiPhone Release上書きと今回の実機不具合確認は未実施。
- TestFlight実機試験、アプリ最終修正、公開前資料の最終改訂は未完了。

</details>

<!-- SKO_STATUS_ARCHIVE_20261012_0857 -->
<details>
<summary>過去スナップショット：2026-10-12 08:57 JST</summary>

## 現在のやること一覧（2026-10-12 08:57 JST）

> この節を最新状況の正とする。過去の記録は下に保持する。  
> **コード保存、PRのCI、main統合、mainのCI、本番DB/Storage反映、iPhone実機確認、TestFlight試験は別々に判定する。**

### 完了済み

- [x] 最新mainは `15c80dd05165dd68231fce00d1e35424a34ff022`（PR #940統合）、treeは `dc9635f6310415f3e42cc08cf3e3f279494b9419`。#940の全4CI成功headと同一tree。
- [x] 最新main自身のpush CIは成功：Flutter CI `38183483623`、iOS CI `38183483527`、Secret Scan `38183483635`、Route visit reports check `38183483585`。
- [x] #930〜#940のうち統合対象はmainへ通常マージ済み。主な最新統合は、必要書類設定導線、ルート到着/移動/退勤と履歴復旧、GPS数値再表現、経費振り分けUI、TOPスクロール、必要書類共用、社員個別情報、取引/協力会社リンク、会社書類写真操作、個別給与UI整理。
- [x] 本番反映と照合が記録されたDB範囲：#931 `route_final_visit_clock_out`、#932 `archived_attendance_capture_recovery`、#936 `worker_document_shared_scope`、#937 `employee_personnel_read_view`、#938の会社代表者情報/リンク用migration。既存行hash・権限・保護関数の照合記録を保持。
- [x] PR #940は表示/UI範囲のみ完了。給与保存・serialization、Repository、DB、給与計算、日報、帳票は変更していない。
- [x] 給与・手当・日報数量→給与の実装担当はMac Codexへ一本化。Work側の未保存差分は保持し、この定期整理からコード/DB変更を開始しない。

### 作業中

- [ ] PR #941「TOPボタンが持ち手追加で縮む表示崩れを修正」：Draft、head `90a9524d8071bd9c59c07f914cb7b505ac950137`。Flutter/Secret/Routeは成功、iOS CIは実行中。ヘッダー未変更、実機未確認。
- [ ] PR #942「必要書類の共通選択と撮影画面の日本語対応」：Draft、head `e8b31ef710d018a9ce6c1a6da7871cdd078b7835`。Secret/Routeは成功、Flutter/iOS CIは実行中。既存の別ID同名書類は自動統合・削除せず、実機の日本語表示は未確認。
- [ ] PR #929「取引会社別請求数量の承認」：Draft、head `c77e02572e7f8708d3c4991c0d0638d81d58724b`、全7CI成功。ただし請求書明細への数量/承認単価接続、既存計算方式との整合、未承認時の確定防止、通常退勤後の申請、古い送信識別、本番導入が未完成。
- [ ] Open PRは34件。上記3件以外の多くは過去のDraft/調査/隔離検証であり、最新mainへの統合候補・本番反映済み・実機完了とは扱わない。
- [ ] 個別給与の時間/日/月自由追加、日報表示チェック、数量・給与接続は未実装でMac担当。#940のUI統合を給与機能全体の完了とは扱わない。

### これから

- [ ] #941/#942は各最新headの全CI結果と差分を確認し、成功・レビュー完了後だけ最新mainへ安全に統合する。
- [ ] #929の請求数量・承認単価・確定防止・通常退勤後申請を完成させ、隔離fixture成功と本番導入を分けて確認する。
- [ ] 経費の現金/給与精算の永続化と、取引会社/下請け会社分を請求書・支払証明書へ福利厚生費/消費税なしで別途加算する接続を完成する。給与側接続はMac担当境界を維持する。
- [ ] LINEトーク第1段階（既存受信復旧・閲覧・実投稿保存）と第2段階（出勤表/請求書の個別ON/OFF・抽出/修正/集計/再取込）を継続する。
- [ ] 本番DB/Storageバックアップの保存先・取得日時・復元可能性を確認し、migration適用記録とソース統合を混同しない。
- [ ] 同一Bundle ID `com.skworks.skWorks` の署名付きRelease版を既存iPhoneへ上書きし、起動・ログイン・登録データ保持を確認する。既存アプリは削除しない。
- [ ] 実機でTOP 1〜4列、書類共通選択/撮影日本語、GPS/写真ルート、経費、社員/会社情報、3帳票の角印・金額・PDF/印刷/共有を確認する。
- [ ] TestFlight実機試験と最終修正が完了した証拠の後、？アイコン、ヘルプ、一般10頁・サブ管理者15頁・管理者20頁の説明書、20頁パンフレットを「公開前最終版」として改訂する。ベータ版更新とは区別する。

### ユーザー操作・外部条件が必要

- [ ] Macの未保存差分を対象指定stashで保持し、最新mainをff-only取得して既存 `tool/device_day.sh` を実行する。クラウドからMac/iPhone操作済みとは扱わない。
- [ ] 接続済みiPhoneでRelease上書き後、ログイン維持、実GPS/写真、権限別表示、通知遷移、帳票表示・印刷・共有をユーザー操作で確認する。
- [ ] Apple Developer会社登録、契約・署名、App Store Connect、TestFlight配布、複数権限/複数端末試験。
- [ ] Master初回端末登録は通常の会社管理者権限とは別のSKO運営者専用権限として扱い、登録成功を実機で確認するまで完了扱いにしない。

### 完了扱いにしないもの

- #941/#942はDraft・未統合で、実機確認も未実施。
- #929はCI成功済みでも請求接続と本番導入が未完成。
- 最新mainのiPhone Release上書き、実機ログイン、今回の画面/帳票確認は未実施。
- TestFlight実機試験、アプリ最終修正、公開前資料の最終改訂は未完了。

</details>

<!-- SKO_STATUS_ARCHIVE_20261011_0824 -->
<details>
<summary>過去スナップショット：2026-10-11 08:24 JST</summary>

## 現在のやること一覧（2026-10-11 08:24 JST）

> この節を最新状況の正とする。過去の記録は下に保持する。  
> **コード保存、PRのCI、main統合、mainのCI、本番DB/Storage反映、iPhone実機確認、TestFlight試験は別々に判定する。**

### 完了済み

- [x] 最新mainは `041064401afa5608fe0a50db77e0921b6e09e07f`（PR #901統合）。
- [x] PR #897（ルート到着・移動時刻）head `0cae8702817b5fd938c6c51cbcc9870dc22ce2d8` は全7CI成功後にmain統合。
- [x] PR #898（ホームの現場到着/移動、日報の実時刻・現場名、新規支払証明書の角印preview）head `845423e5658f7c9b8bc9179ff8101c7cec32761f` は全9CI成功後にmain統合。
- [x] PR #896（会社書類の複数写真）head `4e550d70b7673c232cb400a866c64333654532a7` は全7CI成功後にmain統合。
- [x] PR #900（必要書類の複数写真）head `bbe839e84f86edc871a519d0505df3841b337a35` は全7CI成功後にmain統合。
- [x] PR #899（資格の追加写真、保存履歴、会社間送信）head `26d0d14d1fe56de61b4b8507ea5ac40e0dff717b` は全7CI成功後にmain統合。
- [x] PR #901（本人の保存済み資格写真previewと上記変更の最終統合）head `97a8b2fc346b8101909243e1d11522d39560ba16` は全9CI成功後にmain統合。
- [x] 最新main tree `7d84aa1580cea6883a29cb212a3db2d2fb8db37a` は、最終統合CI成功head #901のtreeと一致。統合状態でFlutter Test 1326件、Release gate、再テスト1297成功/29既存skip、Android build、iOS Analyze/Test/Release unsigned build成功。
- [x] 既存の経費・税率・PNG角印のソース、本番反映済み範囲、以前のRelease実機確認を保持。今回の整理ではコード、DB、Storage、マージ、インストールを行っていない。
- [x] 給与・手当・日報数量→給与の実装担当はMac Codexへ一本化。Work側の未保存差分は保持し、この定期整理からコード/DB変更を開始しない。

### 作業中

- [ ] 最新main `041064401afa5608fe0a50db77e0921b6e09e07f` のpush CI：Secret Scan `38094558333` は成功。Flutter CI `38094558332` とiOS CI `38094558322` は実行中。**個別PRのCI成功を最新mainの3CI成功として代用しない。**
- [ ] PR #868（友達画面の日英対応）head `7258400b770b9b66596b9aa171facaa61106c538` はOpen・未統合。PR上のFlutter/iOS/Secret Scanは成功済みだが、古いmain起点のため最新mainへの再照合が必要。
- [ ] PR #869（チャット背景・透明度の日英対応）head `df8c714f101ae338d7304477fd67a7f31427c60f` はOpen・未統合。PR上のFlutter/iOS/Secret Scanは成功済みだが、古いmain起点のため最新mainへの再照合が必要。
- [ ] 本人資格は保存済み表/裏/追加写真のpreviewと既存テキスト登録保護まで。本人による写真の追加・差替・削除保存は未完成で、停止表示を維持。
- [ ] 本番Storageの既存upload pilot制限を維持。資格・必要書類・会社書類の全種類で実upload成功した状態とは扱わない。

### これから

- [ ] 最新mainのFlutter CI・iOS CI完了を確認し、3CI成功をmain SHAと結び付けて記録する。
- [ ] 本番DBとStorageの写真/PDF実体について、バックアップ日時・保存先・復元確認を揃える。Macのソースバックアップだけで代用しない。
- [ ] バックアップ確認後、既存ledger差を壊さず、次の新migrationだけをforward順で個別適用する：`route_manual_visit_capture` → `add_qualification_certificate_extra_photos` → `company_document_photo_sets` → `worker_document_multiple_photos` → `protect_qualification_photo_snapshots` → `send_qualification_extra_photo_snapshots`。
- [ ] migration適用前後で既存申請、資格、書類、給与、請求書、支払証明書、確定帳票snapshot、Storage objectの保持を照合する。全db push、旧migration再適用、ledger repair、旧写真の物理削除は行わない。
- [ ] main統合・本番準備・CI確認後、同一Bundle ID `com.skworks.skWorks` のRelease版を既存iPhoneへ上書きし、起動とログイン維持を確認する。
- [ ] 実機で、現場到着→現場終了→次現場→退勤、実GPS/写真、日報表示、書類複数写真の保存/再表示、3帳票の角印preview/PDF/印刷/共有、税率/経費メニュー、給与一覧を確認する。
- [ ] TestFlight実機試験と最終修正が完了した証拠の後、？アイコン、ヘルプ、一般10頁・サブ管理者15頁・管理者20頁の説明書、20頁パンフレットを「公開前最終版」として改訂する。ベータ版資料更新とは区別する。

### ユーザー操作・外部条件が必要

- [ ] Mac上で本番DB/Storageバックアップの保存先と復元可能性を確認する。
- [ ] バックアップと本番migrationの確認後、Macと接続済みiPhoneでRelease版を上書きし、実機操作を行う。既存SKOアプリは削除しない。
- [ ] 実際の写真・GPS・経費・会社/従業員条件を使う確認は、架空の本番業務データを登録せずユーザー操作で実施する。
- [ ] Apple Developer会社登録、契約・署名、App Store Connect、TestFlight配布・複数権限/複数端末試験。
- [ ] Master初回端末登録は通常の会社管理者権限とは別のSKO運営者専用権限として扱い、登録成功を実機で確認するまで完了扱いにしない。

### 完了扱いにしないもの

- 最新mainのFlutter/iOS CIは現在実行中。
- 新migrationとStorage変更は本番未適用。
- 最新mainのiPhone Release上書き、実機ログイン、複数写真upload、ルート実運用、3帳票角印の実機確認は未実施。
- TestFlightの実機試験とアプリ最終修正、公開前資料の最終改訂は未完了。

</details>

<details>
<summary>過去スナップショット：2026-10-10 12:10 JST</summary>

<!-- SKO_STATUS_ARCHIVE_20261010_1210 -->
## 現在のやること一覧（2026-10-10 12:10 JST・給与担当変更反映）

> この節を最新状況の正とする。以下の過去履歴は保持する。  
> **コード保存・CI成功・main統合・Release導入・実機確認は別々に判定する。**

### 担当境界（ユーザー承認済み・最優先）

- [x] **給与関連はMacのCodexへ一本化**。専用ブランチ `codex/payroll-tax-connection` で、**税率設定 → 給与計算式 → 給与明細**の接続を最優先に進める。
- [x] **Work側は給与・手当・日報数量→給与に関するコード/DB変更を停止**。定期整理から実装・migration・本番データ変更・マージ・Release導入を開始しない。
- [x] **Work側に残る未保存差分はそのまま保持**。reset / stash / 上書き / 削除 / 別ブランチへの混入を行わない。未保存差分を「GitHub保存済み」「main統合済み」と扱わない。
- [x] 経費実装は未編集の分離ブランチを保持したまま保留。給与優先中に並行着手しない。

### 完了済み（確認できた事実）

- [x] 最新mainは `80651bfb2fd28eee2398451bb8a0883acfb07aee`（PR #877統合）。
- [x] 最新mainの3CI成功：Flutter CI `38017808050`、iOS CI `38017808066`、Secret Scan `38017808197`。
- [x] PR #876 / #877 はmain統合済み。所得税の公式資料リンクの外部起動失敗を復旧。
- [x] main `80651bfb` のRelease版を同一Bundle IDで上書き導入し起動成功。Flutter analyze指摘なし、テスト1148成功・既存skip28。
- [x] iPhone実機で「税率設定 → 所得税 → 年度/PDF管理 → 国税庁公式資料」を開き、2026年源泉徴収税額表PDF表示、関連資料ページ表示、戻る操作を確認。
- [x] 既存の帳票、給与snapshot、認証・権限・RLS、登録データを保持。今回の担当変更整理ではコード・DB・本番データを変更していない。

### 作業中（担当を混同しない）

- [ ] PR #868（友達画面の日英対応）head `7258400b770b9b66596b9aa171facaa61106c538` はOpen・未統合。Flutter / iOS / Secret Scanは成功。
- [ ] PR #869（チャット背景・透明度の日英対応）head `df8c714f101ae338d7304477fd67a7f31427c60f` はOpen・未統合。Flutter / iOS / Secret Scanは成功。
- [ ] **Work側給与レーンは停止中**。未保存差分を保持するだけで、整理作業から再開しない。

### これから

- [ ] 完成した給与変更だけを通常PRで安全にmainへ統合する。古いtreeでmain全体を置換しない。
- [ ] main統合後にRelease版を同一Bundle IDで上書きし、実機で税率設定 → 給与計算 → 明細表示/PDF/印刷/共有を確認する。
- [ ] TestFlight前の実機試験、ベータ版ヘルプ/説明書、通知から承認ページへの直感的導線を最終確認する。
専用セキュリティ追加・Web版は着手しない。公開前資料は開始指示時に整理する。

### 未完了として明確に保持

- [ ] 実会社の税率・所得税表を使った給与計算と給与明細への正式接続。
- [ ] 実データでの給与確定、過去明細不変、再表示、PDF/印刷/共有一致のE2E。
- [ ] Work側未保存差分の内容確認・GitHub保存・破棄判断（現時点は**保持のみ**）。
- [ ] PR #868 / #869の最新mainへのrestack、統合、統合後main CI、Release実機確認。
- [ ] TestFlight配布と複数権限・複数端末での実機試験。
- [ ] Apple Developer / App Store Connectの外部手続き、Master初回端末登録の実機成功確認。

### ユーザー操作・外部条件が必要

- [ ] Apple Developer審査・契約・証明書・App Store Connectで必要となる外部操作。
- [ ] Master端末登録は通常の会社管理者権限とは別のSKO運営者専用権限として扱い、勝手な権限付与・登録・ロック解除・復旧メール送信を行わない。

<!-- /SKO_STATUS_ARCHIVE_20261010_1210 -->

</details>


<details>
<summary>旧CURRENT_STATUS節（2026-10-09 08:35 JSTの履歴）</summary>

<!-- SKO_ARCHIVED_STATUS_20261009_0835_START -->

## 現在のやること一覧（2026-10-09 08:35 JST確認）
この節はGitHubの実在するmain・Open PR・CIと最新コメントを照合した整理です。上の08:04節と下の記録は各時点の履歴として保持します。ソース保存、CI成功、main統合、本番適用、実機確認を分けて扱います。

### 完了済み（ソース統合・確認済みCI）
- [x] 最新main `8681eb3149f26e3376ddad2799817c908df0ed12`。同SHAのmain push **Flutter CI 37857361257／iOS CI 37857361272／Secret Scan 37857361175はすべて成功**。CIの成功は署名済み実機導入・TestFlight試験完了を意味しません。
- [x] #801 通知再送の永続保存：最終head `92a839537276bf661fd3ff493584ebc3e3da80f9`、merge `d5ec4f16d527f1e2fb047e3a49e78833331a26dc`。最終PRの3CI成功・独立レビュー後main統合を最新コメントとPRで確認。登録済み日報の会社・本人・固定IDを保持し、日報を再INSERTせず通知だけ再試行。実機再起動・通信失敗時の通し操作は未確認。
- [x] #802 親子会社の共有提案・内訳差異表示：最終head `a687d88022ccab1a24b430e211d8c6a925ffa652`、上記mainへ統合。最終PRの3CI成功・レビュー記録あり。各社の元データを上書きせず、数値一致を双方合意と混同しない。実機操作は未確認。
- [x] 帳票・ベータ資料：採用請求書v8／給与明細v4の見本・再生成資材、3帳票の共通角印ON/OFF、福利厚生費率、ベータ資料4種65ページの保存・検証記録あり。#788/#793 有給給与連携、#791/#795 現場別提案・双方確認・追加枠と手動税理由、#797/#800 会社情報snapshot・印影重なり修正はmain統合済みとの最新記録。全組合せの実機確認、角印5書体、公開前最終資料改訂とは別。
- [x] #782/#785/#786/#789/#794/#799 GPS・写真・日報・車両・通知のソースと隔離検証を統合済みとの記録。途中現場の生証跡・固定ID・競合検証の範囲を維持。新bucketの保持／削除連携、本番新migration、rollout ON、実機完成とは扱わない。
- [x] #792/#796 車両通知先1〜3名・初期1名提案・停止受信者の制限はソース統合済みとの記録。通常のrole・選択・台帳を保持し、一般管理権限付与と混同しない。

### 作業中（保存済み・未統合／未完了）
- [ ] **#803 双方確認済み現場別帳票の導線**：draft、head `fecafd60660b727f49b65eb47039ad110c0d8c75`。Flutter 37856458240／iOS 37856458180／Secret Scan 37856458192は全成功。Open PRのため**まだmain未統合**。対象会社限定・タップ時snapshot取得・旧月次帳票との分離・独立レビュー／実機導線の確認を継続。
- [ ] **#804 作成済み利用機能ON/OFFを既存本人限定Master設定へ保管**：draft、head `daa20d5357d584f57ae078d616d61dd32ba89c82`。Flutter 37859609463（PR）／37859604785（push）は失敗、iOS 37859609418は実行中、Secret Scanは成功。未統合・実機未確認。失敗修正は実装担当が行い、この整理ではコード修正・再CI・マージをしない。
- [ ] #804の最新仕様は08:25／08:27コメントを優先：Masterはユーザー本人IDのみが利用できる既存運営管理設定。作成済みON/OFFは用途保留・保管中、公開範囲やアプリ全体提供切替が確定したとは扱わない。既存会社別設定をglobalへ変換しない。新Master権限付与・DB/Auth/RLS変更なし。
- [ ] 会社管理者による個人別の担当・業務操作権限はMaster保管機能と別。サブ管理者という肩書きだけで一律全業務を許可しない。Aさん／Bさん／一般ユーザーへの必要範囲だけの割当、閲覧／編集／確認承認のserver側整合を確認する。
- [ ] その他Open PR（#754/#755/#757/#758/#760〜#765/#767〜#771/#773/#776〜#779/#783）は保存・監査・設計／staged実装の履歴を含む。新しい統合PRに内容を取り込んでいるものと、未統合のものを個別照合し、Openであることだけで全実装未完成／統合済みのどちらにも決めつけない。#322は将来動画会議の別課題。
- [ ] 保存直後の再読込失敗・通知0件・RPC不在・再起動、親子会社の数値差・合意状態・月次帳票との分離、途中現場の証跡と保持／回収の残る境界を確認。未保存ローカル作業はこの整理で確認できていない。

### これから（前提を満たして進める）
- [ ] 新migrationの依存・本番実定義・既存データsnapshot・復旧手順・全体連携の確認。既存GPS本番適用記録と、今回の新staged migration未適用を区別する。検証未完了のrolloutはOFFを維持。
- [ ] 出勤・夜勤／月末・休み・有給・給与設定・請求／支払・確認者1〜3名／初期管理者1名・通知から対象ID／月へ進む導線を実機で通し確認。通知の既読と確認／承認完了は別管理。
- [ ] 新外部メール送信基盤・送信元確認・実送信、本人アカウント削除全体・保持分類は未完了。隔離183件の成功を実削除完了と扱わない。
- [ ] TestFlight実機試験と最終アプリ修正が完了した証拠の後、？アイコン・ヘルプ・一般10頁／サブ管理者15頁／管理者20頁説明書・20頁パンフレットの公開前最終改訂。ベータ改訂とは別。英語画面・日本語PDF案内・実PDF全文／A4／文字切れ・同一配布ファイルの版更新を確認。
- [ ] GPS・日報・通知・Releaseを優先。**セキュリティ追加実装とWeb制作はまだ開始しない**との現在の指示を保持。古い「セキュリティ→Web」記録で現在指示を上書きしない。

### ユーザー操作／外部確認が必要
- [ ] Macでデータバックアップ確認・ソース／署名設定退避後、Releaseのみ・同Bundle ID `com.skworks.skWorks` で既存SKOへ上書き。Flutter 3.47.5／ユーザーMac Xcode 27.0／iOS Target 15.5を維持。Debug・flutter run・既存アプリ削除・無断差分破棄は不可。
- [ ] 過去のRelease上書き・起動と3帳票プレビューはユーザーログ／画像の記録あり。**今回追加変更の最新iPhone導入は新成功ログ未受領**。ケーブルなし起動、GPS撮影、日報、通知、給与、請求・支払、印刷／共有、日英を実機で確認する。
- [ ] Apple Developer会社登録・署名・TestFlightアップロード／配布。登録や試験完了の証拠は未確認。
- [ ] 本物の角印5書体のアプリ組込み・電子印影利用許諾／日本語字形。現行の自動印影・ON/OFFとは別。5種類選択・5比較PDFは未完成。購入／業者連絡未実施。
- [ ] 管理者マスター初回端末登録案内は現在作業が落ち着いた後。通常会社管理者とSKO運営者専用Masterを区別。案内済み／実機登録成功は未確認。こちらから権限付与・登録・ロック解除・復旧メール送信をしない。

今回の整理ではIssue本文だけを更新し、コード修正・本番DB変更・マージ・インストールは実行しません。

<!-- SKO_ARCHIVED_STATUS_20261009_0835_END -->

</details>

<details>
<summary>旧CURRENT_STATUS節（2026-10-08の履歴・現在の状態ではありません）</summary>

!-- SKO_ARCHIVED_STATUS_20261008_START -->

## 現在のやること一覧（2026-10-08 更新）
この節が現在地点です。下の記録は過去の状態であり、古い未チェックやSHAを現在の状態と扱いません。

### 完了・保存済み
- PR #745〜#748はmain統合済み。最新mainは `b65c0efe7c013737f9294cf7783061ae3661f8e6`。#747/#748各最終HEADのFlutter CI・iOS CI・Secret Scan成功。
- 採用帳票見本・再生成ファイル、給与／請求／支払の保存額・実SQL／実PDF検証、ベータ資料4種65ページを保存。全組合せの実機確認とは区別。
- 同一Bundle ID `com.skworks.skWorks` のRelease上書き導入成功と3帳票プレビューはユーザー画像で確認。今回#750の導入コマンドは案内済み（解析設定とiOS署名設定を退避、最新main取得、Release上書き）。今回更新の実機インストール成功はまだ未確認。iPhoneの暗号化バックアップ確認はソース退避とは別。

### 今回の統合：PR #750
- ブランチ `fix/company-seal-controls-20261008`、HEAD `670f2c9c6b38887e4d0c99adb895ce91f5df878d`。最終HEADの3CI成功、mainへ統合済み。mainツリー `b44d86281687071b11ded75cf4b7c92604e59a68` は検証済みHEADと一致。mainの追加Flutter CI・Secret Scan成功。iOS追加run #37750111949は開始前にjobがcancelled、step/logなしでrun failure。コードを変更せず該当jobだけ再実行したが、attempt 2もstep/logなしでcancelled。原因注記は連携API非対応、ブラウザー確認はタイムアウトで未取得。PR最終HEADのiOS CI成功とは区別し、main追加iOS成功とは扱わない。
- 会社データの「会社角印」に共通ON／OFFを実装し、3帳票へ接続。OFFでも会社情報・金額・配置・個人の確認／承認印・履歴を保持。
- 福利厚生費率を消費税率と同じ単価欄へ表示、請求書の用紙を白に修正。給与形態が未登録の旧明細で空文字FittedBoxによるPDF停止を修正。
- 日英表示、？ヘルプ、管理者説明書・パンフレットを更新。画面を開いたままの言語切替テスト追加。
- 実Flutter生成のON／OFF各3帳票・福利厚生費率・管理者説明書20頁・パンフレット20頁を `docs/adopted_reports/generated/cc8997a/` に保存。9ファイルのGitHub実在とバイナリ一致、A4・金額・個人印保持・描画を確認。
- 最終レビューで他社所有者の直接UPDATE検証が正常時に走らない分岐を修正。修正後の隔離PostgreSQL権限／他社分離／金額と履歴不変テスト成功。製品コードの独立レビューも完了。最新HEADのFlutter CI・iOS CI・Secret Scanは成功。
- 本番migration `20261008082754 company_seal_visibility` を適用。会社・給与・請求・承認状態・両履歴の反映前後の集約ハッシュ一致。既存2関数は表示キーを除いて元の定義と完全一致。RLS維持、anon実行不可、新設定は既存会社すべてON。実会社のON／OFFを試験目的で変更していない。
- セキュリティ監査では既存の指摘件数を維持し、追加された2つの認証済み実行可能RPCは権限判定済みの読取／保存用関数。匿名公開は増えていない。

### 未完了：角印5種類
- 確定仕様：篆書体／印相体／古印体／隷書体／古印体の別配置。会社管理者の会社設定1か所で選び、登録会社名から3帳票へ共通生成。
- 実フォントのアプリ組込み・電子印影許諾が未確保。5選択と5比較PDFは未完成。ON／OFF比較PDFを5書体見本として扱わない。
- 未採用nisetenは#750に含めない。#749は未採用書体を統合せず、表示修正を#750へ引き継いで閉鎖。

### 作業環境の進め方（2026-10-08 17:21 ユーザー確認）
- タブレットのWorkで可能なコード・計算検証・帳票・資料・GitHub／CI・TestFlight前と公開前の準備を先に進める。
- MacBookが必要なXcode署名・iPhone Release導入・TestFlightアップロードの段階だけ、具体的な操作を案内。Mac側Codexが必要なら、その対象作業を明示する。
- タブレットからMac／iPhoneを直接操作できると案内しない。Apple側の登録・審査・実機結果と、こちらの保存・検証完了を区別する。

### 次に進める順番
1. #750の3CI・本番反映・main統合・保存確認は完了。mainの追加iOS CIは再実行も開始前cancelled。原因を確認できるまでコードやチェック条件を変えて成功扱いにしない。
2. MacでiPhoneデータのバックアップ確認、署名設定／ソースの退避を保持し、Releaseを既存SKOへ上書き。Debug・flutter run・アプリ削除はしない。
3. 実機でON／OFF、請求書％・色、給与・出勤・通知・日英、印刷／共有・ケーブルなし起動を確認。
4. 実書体の許諾確保後に5選択・実PDF比較を完成。TestFlight・公開前最終資料更新へ継続。

### 公開準備のソース保存：PR #751（2026-10-08 21:15更新）
- PR #751 / HEAD `f110bdb22e79c9b4f3a0db9515115482e0b96299` はmainへ統合済み。main `6e74cd2e5a45a7505d5c2df850122adadf4d1c92` のツリーは検証済みHEADと一致。
- Edge2配布物32モジュール・2manifest・関連28定義／ACL・README・隔離テスト・専用CIの計39ファイルを保存。mainの全39ファイルのblob hashとローカル保存物の一致を確認。
- 最終HEADのFlutter CI #37753477875、専用archive check（PR #37753478117／push #37753472215）、Secret Scan（PR #37753478055／push #37753472127）すべて成功。アプリ／iOSコードは変更しておらず、このPRのiOS CIは起動対象外。
- 架空データ／注入モックの59件試験成功、通信試行ゼロ。本人／session照合・AMR再認証・明示確認・停止フラグ・入力バイト境界・worker拒否とステータスを検証。専用CIでmanifest照合と隔離試験を継続実行する。
- 参照ソース保存と入口のモック試験の完了。実削除ライフサイクル・保持分類・外部資格情報／署名URL失効・完了通知・本人UIは未完了。受付／実行フラグfalseを維持。デプロイ・削除申請・削除・メール送信は実施していない。

### 隔離processor検証：PR #752（2026-10-08 21:40更新）
- main統合済み PR #752 / HEAD `365a915eb9342b0b8384acd37d5f024a2ff7d01c`。既存参照processorを架空jobとメモリ内portsで検証。124件追加、既存59件と合計183件成功、通信試行0。
- 8工程順序、資格再確認、各工程・renew・checkpoint失敗後の停止、完了済みprefix再開、checkpoint喪失後の同一idempotencyキー、完了false／異常planを確認。
- 4ファイル保存：追加テストと検証説明、専用CI対象拡張、公開準備docの保存範囲修正。アプリ・iOS・DB・原本を変更せず、実運用受付／実行を有効化しない。専用archive check（PR #37776160813／push #37776124802）とSecret Scan（PR #37776160648／push #37776124954）成功。Flutter CI #37776160618成功。main `b65c0efe7c013737f9294cf7783061ae3661f8e6` へ統合し、ツリーは検証済みHEADと一致。4ファイルの保存blob照合済み。iOS CIはアプリ／iOS変更がないため起動対象外。
- main #751後の専用archive check #37775611385とSecret Scan #37775611375成功、Flutter CI #37775611617成功。CIのDebug APKは検証成果物であり、iPhoneへの導入ではない。

### 次の独立監査
- 日報に紐づかないGPS夜勤の翌朝退勤を、勤務日付／月末・年末境界と出勤表・給与への連携の観点でソース監査開始。DBや登録データの変更なし。既存解決済みなら重複実装しない。

### 別管理の残作業
- 日給／時給の有給支給額と通常勤務の夜間時間割増は登録会社方針が未確定。勝手な金額を導入しない。
- Apple Developer登録完了待ち。公開プライバシーURL・収集ラベル・削除経路・実Release成果物監査・掲載スクリーンショット・審査アクセス・署名／アップロードは未完了。
- 公開準備の追加ソース監査：プロフィールの本人アカウント削除開始ボタン／本人確認／実行・完了経路は未実装。サービスキー限定の検査コードは読み取り専用で、削除機能完成とは扱わない。本番を読み取り棚卸しし、privateの削除ジョブ・申請・保持証跡など12テーブルとサービス専用RPCが実在することを確認。申請／状況／削除実行系RPCはauthenticated・anon直接実行不可。デプロイ済みEdge v3には本人／session照合、10分以内の再認証、本人状況GETと明示確認POSTがある。申請・実行のコード内検証フラグはfalseで意図的に無効。会社唯一のowner/adminは後任引継ぎが必要で、正式書類の種類別保持分類も未確定。デプロイ済み基盤ソースは#751でGitHubへ保存済み。隔離環境で保持・再実行・古いJWT／署名URL拒否を検証した後、本人プロフィールの説明／状況／申請経路へ接続する。直接RPC公開や実運用有効化はしていない。今回の監査では削除・登録データ変更を実行していない。
- Master初回端末登録案内は未実施、実機登録成功も未確認。通常会社管理者とSKO運営者専用Masterを区別。帳票作業が落ち着いてから案内する。こちらから権限付与／登録／ロック解除／復旧メール送信はしない。

<!-- SKO_ARCHIVED_STATUS_20261008_END -->

</details>

---

## 過去の更新履歴（以下の進捗は当時の記録）

### PDF空欄描画の修正・再CI（2026-10-08 16:45）
- PR #750 head cc8997a24fd36a9cac4acf4a0707abe6165b9b5a。給与形態が未登録の旧明細で、幅0の空文字をFittedBoxへ渡してPDF生成が停止する問題を修正。
- 比較テストのデータを埋めて隠す対応ではなく、実際の空欄明細の描画処理を修正。ON／OFF各3帳票・個人印・金額・座標の実PDFテストを再実行中。
- main未統合／新migration本番未適用／今回更新の実機インストール未実施。5種類実書体は許諾待ちで未完成。

### 会社角印表示の実装・CI（2026-10-08 16:32）
- PR #750 / head 3d076c81ccbbe56f341d26d31a28f242806d136d：会社角印共通ON／OFF、会社データUI、3帳票への設定接続、英語・？ヘルプ、請求書福利厚生費単価欄％・白い用紙を保存。
- 隔離PostgreSQLの権限・他社分離・直接更新制限・金額・実確認日時の不変チェック成功。最新本番の2関数定義と照合し、新しいJSONキー以外同じ。新migration本番未適用。
- 3CI・3帳票各ON／OFF実PDF・main統合は実行待ち。未採用nisetenを含まない。
- 5書体見本の実フォント・アプリ組込み／電子印影許諾は未確保。5選択と比較PDFは未完成として維持。

### 会社角印 ON／OFF 追加（2026-10-08 16:22）
- ユーザー追加依頼：角印5種類選択にON／OFFを付ける。
- 会社管理者の会社設定1か所に会社角印の表示ON／OFFを保存し、請求書・給与明細・支払証明書の同一PDF生成へ共通反映する。
- OFFは会社角印だけ非表示。選択書体は保持し、ONで復帰。確認印・承認印および承認履歴には影響させない。
- 未実装。5種類書体の許諾・設定・PDF接続と合わせて実装検証する。プレビュー・印刷・保存・共有は同じPDFを使用。

### 角印5種類の比較PDF（2026-10-08 16:21）
- ユーザー依頼：実際の書体でPDF生成できたら、登録会社名による5種類を並べて提示する。
- 篆書体／印相体／古印体／隷書体／古印体の別配置。会社管理者の設定1か所から3帳票へ共通反映する。
- 実書体・アプリ組み込み・電子印影の許諾確認は未完了。nisetenは未採用。現時点で5種類の実PDF完成とは扱わない。
- PR #749 ed83ee3のFlutter CI・iOS CI・Secret Scan成功を確認。ただし未採用書体を含むためDraft維持・未マージ。PR説明を訂正済み。



### 確定追加仕様（2026-10-08 16:16）
- 管理者が会社設定で法人角印の5見本から選択できる機能を実装する（ユーザー確定）。篆書体・印相体・古印体・隷書体・古印体の別配置。枠の太さだけを別書体に数えない。
- 会社単位で一度保存し、登録会社名から動的生成して請求書・給与明細・支払証明書で共通使用。社員プロフィールや帳票別の重複設定にしない。
- 実フォントの確保・利用許諾・選択画面・保存・各帳票接続・PDF比較・CIは未完了。nisetenや生成画像案を選択肢完成として扱わない。


### 角印の実機確認・方針訂正（2026-10-08 16:12）
- ユーザー提供の法人角印の実サンプルを基準にする。上段は篆書体・印相体・古印体・隷書体、下段は古印体の別配置。5サンプルは5種類の別書体とは限らない。
- PR #749 の niseten 実生成PDFは、ユーザーが求める印鑑用の篆書体と異なると指摘。**niseten角印は未採用・未完成。現状の角印実装をmainへ統合しない。**
- B画像案と実フォントを混同した案内を訂正済み。枠違いを別書体として数えず、実フォントの字形・日本語文字対応・組込みと電子印影生成の利用条件を確認する。
- 福利厚生費率の単価欄表示と請求書PDF白背景は実Flutter PDFで表示確認済み。角印を保留しているため、保存・CIと正式採用/main統合を区別する。

### 現在地点（2026-10-08 15:47）
- 最新main: `2ed609b6274151bcd85eebf1e05feab0b4fbf859`。PR #747/#748は統合済み、各最終HEADのFlutter CI・iOS CI・Secret Scan成功。
- ベータ説明書・パンフレット4種計65ページと合冊を更新保存済み。
- Release版をiPhoneへ同一Bundle ID `com.skworks.skWorks`で上書き導入成功。3帳票プレビューの実機画像を確認。印刷・共有・ケーブルなし単体起動の最終確認は別。
- **15:58–15:59方針更新: 比較案Bの完全再現ではなく、実在する篆書体を使用して進める（ユーザー指示）**。細い均一な印篆風の文字、丸角の枠、右から縦3列。登録会社名から自動生成し、請求書・給与明細・支払証明書で共通使用。固定会社印画像は使用しない。
- 現在の作業ブランチ: `fix/invoice-device-appearance-20261008`。実在する小篆風フォントnisetenへ接続、福利厚生費率を消費税と同じ単価欄へ表示、請求書PDFの白い用紙背景。PR #749 / `ed83ee39be93b28d8af6ce57d7271cf0584f922f`へ保存済み。file_picker_darwinのlockfile差分を公式pub.dev SHA256で確認して修正。CI・実PDF比較中、未統合。35行・採用配置・金額は維持。
- 給与/請求/支払計算の保存データ・SQL/PDFテストは既存検証済み範囲を維持。全組合せの実機確認完了とは区別。
- 残り: B反映の実Flutter PDF比較→3CI→安全なmain統合→Release再更新→実機表示・印刷・共有確認。Master端末登録案内は帳票作業が落ち着いてから（未案内、登録成功未確認）。TestFlight準備・Apple登録待ち・公開前最終資料も別管理。

### 過去の作業記録（以下は履歴、古いSHA/進捗を現在地点と扱わない）


### 実機フィードバック 15:26
- Release版の同一Bundle ID上書き導入成功（App installed画像）。起動・印刷・単体動作の確認は別。
- 請求書: 福利厚生費率を消費税と同じ単価欄へ表示。用紙の灰色/透過と角印の形状を採用見本に照合して修正中。金額・35行・配置は維持。


### 2026-10-08 最新統合確認
- PR #747・#748 統合済み。各最終HEADのFlutter CI・iOS CI・Secret Scanは成功。
- 最新main: `2ed609b6274151bcd85eebf1e05feab0b4fbf859`。保存ツリーは検証済み #748 HEADと一致 (`a88ce7e2e778950d5b6304ad02dec2a113afb943`)。
- ベータ版説明書・パンフレット4種計65ページと合冊の更新保存完了。
- 次はMacで暗号化iPhoneバックアップ確認後、同一Bundle IDのRelease上書き導入。実機導入・印刷確認・Master端末登録・TestFlight・公開前最終資料は未完了。

## 最新やること一覧（2026-10-08 更新）

**この節を現在地点の正とします。下の過去記録は履歴です。実装済み・CI成功・main反映・実機確認を区別します。**

- 最新main: `f72daf80cde41b50b8a19c42466bde1bfd7170cd`
- 完了本線: [PR #746](https://github.com/robin4250/sk-works/pull/746)（3CI成功・main統合済み）
- 現在本線: [PR #747](https://github.com/robin4250/sk-works/pull/747)（ベータ資料・Release導入準備、Draft）
- PR #747保存SHA: `e4124de8a8b1133f59346fe26cf43b41cafeb35e`。英語辞書重複3キーは修正済み。実PDF65ページの全文・A4・印刷範囲検証と描画確認に成功。既存説明テスト2件の不整合を修正した最終SHAで3CIとPDF再生成中。
- ブランチ: `fix/device-report-feedback-20261008`
- GitHub保存済み最新SHA: `f27c326a97be85544689e5d5342d1291f95f66bc`
- 上記SHAのCI: Flutter CI / iOS CI / Secret Scanすべて成功。PR #746をmainへ統合。
- 給与・帳票・会社設定の追加修正は保存・実SQL/実PDF検証・3CI・main統合済み。実機確認と未確定の給与方針は別管理。

### 完了済み・保存済み
- [x] PR #745 の会社名による共通角印をmainへ統合。
- [x] 採用済み請求書v8・給与明細v4の見本と再生成ファイルをGitHub保存。
- [x] 出勤なしでも下請け会社の支払証明書設定からプレビューする経路を実装。
- [x] 請求書の福利厚生費率・取引会社連絡先・現場名下の〃位置を修正。
- [x] 社員番号の自動採番・任意変更・重複拒否、所属・職種・入社日を実装。
- [x] 会社の締め日・給料日・確認者設定を会社データへ集約。
- [x] 給与明細の確認者1〜3名・印影・通知・確認履歴のコードを保存。
- [x] 日跨ぎ勤怠、有給と勤務の重複、未来勤務による月給再計算の不整合を修正・本番関数適用。
- [x] 保存済み給与・支払証明書の金額保護、実SQLによる登録→トリガー→再計算の回帰検証。
- [x] 最新実生成PDF 28ファイル・31ページのA4確認。代表4帳票は前回生成と画像差分なし。5給与例はPDF内訳と保存総額の一致テスト成功。全CI成功とは区別。

### 作業中（まだ完了扱いにしない）
- [x] 個別給与設定の登録済み単価を維持し、無関係の設定保存で単価を変えない。
- [x] 会社単価と手当単位を一括保存し、途中失敗で片方だけ保存される状態を防ぐ。
- [x] 給与明細の家族手当・同名控除合算・月給の夜勤/休日内訳を、保存済み総額と一致させる。
- [x] 給与条件の未登録警告を表示し、確認画面・明細・登録データを連携。
- [x] 計算元の選択を登録会社・現場・権限と照合。支払証明書は下請け支払設定を明示。
- [x] 管理者メニューに利用機能ON/OFFを分かりやすく接続。OFFでもデータを保持。
- [x] 日報の未保存編集・再サイン・二重処理・古い読込結果の混入を防ぐ。
- [x] PDF生成失敗後の再試行と、プレビューから戻った後の再読込を整える。
- [x] 主要設定・日報・給与・支払証明書のEnglish/日本語表示とシステム言語を修正。全ページの監査は継続。
- [x] `lib/international/` の言語と国別仕様を整理。英語への切替で日本の給与計算を変更しない。

### 今回の本番反映・検証
- [x] 会社設定の原子的保存、計算元検証、給与名付き内訳を本番適用。
- [x] 給与条件警告は初回自動承認レビューで拒否（理由未提示）。既存トリガー削除をなくして再検証・再適用成功。
- [x] 本番version: `20261008052056` / `20261008052058` / `20261008052138` / `20261008052341`。
- [x] 反映後も社員8件・給与明細2件・会社2件。警告内部関数はanon/authenticated直接実行不可、追加有給トリガーは1件。
- [x] 実生成の給与金額PDF5例と再生成ファイルをGitHub保存。全帳票比較の実機確認はこれから。

### これから（順番）
1. ベータ版ヘルプ・役割別説明書・パンフレットを保存し、実PDF65ページと3CIを検証。
2. Macの生成iOSファイルを削除せず、署名設定のローカルコピーと未保存ソース検査を保護してRelease導入を準備。
3. 資料・導入準備のPRを最新mainへ統合し、保存実在を確認。
4. iPhoneで帳票・出勤・給与・印刷・通知・ON/OFF・日英切替を確認。
5. TestFlight社内試験へ移行。全ページ翻訳・給与方針・公開準備の未完了範囲も継続。

### 並行作業の具体的な改善・検証
- [ ] [PR #748](https://github.com/robin4250/sk-works/pull/748) SHA `8c5fb6a923eddecc11c38067049dd1b5bc27a2b5`: 給与確認通知の対象月への接続・第2認証・RLS・未読保持・二重タップ防止を保存。初回解析の通知遷移Widget型不整合を修正済み。最終CI待ち。
- [ ] 通知画面・承認一覧の言語変更追従と未翻訳キーを整える。通知の任意入力本文を自動翻訳しない。
- [ ] GPSは現在、予定時間外も位置送信するため、サーバーの曜日・予定窓・夜跨ぎ・timezoneを保つ送信抑制方法を調査。

### 未完了の給与規定・追加検証
- [ ] 日給/時給の有給支給額、通常勤務の夜間時間割増は会社の登録方針が未確定。警告を表示し、任意の金額を導入しない。
- [x] 同日2現場の同名手当の1日1回計上、登録順序、実績削除、同値保存時の確認維持を隔離DBで追加検証。追加テストはPR #748へ保存、CIにも接続。

### ヘルプ・説明資料の2段階更新（2026-10-08追加指示）
- [ ] TestFlight前: ベータ版の？アイコン・ヘルプ・説明書・パンフレットの更新コードをPR #747へ保存。実PDF検証・配布資料更新は完了、3CI最終成功とmain統合待ち。
- [x] Flutter source `e4124de8a8b1133f59346fe26cf43b41cafeb35e` から一般10/サブ管理者15/管理者20/パンフレット20ページを生成。全65ページのA4・全文・印刷範囲検査成功、全ページの配置と変更ページの描画確認済み。
- [x] 既存の4配布PDFと65ページ統合版を同じファイルIDへベータ版version 1として更新。個別4PDFのデータはFlutter生成物と同一。配布資料の更新だけで実機や公開前最終改訂は完了扱いにしない。
- [ ] 帳票・確認印・会社/社員設定・利用機能ON/OFF・日英切替の案内を整合。未実装を利用可能と案内しない。
- [ ] TestFlight後: アプリの最終修正が決まった後、公開前に4点を最終更新。
- [ ] 文書の版と対応ソースを明記し、アプリと資料の食い違いを防ぐ。

### App Store公開準備（登録待ち中も並行して進める）
- [x] 既存公開タスク・Apple公式要件・実装を照合し、`docs/APP_STORE_RELEASE_READINESS.md` をGitHub保存。公開要件自体の完了とは区別。
- [ ] プライバシー方針・収集データ表示・アカウント削除経路を確認。
- [ ] カメラ・位置情報などの権限説明と審査用操作案内を整える。
- [x] 日英の掲載文・審査操作案内の下書きをPR #747へ保存。未提出・未公開。
- [ ] スクリーンショット・サポート情報・公開プライバシーURLを準備。
- [ ] 実Release成果物のPrivacy Manifest/SDK/用途説明監査（スクリプト・架空成果物7テストをPR #748へ保存。実Mac検証はこれから）。
- [ ] 登録後に署名・App Store Connect設定・提出/審査へ進む。

### マスター管理者・デバイス登録（2026-10-08確認）
- [x] UIと本番RPCの実在を読み取り監査。全体集計、車両/ルート機能切替、端末管理、復旧メール設定を確認。
- [x] 本番の有効Master権限は1件、登録端末は0台。本人IDとの一致・初回登録・Face ID/第2パスワードは実機未確認。監査による権限付与・端末登録はしていない。
- 過去の「ログインしない」案内は、ユーザー説明では当時の管理者ログイン不具合によるもの。現在の一律ログイン禁止とは扱わない。
- [ ] 現在の帳票・ベータ資料・Release準備が落ち着いた後、ユーザーへ初回デバイス登録の画面順を案内。案内済みと登録成功を別管理。
- [ ] クライアントの信頼端末/Face ID/第2パスワード/15分失効と、サーバーのMaster権限照合の範囲を区別して追加監査。Master全体変更RPCに新鮮な再認証をサーバーで強制することは現在未検証・未実装。

### Apple Developer登録待ち
- [ ] Appleから登録完了の連絡を受領（2026-10-08 ユーザー報告: 連絡待ち）。こちらでは登録状況を直接確認していない。
- [ ] 有効なメンバーシップ確認後、TestFlightの署名・App Store Connect配布準備を進める。
- 待機中もコード修正・給与計算・帳票・CI検証を継続する。

### ユーザー操作が必要（準備後に案内）
- [ ] Mac/iPhoneの暗号化バックアップ確認。ソースバックアップとは別。
- [ ] 既存SKOを削除せず、同一Bundle ID `com.skworks.skWorks` のReleaseを上書き導入。
- [ ] 実機の表示・印刷・通知確認。**今回の上書きインストール完了は未確認。**
- 確認済み環境: Flutter 3.47.5 / Xcode 27.0、接続先13 Pro Max。
- Debug・`flutter run`は禁止。未追跡のiOS署名設定等をまとめて削除しない。

### 更新ルール
- 新しい指示・保存・CI・本番適用・main統合・実機結果に変化があれば、この節を更新。
- 完了条件の証拠を確認してからチェック。完了済み作業を繰り返さない。
- 過去の未チェック項目は履歴上の状態。最新節と矛盾する場合は最新節を優先。


---

## 過去の指示・作業履歴

## 🔁 新しい指示を受けた時の更新ルール

- ユーザーから新しい指示を受けたら、内容を整理した時点で**実装より先に Issue #273 を更新**する。
- その指示を「現在進行中」または「次にやる」に明記してから実装開始する。
- 作業完了後は、**同じ Issue #273 を再更新**して対象項目を「完了済み」に切り替える。
- チャット切断・スレッド移動・端末変更が起きても、Issue #273だけ見れば現在地点が復元できる状態を維持する。
- 完了済み作業は再実装しない。進行中PR・ブランチ・本番migration・CI状態も必要に応じて併記する。

## 🟣 2026-10-04 新規指示：全ページUX・表示・リンク総点検

### 先にやること
### 全ページ監査 一次結果
- [x] PR #609 全ページUX/リンク監査契約テスト（3CI成功・main反映済み）
### 全ページ監査 第2グループ
- [ ] 設定 `settings_page.dart`：一部翻訳済みだが固定日本語多数
- [ ] 利用機能設定 `company_module_settings_page.dart`：翻訳未接続
- [ ] 会社単価・手当設定 `company_rate_settings_page.dart`：翻訳未接続
- [ ] 承認待ち `approvals_hub_page.dart`：翻訳未接続
- [ ] 通知 `notifications_page.dart`：翻訳未接続
- [ ] 友達 `chat_friends_page.dart`：翻訳未接続
- [ ] 従業員資格/資格証 `qualification_cloud_page.dart` / `qualification_certificate_page.dart`：翻訳未接続
- [ ] 必要書類 `worker_document_page.dart`：翻訳未接続
- [ ] 協力会社受信 `company_delivery_inbox_page.dart`：翻訳未接続
- [ ] サイン一覧 `signature_list_page.dart`：翻訳未接続

- [ ] 高優先：請求書画面 `invoice_cloud_page.dart`（日本語固定多数 / 翻訳呼び出し0）
- [ ] 高優先：本人給与明細 `payroll_statements_page.dart`（日本語固定多数 / 翻訳呼び出し0）
- [x] 高優先：給料一覧 `payroll_review_page.dart`（PR #610 / 3CI成功・main反映済み）
- [ ] 高優先：支払証明書 `payment_certificates_page.dart`（日本語固定多数 / 翻訳呼び出し0）
- [ ] 高優先：本日の出勤 `today_attendance_page.dart`（日本語固定多数 / 翻訳呼び出し0）
- [ ] 高優先：勤怠管理 `attendance_management_page.dart`（日本語固定多数 / 翻訳呼び出し0）
- [ ] 高優先：従業員登録 `employee_invite_page.dart`（日本語固定多数 / 翻訳呼び出し0）
- [ ] 高優先：現場詳細 `site_detail_page.dart`（日本語固定多数 / 翻訳呼び出し0）
- [ ] 継続監査：日報・社員一覧・現場一覧・プロフィールは一部翻訳済みだが日本語固定が残る
- [ ] 88個の `*_page.dart` を順次監査し、英語残り/日本語残り/文字バランス/リンクを修正

- [ ] 全ページを対象に、直感的に使える箇所は現状維持
- [x] 初回登録ページ監査【PR #604 / 3CI成功・main反映済み】
  - 本パスワード設定
  - 本人情報登録
  - 承認待ち
  - 招待期限切れ
  - 従業員登録QR読取
  - 日本語/English切替
  - 難しい箇所の「？」案内
  - 文字バランス/リンク/戻る導線
- [ ] 難しそうなページ・ボタン・操作に「？」ヘルプアイコンを追加
  - タップで短い説明
  - 既存ヘルプページへ遷移できる箇所はリンク
  - 説明過多にならないよう、直感操作には付けない
- [ ] 全ページの文字サイズ・余白・2行折返し・ボタン文字のバランスを見直す
- [ ] 日本語表示時に英語のまま残っている案内・ラベル・エラー文を修正
- [ ] English切替時に日本語のまま残っている全ページの文字列を修正
- [ ] 全ページのリンク/遷移を確認
  - ホーム
  - フッター
  - メニュー
  - 一覧→詳細
  - 戻る
  - 設定
  - 承認
  - 印刷/プレビュー
  - チャット
  - 給与/請求/支払証明書/日報
  - 取引会社/下請け会社
- [ ] 無効なリンク・到達不能ページ・誤ルート・権限不整合を修正
- [ ] 日本語/英語の両方で主要ルートの契約テストを追加
- [ ] Flutter CI / iOS CI / Secret Scan 成功後にmain統合
- [ ] 完了後にこの節を更新し、完了済みに切り替える

## 🟪 2026-10-04 新規指示：全画面フローティングヘルプ

- [x] SKO利用中、全画面の最前面に小さなヘルプボタンを表示（PR #606 / 3CI成功・main反映済み）
- [x] ボタンは長押し＋ドラッグで画面内の好きな位置へ移動可能
- [x] 初期表示位置は**フッターのすぐ上・画面右端**
- [x] ユーザーが一度移動した後は、その保存位置を優先
- [x] 位置は端末/ユーザー単位で保存
- [x] タップで「何かお困りですか？」ヘルプを開く
- [x] 現在画面に合った説明を最初に表示
- [x] 辞書のように機能名・ページ名・操作名から検索できる
- [ ] 難しい操作は短い説明→詳しい説明/ヘルプへ進める
- [x] 設定画面に「フローティングヘルプ」ON/OFFを分かりやすく追加
- [ ] 設定画面に「ONにすると画面上の？ボタンからいつでも使い方を確認できます」の説明を表示
- [x] 初期値はON
- [ ] 日本語/Englishの両方に対応（初回登録フローはPR #604で完了、全ページ監査は継続）
- [ ] iPhoneのSafeArea、キーボード、フッター、ヘッダーと重ならないよう制御
- [x] PR #606 Flutter CI / iOS CI / Secret Scan 全成功・main統合
- [x] 完了後にこの節を完了済みに更新

## 🔴 2026-10-04 現在地点（再開時はここを最優先で確認）

### 最新main
- `cff6810677c00a2681eb26584d50a02ba3ec2971`
- PR #597「給料一覧：サブ管理者に見せない人をチェック」main反映済み
- PR #598「0現場・0円自動下書き請求書でも一覧を開ける」main反映済み
- 直前Releaseゲート #596 は3CI成功・main反映済み。ただし #597/#598 以降の新作業があるため、**iPhone実機導入前にもう一度最新mainで3CI＋バックアップが必要**
- 正Bundle IDは `com.skworks.skWorks`。Releaseのみ。元のSKOアプリは削除しない

### ✅ 完了済み（現在の作業で繰り返さない）
- [x] #591 設定未入力でも給与明細/請求書/支払証明書の0円自動下書き生成
- [x] #592 給料一覧・サブ管理者表示制御・閲覧者確認フロー
- [x] #593 給与明細の確認済み/未確定表示
- [x] #594 支払証明書A4印刷
- [x] #595 給料一覧メニュー接続
- [x] #596 post-594 Releaseゲート
- [x] #597 給料一覧を「サブ管理者に見せない人だけチェック」方式へ反転
- [x] #598 0現場の自動下書き請求書で落ちる `sites must contain at least one site` を修正
- [x] 本番Supabase: 給与レビュー/0円下書き/支払証明書関連 migration 適用済み

### 🟡 現在進行中PR
- [x] #599 本人専用「給与明細」入口を一般/サブ管理者/管理者本人へ復元（3CI成功・main反映済み）
  - 管理側「給料一覧」とは別
  - 本人分のみ取得
  - 第2パスワード/Face ID保護を維持
- [x] #600 預かり画像 `IMG_4214.jpeg` を基準に給与明細A4 PDFを帳票化（3CI成功・main反映済み）
- [x] #601 預かり画像 `IMG_4212(1).jpeg` を基準に「工事代金支払明細書」A4 PDFへ変更（3CI成功・main反映済み）
- [x] #602 預かり画像 `IMG_4213.jpeg` を基準に「御請求書」A4 PDFへ変更（3CI成功・main反映済み）
- [x] #603 預かり画像 `IMG_4196.jpeg` を基準に「作業日報」A4 PDFへ変更（3CI成功・main反映済み）
- [ ] #322 将来のビデオ会議ロードマップ。**現在のTestFlight/実機導入本線ではない**

### 🟠 現在進行中：取引会社 / 下請け会社 共通マスター
PR #607 / ブランチ: `feature/trade-company-master-main-20261004`

#### 目的
- 連携して使う会社も、SKO連携しない会社も、同じ「取引会社マスター」に保存
- 「取引会社」と「下請け会社」の両方から登録・契約設定可能
- 連携なしでも請求書/支払証明書を作成可能
- 後からSKO連携する場合、会社名・電話番号・住所・法人番号等から候補を出し、**統合確認後に連携**
- 既存 `customers` / `partner_companies` は壊さず互換リンクを維持

#### 契約設定
- [ ] 1日単価
- [ ] 月単価
- [ ] 平米単価 + 平米数
- [ ] 請負金額
- [ ] 取引会社にも下請け会社にも同じ設定UIを用意
- [ ] 下請け会社は連携なしでも支払証明書生成対象

#### 管理現場との競合ルール
- 管理現場側の単価設定と取引会社/下請け会社契約の両方が入っている場合、**自動で優先順位を決めない**
- [ ] 「管理現場の設定を使う」
- [ ] 「取引会社/下請け会社の契約設定を使う」
- どちらかを選ぶ案内を表示し、**選択必須**
- 選んだ側だけを有効な計算元として保存
- 請求書 / 支払証明書 / 給料明細の計算に共通適用
- 後から設定画面で変更可能

#### 本番Supabase適用済み土台
- [x] `20261004132001 add_trade_company_master_and_contract_sources`
- [x] `20261004132037 restrict_trade_company_master_to_rpc`
- [x] `20261004132201 add_trade_company_calculation_conflicts`
- [x] 新規テーブルはRPC専用に制限
- [x] 連携候補RPC・契約保存RPC・計算元選択RPC・競合検出RPCの土台
- [x] リポジトリmigration mirror
- [x] 取引会社ページUI（PR #607）
- [x] 下請け会社ページUI（PR #607）
- [x] 連携候補→統合確認UI（PR #607）
- [x] 競合時2択UI（PR #607）
- [x] 既存自動計算関数へ計算元選択を反映（本番DB + repo mirror / PR #607）
- [ ] PR #607 3CI成功後mainへ統合

### 📄 預かり帳票画像の正式基準
- 給与明細: `IMG_4214.jpeg`
- 支払証明書: `IMG_4212(1).jpeg`
- 請求書: `IMG_4213.jpeg`
- 日報: `IMG_4196.jpeg`
今後この4帳票は独自デザインを基準にせず、上記画像へ寄せる。

### 📱 iPhone実機導入の最終条件
- [ ] #599〜#603 を必要なものからmain統合
- [ ] 取引会社/下請け会社共通マスターの今回スコープ完了
- [ ] 最新mainで Flutter CI / iOS CI / Secret Scan 全成功
- [ ] 本番Supabase migrationとrepo migration mirror一致
- [ ] 最新mainから**新しい実機前バックアップ**を作成
- [ ] `tool/pre_device_release_gate.sh` / `tool/device_day.sh` 最終確認
- [ ] その時点で初めて、Macへ貼る**1行のRelease上書きインストールコード**を提示

---

## 再開時のルール

新しいチャットや別端末で作業を再開したときは、まずこの Issue #273 を確認する。

- [ ] 0. Apple Developer Account の承認状況を最初に確認
  - 「隅田建設KK」の状態を確認
  - 保留中なら通常の開発作業を継続
  - 承認済み・手続き可能ならApple側の手続きを優先

## 開発の基本運用ルール（今後は本線＋並行レーン）

- 本線の作業は止めずに最優先で進める。
- 並行レーンでは、本線と干渉しない軽いUI変更・表示変更・画面枠・設定項目・権限の骨組みなどを先に進める。
- 並行タスクは別ブランチで扱い、同じファイル・同じDB構造・同じ認証処理などに触れて競合しそうになった時点で止める。
- 競合しそうになったら無理に完成まで進めず、別の独立した軽いタスクへ移る。
- やることリストから「短時間で安全に消せるもの」「骨組みだけ先に作れるもの」を積極的に拾って進める。
- 本線が完了したら、並行レーンで準備済みの作業を順次仕上げ・統合する。

### 2026-09-30 現在

- TestFlight前mainline: 現場チャット連動、車両/ルート、委任権限、Master厳格ゲート、Master集計ダッシュボード、可逆機能制御、Japan Country Packまでmain反映済み。
- 本番Supabase security assertion suite は最終監査で pass。
- 未完の大項目は下記チェックボックスを正とし、完了済み作業は繰り返さない。

## 現在の実装順序

- [x] 1. 過去のまとめて出勤 + まとめてサイン（PR #281 マージ済み）
- [x] 2. 給与調整（前貸し／前借り等）管理 + 給与明細連携（Issue #274、実装済み）
  - [x] ドメイン骨組み PR #282 マージ済み
  - [x] 権限・監査土台 PR #285 マージ済み
  - [x] 給与明細反映 PR #286 マージ済み
  - [x] 管理UI PR #289 マージ済み
  - [x] 項目別・期間別フィルター＋監査付き編集 PR #293 マージ済み
  - 管理者のみページ表示名を変更可能
  - サブ管理者は権限付与時に登録・編集可能
  - 社労士等の閲覧者は権限付与時に閲覧可能
  - 第2パスワード必須
  - 給与明細・個別給与設定へ連携
  - 修正・取消は履歴を残す
- [x] 3. 過去分のまとめて修正・編集（PR #291 土台、PR #294 承認UI、PR #303 月別複数選択・修正UIまでマージ済み）
- [x] 4. 上記修正分のまとめてサイン（PR #291/#303 共通サイン、PR #294 承認側サイン表示までマージ済み）
- [x] 5. 出勤表カレンダー表示修正（PR #280 週末色分け、PR #288 祝日表示ともにマージ済み）
  - [x] フッターの出勤表は1週間表示
  - [x] 日曜日を赤表示
  - [x] 土曜日を青表示
  - [x] 1週間表示内の日本の祝日は赤表示
  - [x] 祝日名を欄内へ小さい赤文字で表示
  - [x] PR #288 CI完了・マージ
- [x] 6. チャット参加メンバー表示（PR #279 / #290 マージ済み）
  - [x] ヘッダーのグループ名タップで参加メンバー一覧を開く
  - [x] メンバーをチャット更新順で上から縦表示
  - [x] 一覧内容は氏名＋会社名
  - [x] 吹き出し内の時刻を外へ移動（自分＝左外、相手＝右外）
  - [x] PR #290 CI完了・マージ

## マスター管理者・運営機能

- [x] 7. マスター管理者ロールの正式追加（土台 PR #300 マージ済み）
  - [x] 会社管理者より上位のSKO全体運営ロール
  - [x] 通常の会社管理者からマスター権限を付与・削除できない設計
  - [x] 重要操作は監査ログに記録

- [x] 8. マスターデバイス管理（厳格Masterゲート・管理UI・端末登録/ロック/解除までmain反映済み）
  - [x] iPhone / iPad / Mac を信頼済みマスターデバイスとして登録
  - [x] 端末名、種類、登録日時、最終利用日時、有効/ロック状態を表示
  - [x] 既存の信頼済み端末から他端末のロック・登録解除
  - [x] 機種変更時の新端末追加は再認証必須

- [ ] 9. マスター緊急復旧（PR #405 main反映・本番DB/Edge Function配備済み。メール送信secret設定と実機送信確認のみ残り）
  - [x] 2つの別々の復旧用メールアドレスを登録
  - [x] 両方へ別々のワンタイム復旧コードを送付する実装
  - [x] 2系統とも認証成功した場合のみ新しいマスターデバイスを登録可能
  - [x] 復旧用メール変更時は強い再認証
  - [x] 全操作を監査ログへ記録
  - [x] 復旧チャレンジ発行を10分3回までにDB境界で制限
  - [x] send-master-recovery-codes Edge Functionを本番へ配備（JWT必須）
  - [ ] RESEND_API_KEY / MASTER_RECOVERY_FROM_EMAIL を本番secretへ設定
  - [ ] 実メール2系統で送信・二重コード・新端末登録を実機確認

- [x] 10. マスター分析データ収集基盤
  - [x] 会社登録総数、新規会社登録数（7日 / 30日 / 月次）
  - [x] ユーザー総数、1社あたりユーザー数（平均 / 中央値 / 最小 / 最大）
  - [x] 会社間連携数、連携済み / 未連携会社数、連携率（PR #407 main反映済み）
  - [x] アクティブ会社数・利用継続率、登録・利用の成長速度（PR #409 main反映済み）

- [x] 11. ストレージ・データ利用統計（全体集計 #393＋個社を特定しない会社分布 #410 までmain反映済み）
  - [x] 全体のファイル数・総容量・画像数・PDF数・使用中バケット数
  - [x] 全体の総ファイル数・総容量・画像/PDF件数・使用中バケット数
  - [x] 会社単位の写真・PDF・添付・容量分布（PR #410で会社ID/会社名を返さず、平均・最大・最小等のaggregate-only集計としてmain反映済み）
  - [x] 総ストレージ使用量、会社単位の平均 / 最大 / 最小使用量（#393/#410でmain反映済み。最大/低使用の個社名・ID特定表示はプライバシー方針上行わない）

- [x] 12. ページ・機能・ボタン利用ランキング（基盤＋主要画面のpage_open収集＋7/30/90日ランキング表示＋7日/30日利用率までmain反映済み）
  - [x] 固定allowlistの主要画面/機能だけを非同期・非ブロッキングで収集（本文・GPS・電話番号・自由入力metadataなし）
  - [x] Masterダッシュボードで7日 / 30日 / 90日のイベント数・利用会社数・利用者数・人気操作/画面/機能を表示
  - [x] ホーム / 出勤 / 退勤 / 出勤表 / 日報 / 給与明細 / 請求書 / チャット / 印刷 / 会社間連携 等（固定allowlistと主要アクション配線をPR #414の契約テストで固定）
  - [x] 開いた回数、使用会社数、使用ユーザー数、1人・1社あたり利用回数（PR #406 main反映済み）
  - [x] 7日 / 30日利用率、上昇・下降傾向（前期間比はPR #406、7日/30日利用率はPR #415でmain反映・本番migration適用済み）
  - [x] 無効化された機能と、有効だが未使用の機能を分ける（PR #411 main反映済み）

- [x] 13. マスターダッシュボード（主要KPI・期間比較・利用グラフ・将来プラン分析指標までmain反映済み）
  - [x] 集計値のみを表示し、個別データ/本文/写真/ファイル内容/位置情報を表示しない
  - [x] 利用状況の7日 / 30日 / 90日切替と人気操作/画面/機能ランキング
  - [x] 上記KPIを一覧表示（PR #412 main反映済み）
  - [x] 期間比較（7日 / 30日 / 90日をPR #416で同時比較表示。既存の期間選択表示も維持）
  - [x] グラフ表示、人気機能 / 低利用機能ランキング（PR #417で既存aggregate利用データをグラフ表示。0回は「有効・未使用」で分離）
  - [x] 将来のFree / Proプラン分析に使える指標（PR #418で30日利用率、1社あたり利用回数、平均利用者数、平均ストレージ、会社間連携率、30日継続率をaggregate-only表示）

## App Store正式公開前の必須タスク

- [ ] 14. アプリ更新案内・App Store誘導（更新ポリシー #297、App Store照合 #419、案内UI/判定 #420 までmain反映済み。起動時配線・App Store起動が残り）
  - [ ] アプリ起動時に利用中バージョンと最新公開バージョンを確認
  - [x] 古い場合は「新しいバージョンがあります」等の案内UI・判定を実装（PR #420 main反映済み。起動時呼び出しは未接続）
  - [ ] App StoreのSKOページへ直接誘導
  - [x] 通常更新は案内のみ、重大な互換性問題がある場合は将来「必須更新」にできる設計余地を実装（PR #420）
  - [ ] App Store正式公開前に実装・テストする

## プライバシー方針

分析では内容そのものは収集せず、イベント・件数・容量・集計値を中心にする。
チャット本文、写真そのもの、ファイル内容、マイナンバー、パスワード、GPSの具体的位置などは分析用には収集しない。

## 実装タイミング

2026-09-30現在、給与調整・まとめて修正・カレンダー・チャット参加メンバー・Masterデバイス・現場チャット・車両/ルート・Country Packの本線は完了。Master分析は利用詳細 #406、会社間連携KPI #407、会社ストレージ分布 #410、機能OFF/未使用分類 #411、7日/30日利用率 #415、期間比較 #416、利用グラフ #417、将来プラン分析指標 #418までmain反映済み。アクティブ会社・継続率・成長速度はPR #409でmain反映済み。緊急復旧は実装/DB/Edge Function配備済みで、メール送信secret設定と実機確認のみ残り。アプリ更新案内はApp Store照合/UIまでmain反映済み。残りは起動時配線・App Store URL起動・実機確認で、App Store正式公開前の必須項目とする。

## 2026-10-01 実機確認反映

- [x] 管理ホーム一次修正（PR #421 main反映済み）
  - 「要対応」の位置を維持
  - 「本日の出勤」を維持
  - 重複の「管理出勤」は存在しない状態を契約固定
  - 「人員」「管理現場」の表示
  - 白 / 薄青 / 青枠 / 青枠＋黒二重丸の権限UI土台
  - 「運用準備チェック」は通常メニュー非表示
- [ ] 会社提出書類
  - [x] 既存 company_required_documents / private Storage / company_document_exchange を再利用
  - [x] 管理・PDF/画像・期限・メモ・上位送信UI（PR #422 main反映済み）
  - [ ] 管理メニュー/管理カード接続（PR #429）
  - [ ] 受信側を出所会社 > 従業員 / 資格証 / 従業員提出書類 / 会社提出書類へ分類（latest-main PR #430）
- [ ] 資格証表裏
  - [x] 本番DBへ optional attachment_back_path migration 適用・検証済み
  - [ ] latest-main foundation PR #433
  - [ ] 表面＋任意裏面の実機UI PR #427（#433依存）
  - [x] 本番 company_document_exchange に裏面添付送信を追加・検証済み
  - [ ] リポジトリmirror PR #432（#433依存）
- [ ] 資格画像認識・資格マスター自動化
  - [ ] OCR結果を自動確定せず候補化し、資格マスター/別名へ照合（latest-main PR #434）
  - [ ] 表記揺れ・重複をクラスタ化して資格マスター候補化（latest-main PR #431）
  - [ ] 実画像OCRプロバイダを接続し、登録前確認UIへ接続
- [ ] 運用準備の意味を契約固定（latest-main PR #435）
  - 3/3 = 作業員マスター + 現場マスター + 通信グループ
  - 勤怠実績は情報表示で3/3に含めない
  - 通信グループは communication_groups、LINE連携は active_line_bindings の別カウント


## 🟦 2026-10-04 23:37 JST 再開セッション
- [x] 再開時にIssue #273を最初に確認
- [ ] 最新main SHA / Open PR / Flutter CI / iOS CI / Secret Scanを再確認
- [ ] 本番Supabase migrationとrepo mirror一致を再確認
- [x] PR #606はIssue記録上、3CI成功・main統合済みのため再実装しない
- [ ] PR #607の最新CI・mergeable状態を確認し、成功済みならmain統合
- [ ] 全ページUX/日本語-English/リンク監査を継続（完了済み #609/#610 は繰り返さない）
- [ ] 高優先残件から競合しない5〜7レーンを維持
- [ ] TOPヘッダーは完成済みとして変更禁止
- [ ] 最終的に最新main 3CI、本番migration mirror、実機前バックアップ、Releaseゲート、Bundle ID `com.skworks.skWorks` を確認後のみ1行Release上書きコードを提示


### 23:45 JST 状態確認追記
- [x] latest main = `cff6810677c00a2681eb26584d50a02ba3ec2971` (#610 merge)
- [x] 本番Supabaseは ACTIVE_HEALTHY、取引会社6 migrationは本番適用済み
- [x] 6 migrationのrepo mirrorは #607 ブランチに存在（main未統合のためmain上にはまだ無い）
- [ ] #607: Secret Scan成功、Flutter CI/iOS CI進行中、現時点mergeable=false
- [ ] #616失敗原因: 給与明細の旧固定日本語契約テストがEnglish対応と衝突
- [ ] #617失敗原因: today_attendance_page.dart の未使用 language_controller import（Flutter/iOSともanalyze失敗）
- [ ] #611〜#617は重複ページ変更を含むため、差分を整理して重複PRを統合/閉鎖し、最新mainへ安全に載せ直す


### 23:50 JST 更新
- [x] PR #608「UI language/navigation audit」Flutter CI + Secret Scan成功、iOS対象外、mainへ統合
- [x] #608 merge commit: `1008868afa92991b9a0fdea4a6c5bc5a01365702`
- [ ] 以降は `1008868...` 以降の最新mainを正として #607 / 高優先監査PRをrestack


### 23:58 JST 高優先監査 restack
- [ ] #619 本人給与明細 English対応（#611後継 / 最新main起点）
- [ ] #620 支払証明書 English対応（#612後継 / 最新main起点）
- [ ] #621 請求書 English対応（#613後継 / 最新main起点）
- [ ] #622 本日の出勤 English対応（#614後継 / 最新main起点）
- [ ] 上記後継PRの3CI確認後、旧 #611〜#614 は重複PRとして閉鎖


### 00:05 JST 監査追記
- [ ] #615由来でmainに未反映のEnglish辞書6語を独立PR化
  - 給料一覧 / 確認済み / 未確定 / 支払証明書 / 下書き / 確定
- [ ] 辞書PRを先行main統合し、#619/#620のEnglish表示を成立させる


## 🟥 2026-10-04 新規不具合：出勤表の有給表示 / フッター消失
- [ ] 出勤表カレンダー表示で、有給日が「休み」と表示される不具合を修正
- [ ] 出勤表プレビュー表示で、有給日が「休み」と表示される不具合を修正
- [ ] 有給は週表示 / 月カレンダー / プレビューで一貫して「有給」と表示
- [ ] カレンダー表示・プレビュー表示から週間表示へ戻る際、フッターが消えることがある不具合を修正
- [ ] 既存の週/月切替、今日枠、祝日表示、月間集計、手当表示、A4プレビュー仕様を壊さない
- [ ] TOPヘッダー・DB・認証・RLSは変更しない
- [ ] 最新main起点の独立PRで契約テストを追加し、3CI成功後main統合


### 追加UI要望
- [ ] 出勤表上部の「有給申請」「勤務修正」をTextButton風ではなく、押せることが分かる明確なボタンUIへ変更
- [ ] 既存の動作・権限・遷移は維持


### 追加UI要望（勤務修正）
- [ ] 勤務修正画面内の「休み→有給」を、文字リンクではなく押せることが明確なボタンUIへ変更
- [ ] 既存の休み→有給申請フロー、承認、履歴、権限は維持


### 追加UX要望（勤務修正の進め方）
- [ ] 勤務修正画面を開いた直後に「何をすればよいか」が直感的に分かるUIへ改善
- [ ] 画面上部に短い手順（①月/日を選ぶ → ②修正する日を選ぶ → ③内容を直す → ④最後にまとめてサイン）を表示
- [ ] 現在の選択件数・未変更/変更済み件数を分かりやすく表示
- [ ] 次に押す操作を視覚的に強調し、無効時は理由が分かるようにする
- [ ] 「休み → 有給」ボタンは明確な独立操作として維持
- [ ] 既存の一括勤務修正、承認、サイン、履歴、権限は変更しない


### 出勤表 / 勤務修正 UX 実装状況
- [ ] PR #627「Restack attendance sheet paid leave footer and correction UX」を最新main起点で作成（#626後継）
- [x] 有給申請 / 勤務修正を明確なボタンUIへ変更
- [x] 勤務修正内「休み → 有給」を明確なボタンUIへ変更
- [x] 勤務修正に4ステップガイド（①月→②対象日→③修正→④まとめてサイン）を追加
- [x] 選択件数 / 変更済み件数を表示
- [x] 変更がない間は最終サインボタンを無効化し、次の操作を文言で案内
- [x] A4プレビュー / PDFで有給を「休み」と誤表示しない修正
- [x] 月カレンダー/プレビューから週表示復帰時に共有フッターを再表示
- [ ] #627 3CI成功後main統合し、#626を重複PRとして閉鎖


## 🟦 2026-10-05 新規指示：チャット構成・友達一覧・グループチャット・通知音設定

### チャット上部タブ構成
- [ ] 現在の「すべて / 現場 / 個別 / 協力会社」を廃止し、「すべて / 友達 / 現場 / グループ / 協力会社」に変更
- [ ] 既存チャット・現場チャット・協力会社チャット・個別チャットのデータは削除しない

### ヘッダー「友達一覧」
- [ ] チャット画面ヘッダーに「友達一覧」を追加
- [ ] タップすると友達を縦一覧表示
- [ ] 一覧に友達氏名を表示
- [ ] 友達氏名タップで個別トークを開始
- [ ] 個別トーク開始後、そのスレッドは「友達」タブ一覧へ生成/表示

### グループタブ
- [ ] 「グループ」タブ直下に「グループチャット作成」ボタン
- [ ] グループ名を入力して作成
- [ ] 作成ボタンの下に作成済みグループ一覧を縦表示
- [ ] グループチャットを開いた後は、同位置の操作を「友達を招待」ボタンへ切替
- [ ] 友達を招待すると承認通知を送信
- [ ] 承認後にグループメンバーへ追加

### グループメンバー管理
- [ ] グループ名タップ先にメンバー一覧
- [ ] メンバー一覧上部に「友達招待」「脱退」ボタン
- [ ] メンバー名長押しで追放操作
- [ ] 追放は権限を持つユーザーのみ実行可能
- [ ] 最後の1名が脱退してメンバー0名になった時点でグループ削除
- [ ] 1名残っている間はグループを残す

### グループ一覧ジェスチャー
- [ ] グループ名を左スワイプ → 「削除」「非表示」
- [ ] グループ名を右スワイプ → 「上位にピン留め📌」「通知音ON/OFF」
- [ ] ピン留めグループは一覧上位へ表示
- [ ] 非表示はユーザー単位
- [ ] 通知音ON/OFFもユーザー単位

### 設定
- [ ] メニュー > 設定 に「アプリの通知音設定」ON/OFFを追加
- [ ] 初期値ON
- [ ] アプリ全体の通知音設定とグループ単位通知音設定を分離
- [ ] グループ単位OFFは、そのグループの通知音のみ消音
- [ ] 既存通知ベル・通知一覧・通知件数は維持

### 実装ルール
- [ ] 既存チャットデータ、friend基盤、communication_groups、company connectionを再利用できるか先に確認
- [ ] 新規DBは既存構造で不足する最小限のみ
- [ ] TOPヘッダーは変更しない
- [ ] DB/RLS/認証を不用意に変更しない
- [ ] 最新main起点で競合しないPRへ分割
- [ ] 各PR 3CI成功後main統合


### 2026-10-05 進捗：チャット5タブ / グループチャット
- [x] 本番Supabase migration `20261004155625 add_custom_chat_group_membership_workflow` 適用済み
- [x] repo mirrorをPR #628へ追加
- [x] チャット上部を「すべて / 友達 / 現場 / グループ / 協力会社」へ変更
- [x] ヘッダー「友達一覧」→友達氏名縦一覧→タップで個別トーク開始
- [x] 友達タブは既存direct chatのうち友達関係のみ表示
- [x] グループ名入力→participants_onlyグループ作成
- [x] 友達招待→承認通知→承認/拒否→参加
- [x] メンバー一覧上部「友達招待」「脱退」
- [x] メンバー名長押し→追放（DB側権限確認あり）
- [x] 最後の1名脱退後、メンバー0名ならグループ削除
- [x] 左スワイプ→削除/非表示、右スワイプ→ピン留め/通知音ON-OFF
- [x] 設定に「アプリの通知音設定」ON/OFF（初期ON）
- [ ] PR #628 3CI成功後main統合
- [ ] 実機通知音の発音側が設定値を参照しているか最終配線確認


### 2026-10-05 チャット実装進捗
- [x] 本番Supabase migration `20261004155625 add_custom_chat_group_membership_workflow` 適用
- [x] 本番Supabase migration `20261004161045 allow_cross_company_custom_chat_members` 適用
- [x] 両migrationをPR #628へrepo mirror
- [x] チャットタブを「すべて / 友達 / 現場 / グループ / 協力会社」へ変更
- [x] ヘッダー「友達一覧」→友達氏名の縦一覧→氏名タップで個別トーク開始
- [x] 個別トークを「友達」タブ内で表示
- [x] グループタブに「グループチャット作成」→グループ名入力→作成済み一覧
- [x] グループ会話を「グループ」タブ内で開き、作成ボタン位置を「友達を招待」へ切替
- [x] 友達招待→承認通知→承認/拒否→参加
- [x] メンバー一覧上部「友達招待」「脱退」、メンバー長押し追放
- [x] 最後の1名脱退でグループ削除
- [x] グループ一覧 左スワイプ→削除/非表示、右スワイプ→ピン留め/通知音ON-OFF
- [x] 設定に「アプリの通知音設定」ON/OFF（初期ON）を追加
- [x] 他社のSKO友達もparticipants-only明示メンバーとして参加可能に補強
- [ ] PR #628 最新3CI成功後main統合


### 出勤表 / 勤務修正 UX 完了
- [x] PR #627 3CI成功・main統合
- [x] merge commit `e5f9cd84042eee2a96b991c2aa462ceeaf9a27b8`
- [x] 有給誤表示、週表示復帰時フッター、有給申請/勤務修正/休み→有給ボタン化、4ステップ勤務修正ガイドをmain反映


### 2026-10-05 完了更新：出勤表 / 勤務修正 UX
- [x] PR #627 3CI成功・main統合済み
- [x] 出勤表カレンダー/A4プレビュー/PDFで有給を「有給」と表示
- [x] カレンダー/プレビューから週表示復帰時にフッター再表示
- [x] 出勤表「有給申請」「勤務修正」を明確なボタン化
- [x] 勤務修正「休み → 有給」を明確なボタン化
- [x] 勤務修正4ステップガイド・選択件数/変更済み件数・次操作案内


### 2026-10-05 チャット本線 restack
- [x] #627統合後の最新mainから後継PR #629を作成（#628の安全なrestack）
- [x] 本番migration `20261004161416 allow_explicit_cross_company_chat_members` 適用・repo mirror
- [x] 本番migration `20261004161722 harden_custom_chat_group_access_search_path` 適用・repo mirror
- [x] グループ招待通知タップでチャットのグループタブへ遷移
- [x] アプリ通知音ON/OFF＋グループ単位通知音ON/OFFを実際のチャット受信音へ反映
- [ ] PR #629 3CI成功後main統合し、#628を重複PRとして閉鎖


### グループ追放権限の確定
- [x] 本番migration `20261004162159 allow_custom_chat_members_to_remove_members` 適用・PR #629へrepo mirror
- [x] participants-onlyグループの参加メンバーは、他メンバー名長押しで追放可能
- [x] グループ外ユーザーは追放不可
- [x] 自分自身は追放操作ではなく「脱退」ボタンのみ


### チャット追加安全調整
- [x] 本番migration `20261004162159 allow_custom_chat_members_to_remove_members` 適用・PR #629へrepo mirror
- [x] グループ参加者は他メンバーを長押し追放可能、グループ外は不可、自分は脱退ボタンのみ
- [x] 他社友達との個別トークも友達氏名で表示
- [x] 5タブは既存iPhone回帰契約に合わせ、高さ固定の横ListViewで表示


### 2026-10-05 継続進捗
- [x] PR #623 取引先/協力会社統合マスター 3CI成功・main統合
- [x] 最新main: `734c2082b09cb6b8650205d910ad4a09fd92c3a1`
- [x] チャット仕様を最新main起点のPR #630へ完全載せ直し
- [x] #630 head: `c6daf0cea45564d541fa0db13bb713bfca854210`
- [x] #630 mergeable=true
- [ ] #630 Flutter CI / iOS CI / Secret Scan 3成功後main統合
- [ ] #628/#629は#630統合後に重複PRとして整理


### 2026-10-05 チャット最終restack #630
- [x] #623 取引先/協力会社統合マスター: 3CI成功・main統合済み（main `734c2082b09cb6b8650205d910ad4a09fd92c3a1`）
- [x] #628/#629 の旧baseを使用せず、current main起点の #630 を作成
- [x] #630 mergeable=true
- [x] Secret Scan成功
- [ ] Flutter CI成功
- [ ] iOS CI成功
- [ ] 3CI成功後main統合
- [ ] #628/#629を重複として整理


### 2026-10-05 並走restack #631-#633
- [x] #631 承認ハブ＋出勤管理ローカライズを current main へrestack
- [x] #632 給与明細ローカライズを current main へrestack
- [x] #633 支払証明書ローカライズを current main へrestack
- [ ] 各PR 3CI成功後に順次main統合
- [x] #630 チャット本線は mergeable=true / Secret Scan成功
- [ ] #630 Flutter CI / iOS CI完了待ち


### 2026-10-05 完了：チャット新仕様 #630
- [x] PR #630 Flutter CI成功
- [x] PR #630 iOS CI成功
- [x] PR #630 Secret Scan成功
- [x] PR #630 current mainへ統合
- [x] merge commit `66e7ec3217c8188480db237466a1c43d493d5440`
- [x] 5タブ「すべて / 友達 / 現場 / グループ / 協力会社」
- [x] 友達一覧→氏名タップ→個別トーク
- [x] グループ作成/招待承認/脱退/追放/0人削除
- [x] 左スワイプ削除/非表示、右スワイプピン留め/通知音ON-OFF
- [x] アプリ通知音ON/OFF＋グループ個別ミュート
- [x] 会社跨ぎ友達は明示メンバー型チャットのみ許可
- [ ] 旧 #628/#629 を重複整理


### 2026-10-05 後継restack #634-#636
- [x] #630 チャット新仕様 3CI成功・main統合済み（main `66e7ec3217c8188480db237466a1c43d493d5440`）
- [x] #628/#629 重複整理済み
- [x] #634 承認ハブ＋出勤管理ローカライズを latest main へ再restack
- [x] #635 給与明細ローカライズを latest main へ再restack
- [x] #636 支払証明書ローカライズを latest main へ再restack
- [x] #631/#632/#633 重複整理済み
- [ ] #634/#635/#636 3CI成功後に順次main統合


### 2026-10-05 進行ルール再確認：完了までノンストップ
- [x] メイン作業1本＋競合しない5〜7並走レーンで進行
- [x] 同じファイル / DB / 認証処理を同時に触らない
- [x] CI待ち / GitHub待ち / ビルド待ちで止まらず別レーンを進行
- [x] 区切り報告で停止しない・確認待ちにしない
- [ ] #634/#635/#636 をCI成功後に順次main統合
- [ ] 社員招待 / 現場詳細 / 残ページの言語・リンク監査継続
- [ ] 最新mainでFlutter CI / iOS CI / Secret Scan成功確認
- [ ] 本番Supabase migrationとrepo mirror一致確認
- [ ] iPhone導入直前に最新mainの新規バックアップ作成
- [ ] tool/pre_device_release_gate.sh / tool/device_day.sh / Bundle ID guard確認
- [ ] 正Bundle ID com.skworks.skWorks のRelease上書きインストール1行コマンドを最終提示


### 2026-10-05 UI監査：社員招待 / 現場詳細
- [x] 社員招待ページ監査：日本語直書き多数を確認
- [x] 現場詳細ページ監査：日本語直書き多数を確認
- [x] site_cloud_page は一部SkoLanguageController.tr化済み
- [ ] #634が英語辞書を触るため、辞書競合回避として実装は#634統合後に開始
- [ ] 社員招待：役割/承認担当/初期パスワード共有/QR案内まで英語切替
- [ ] 現場詳細：共有/終了申請/登録者/編集/写真/確認ダイアログまで英語切替
- [ ] 各遷移・ボタンリンク切れ契約を追加


### 2026-10-05 Release/Supabase静的ゲート
- [x] 本番Supabase直近15 migration → main mirror全件確認済み
- [x] tool/pre_device_release_gate.sh: dependency / secret / destructive SQL / migration / shell / analyze / test gate確認
- [x] tool/device_day.sh: Mac準備→release gate→prepare_ios→device preflight→Release実機導入の一括経路確認
- [x] tool/run_ios_device.sh: Releaseビルドのみ・Debug不使用
- [x] 正Bundle ID `com.skworks.skWorks` をビルド後Info.plistから再検証
- [x] Bundle ID不一致時は実機インストールを停止
- [ ] 最終main確定後に新規backup branch作成
- [ ] 最終main 3CI再確認後、iPhone用1行コマンド提示


### 2026-10-05 追加並走：社員招待 / 現場詳細ローカライズ
- [x] #634英語辞書との競合回避方針を決定
- [ ] 社員招待ページはページ内のJA/EN切替で実装
- [ ] 現場詳細ページはページ内のJA/EN切替で実装
- [ ] 既存DB/RLS/認証/遷移は変更しない
- [ ] 各ページ契約テスト追加→3CI成功後main統合


### 2026-10-05 02:22 JST 進行ルール固定
- [x] メイン作業1本を最優先
- [x] 競合しない作業を約5本並走
- [x] 最新mainを正として作業し、main全体を古いSHAへ戻さない
- [x] 完了済み作業を繰り返さない
- [x] 同一ファイル / DB / 認証処理の同時編集禁止
- [x] CI/GitHub/ビルド待ちで停止せず別レーンへ切替
- [x] レーン完了後は次の未完了へ即切替
- [x] iPhone導入はReleaseのみ、Debug/flutter run禁止
- [x] 正Bundle ID `com.skworks.skWorks`
- [x] 誤Bundle ID `com.robin4250.sko` へは絶対にインストールしない
- [ ] 全作業後に最新main / Flutter CI / iOS CI / Secret Scan / Release条件 / Bundle IDを最終確認
- [ ] iPhone導入可能になった時点でMacへそのまま貼れる1行コマンドを提示


### 2026-10-05 チャットRPC本番権限確認
- [x] create/invite/list/respond/leave/remove/delete/member-list の8 RPCを本番で再検証
- [x] anon EXECUTE=false
- [x] PUBLIC EXECUTE=false
- [x] authenticated EXECUTE=true
- [x] public wrapperはSECURITY DEFINERではない


### 2026-10-05 latest-main本線 #642-#645
- [x] #637 給与明細ローカライズ 3CI成功・main統合済み（main `b3731664834efe34e4d852b79dfb45d1c52def8c`）
- [x] #642 支払証明書ローカライズを latest main へrestack
- [x] #643 財務英語6ラベルを latest main へrestack
- [x] #644 社員招待/従業員登録ローカライズを latest main へrestack
- [x] #645 現場詳細/編集申請ローカライズを latest main へrestack
- [x] #638/#639/#640/#641 は重複整理済み
- [ ] #642/#643/#644/#645 3CI成功後に順次main統合


### 2026-10-05 最終ローカライズ統合方針
- [x] #642/#643/#644/#645 は変更ファイルが相互非競合であることを確認
- [x] 個別CIは検証レーンとして継続
- [ ] latest mainから4本の差分だけをまとめた最終統合PRを作成
- [ ] 統合PR 3CI成功後に1回でmainへ統合し、個別PRを重複整理


### 2026-10-05 最終統合PR #646
- [x] #642/#643/#644/#645 の非競合差分を current main `b3731664834efe34e4d852b79dfb45d1c52def8c` 起点へ統合
- [x] PR #646 作成（10ファイル、behind=0、mergeable=true）
- [ ] #646 Flutter CI / iOS CI / Secret Scan 3成功
- [ ] #646 main統合
- [ ] #642/#643/#644/#645 を重複PRとして整理


### 2026-10-05 Supabase Release preflight PASS
- [x] 本番で余分なanon/破壊系table権限を検出
- [x] production migration `20261004175148 revoke_recent_public_table_excess_privileges` 適用
- [x] repo mirrorを #646 へ追加
- [x] security assertionを実テーブルRLS / security-invoker VIEWに正しく分離
- [x] 本番 `SKO pre-device database security assertions passed`
- [x] onboarding/approval capability marker 10/10 true
- [ ] #646 3CI成功後main統合


### 2026-10-05 Release-only実機経路固定
- [x] device_day.sh 本体はRelease導入のみ
- [x] device_day_preflight.sh のDebug no-codesign buildをRelease no-codesignへ変更
- [x] run_ios_device.sh はRelease署名ビルドのみ
- [x] flutter run 不使用
- [x] 正Bundle ID `com.skworks.skWorks` を実機インストール直前に再検証
- [x] Release-only契約テストを #646 に追加
- [ ] #646 最新head 3CI成功後main統合


### 2026-10-05 Release-only最終強化
- [x] #646で device_day_preflight を unsigned iOS Release build のみに固定
- [x] Debug buildをdevice-day preflightから排除
- [x] run_ios_device.sh は --release を必須化済み
- [x] device-day / installer に flutter run が無いことを契約テスト固定
- [x] Bundle ID `com.skworks.skWorks` 固定契約を維持
- [ ] #646 latest head 3CI成功後main統合


### 2026-10-05 Release候補 最終事実
- [x] current main: `b3731664834efe34e4d852b79dfb45d1c52def8c`
- [x] #646 は current main 起点 / mergeable=true
- [x] #646 Secret Scan成功
- [x] 本番Supabase migration `20261004175148` 適用・#646 mirror済み
- [x] 本番 database security assertions PASS
- [x] 本番 capability markers 10/10 true
- [x] device-day preflightをunsigned Release buildへ強化（Debug buildを除去）
- [x] Bundle ID guard `com.skworks.skWorks` 維持
- [ ] #646 Flutter CI成功
- [ ] #646 iOS CI成功
- [ ] #646 main統合
- [ ] final backup `backup/pre-device-install-20261005-final`
- [ ] 最新mainのCI/Release条件再確認後、1行Release上書きコマンド提示


### 2026-10-06 引き継ぎ：Release導入後の未完了修正
- [x] latest mainを正として再開（古いSHAへ巻き戻さない）
- [x] 引き継ぎ対象を固定：請求書 / 週間表示 / フッター / 通知→承認導線 / 勤務修正・有給反映 / 給料明細テンプレート・実データ連携
- [x] 請求書：会社名上詰め、請求金額枠上詰め、角印案A、金額枠を確認者枠右端まで拡張
- [x] PR #670「Restack invoice empty work content fallback」3CI成功・main統合（merge `8ee6487d6642c6534892b9ac64278bcb8bb9da95`）
- [x] PR #668「Fix attendance correction propagation, current week, footer and approval routing」3CI成功・main統合（merge `e4f8c9ddb71f3fe0c20609e06aaebe555f44de35`）
- [ ] 有給・勤務修正の実データ反映と給与/請求集計への再反映を回帰確認
- [ ] 給料明細を預け済み見本へ合わせ、出勤/残業/早出/夜間/手当/支給/控除/差引支給を実データ連携
- [x] 給料明細プレビューを拡大縮小対応、PDF/印刷/共有と同一帳票生成に統一
- [x] PR #669 は #670 統合後のbase差分解消のため重複整理
- [x] 後継PR #671「Restack payroll statement reference and linked values」3CI成功・main統合（merge `64e290f39c645fac3cebab4ec8602a9f9920d557`）
- [ ] 全修正後、Flutter CI / iOS CI / Secret Scan成功確認 → Release実機導入条件確認

- [x] PR #669 初回CI失敗（印刷余白の確認済み/未確定表示契約）をログ確認し、見本を崩さない小さな余白表示として復元して再CI

- [x] 本番 migration `20261006114652 link_payroll_statement_breakdown` 適用済み
- [x] 自動給与明細detailへ基本給/残業手当/早出手当/家族手当/交通費/所得税/住民税/社会保険/その他控除と勤怠集計を再同期
- [x] 本番自動draftで給与・勤怠リンク項目の存在を確認

- [x] 最終バックアップ `backup/pre-device-install-20261006-final` を最新mainから作成

- [x] 最終main `64e290f39c645fac3cebab4ec8602a9f9920d557`
- [x] PR #671 Flutter CI / iOS CI / Secret Scan 全成功
- [x] 本番Supabase migration `20261006114652` とrepo mirror一致
- [x] Release実機導入経路は `com.skworks.skWorks` 固定・flutter run不使用
- [x] iPhoneへRelease上書きする最終1行コマンド提示可能


### 2026-10-06 取引会社・協力会社 詳細/編集/削除
- [x] 実機報告を受領：取引会社登録/協力会社登録で内容確認・編集・削除ができない
- [x] 会社名タップで登録内容・契約内容を確認できる詳細ダイアログを追加
- [x] 詳細から会社情報編集・契約設定・削除へ分岐
- [x] 編集で会社名/電話/郵便番号/住所/メール/法人番号/備考を更新
- [x] 削除確認付きRPCを本番Supabaseへ追加（migration 20261006122723）
- [x] 「？」ヘルプを詳細/編集/削除導線へ更新
- [x] MacでFlutter 3.47.5が空欄検出されるdevice-day判定を修正
- [x] PR #672 3CI成功・main統合（merge `13f8ce73faeb723c38e3ca0a61392a450a1191db`）
- [x] 取引会社/協力会社の詳細確認・編集・削除導線をmain反映
- [x] device-dayのFlutter 3.47.5空欄検出を修正
- [ ] 最新mainをMacへ取得しRelease実機導入再実行


### 2026-10-06 現場データ項目統一・取引会社削除整合
- [ ] 現場の新規登録・詳細表示・編集で項目を統一
- [ ] 編集画面に「取引先」を追加し、登録済み取引会社から付け替え可能にする
- [ ] 登録者は詳細表示のみ・編集不可
- [x] 取引会社削除はDB削除成功時のみ成功表示
- [ ] 現場/請求書/その他参照中は削除を拒否し理由を表示
- [ ] 現場編集で参照解除後は不要な取引会社を削除可能にする
- [ ] 既存現場・請求データを壊さない契約テストを追加


### 2026-10-06 現場データ項目統一・取引会社削除整合性
- [x] 現場の新規登録・詳細表示・編集で、現場名/取引先/状態/現場正式名称/担当者/現場責任者/責任者電話番号/現場住所/最寄り駅/開始日/終了日/備考を統一
- [x] 編集画面の取引先を登録済み取引会社から選択し、後から付け替え可能にする
- [x] 登録者は詳細表示のみ、編集対象外
- [ ] 取引会社削除はDB削除成功時のみ成功表示
- [x] 現場・請求書等の参照中は削除拒否し、理由を明示
- [x] 現場を別取引先へ付け替え後、参照がなくなれば削除可能
- [x] 既存現場/請求データを壊さない参照整合性テスト追加
- [x] PR #673 3CI成功・main統合（merge `e284e500ec810decd95be6b9432ddd355b23cb02`）


### 2026-10-06 請求書印影・金額枠・管理現場単価・手当名
- [ ] 確認印の印中文字を少し大きくする
- [ ] 会社角印を角印案Bへ更新し、角印らしい四角印影へ修正
- [ ] 確認印枠と請求金額枠を隣接した別枠にする
- [ ] 請求金額枠を請求先名の真下まで上へ移動
- [ ] 管理現場へ請求書用残業単価・早出単価の登録欄を追加
- [ ] 請求書の手当行で手当名を表示し、何の手当か判別できるようにする
- [ ] 画面プレビュー/PDF/印刷/共有で同一帳票生成ロジックを維持

- [x] 請求書下部の「お支払約定日」と「金額」を同じ横幅にする


### 2026-10-06 給与控除自由項目・給与調整反映・支払証明書設定
- [ ] 個別給与設定の「控除」に、名称を自由変更できる追加枠を任意数追加できるようにする
- [ ] 給料明細の控除欄へ追加控除項目を自動反映
- [ ] 給与調整データを給料明細の控除欄へ反映
- [ ] 支払証明書の設定画面を復旧/追加
- [ ] 支払証明書設定にプレビューを付ける
- [ ] 支払証明書の画面プレビュー/PDF/印刷/共有で同一帳票生成ロジックを維持

- [x] 個別給与設定の控除に名称自由・追加数自由の追加控除UIを実装
- [x] 本番に custom_deductions jsonb + 自動控除反映トリガーを適用
- [x] 給与調整の控除を給与明細控除欄へ名称付き表示するPDF連携を実装
- [x] 支払証明書設定を専用RPC保存・再読込検証へ変更
- [x] 支払証明書設定に同一PDF生成ロジックのプレビューを追加
- [x] 支払証明書一覧から設定画面へ直接開く導線を追加
- [x] 管理者・サブ管理者で支払証明書設定を扱える本番権限を反映
- [x] PR #676 は PR #674 統合後のbase差分解消のため重複整理
- [x] 後継PR #677 3CI成功・main統合（merge `350db72a2be9d781808290020b9cbd49a31c4c26`）

- [x] PR #674 3CI成功・main統合（merge `a7dfb39404044fc65c22b1db5218e7659dbe0229`）

- [x] 請求書の確認印文字拡大・角印案B・金額/確認枠分離・約定日/金額同幅をmain反映
- [x] 管理現場へ請求書用残業単価・早出単価を追加し本番DB反映
- [x] 請求書手当行を実際の手当名表示へ修正
- [x] 個別給与設定の自由追加控除・給与調整控除の給与明細反映をmain反映
- [x] 支払証明書設定のRPC保存・再読込検証・プレビュー・管理者/サブ管理者導線をmain反映


### 2026-10-07 実機不具合：請求書が表示されない
- [x] 最新Release実機で請求書が表示されなくなった事象を調査
- [x] 最新mainと本番Supabaseの請求書データ/読込経路を確認
- [x] PR #678 3CI成功・main統合（merge `faf627f4fc445336e003ef9411e8710b70893efa`）

- [x] 本番Supabaseで請求書レコードが残っていることを確認（データ消失ではなく表示/読込経路の不具合）
- [x] 請求先JOIN欠落時にsnapshotのcustomer_nameへフォールバック
- [x] 1件の不正な履歴行で請求書一覧全体が消えないよう読込を分離
- [x] 現在月に請求書がない場合は保存済み請求書の最新月を自動表示
- [x] PR #678 3CI成功・main統合済み（merge `faf627f4fc445336e003ef9411e8710b70893efa`）。Release再導入は最終main完成後に実施


### 2026-10-07 給与明細：支給/控除の自由追加方式
- [x] 個別給与設定を「支給」と「控除」の自由追加方式に分離（PR #685 3CI待ち）
- [ ] 既存表示の「勤続手当・役職手当・家族手当・働き方手当」を支給追加項目として初期表示
- [ ] 既存表示の「介護保険料・厚生年金保険・雇用保険・SKO会費」を控除追加項目として初期表示
- [ ] 給与明細は各追加項目が0円なら非表示、1円以上なら名称と金額を表示
- [ ] 既存の家族手当等の値を壊さず新方式へ引継ぎ
- [ ] 給与調整の加算/控除も同じ支給/控除欄へ名称付き反映


### 2026-10-07 給与明細レイアウト・支給/控除自由追加
- [x] 給与明細のマス目をバランスよく綺麗に再配置（PR #685 3CI待ち）
- [ ] 支給側を自由追加方式にし、既存の勤続手当/役職手当/家族手当/働き方手当を初期項目として移行
- [ ] 控除側を自由追加方式にし、既存の介護保険料/厚生年金保険/雇用保険料/SKO会費を初期項目として移行
- [ ] 追加項目は0円なら給与明細に非表示、1円以上なら表示
- [ ] 給与調整の加算/控除も同じ支給/控除欄へ名称付き表示

- [x] 給与明細右上の「支払日」は個別給与設定で入力した支払日を自動表示（PR #685 3CI待ち）

- [x] 後継PR #685で最新mainへrestackし3CI成功・main統合済み（給与自由追加/5列均等/支払日）


### 2026-10-07 現場詳細：1ページ表示・未登録非表示
- [x] 現場詳細を1ページ内で見やすく表示できるコンパクトレイアウトへ変更
- [x] 未登録/空欄の項目は詳細画面では非表示
- [x] 登録者は履歴情報として表示し、編集対象外を維持


### 2026-10-07 手当単位「回」の名称変更
- [ ] 週間表示・カレンダー表示などの手当表示で固定の「回」をやめる
- [ ] 個別給与設定の手当名称設定に、手当単位（例：回/日/時間/件など）を変更できる項目を追加
- [ ] 既存は「回」を初期値として保持し、変更後は出勤表/月集計/給与関連表示へ反映

- [x] PR #682 3CI成功・main統合（merge `73b0655307bc08a6c83403b80a76f9db7711377d`）
- [x] 後継PR #686 手当単位（回/日/時間/件など）編集 3CI成功・main統合済み（merge `b1f730e141fd6663678392a73c325fbaff528341`）



### 2026-10-07 共通単価自動計算式・支払証明書手当/福利厚生費/消費税
- [ ] 支払証明書設定へ名称変更可能な追加式手当を追加
- [ ] 支払証明書設定へ福利厚生費・消費税を追加
- [ ] 請求書/支払証明書/個別給与設定/現場データで共通の単価自動計算式を利用
- [ ] 1日単価から残業・早出・夜勤・夜勤残業・休日出勤・休日残業・休日夜勤・休日夜勤残業を自動算出
- [ ] 初期式: 残業=1日単価÷8×1.25 / 早出=1日単価÷8×1.25 / 夜勤=1日単価×1.5 / 休日出勤=1日単価×1.35 / 休日夜勤=1日単価×1.6
- [ ] 各計算式の数値を変更・保存可能にする
- [ ] 自動計算値を直接上書き入力可能にする
- [ ] 各単価入力枠の下に実際に使用した計算式を表示
- [ ] ページ全体の入力項目を見やすくバランス良く整理


### 2026-10-07 共通単価自動計算・式編集・支払証明書追加項目
- [ ] 支払証明書設定に名称変更可能な手当追加方式を追加
- [ ] 支払証明書設定に福利厚生費・消費税を追加
- [ ] 請求書/支払証明書/個別給与設定/現場データで共通の自動単価計算を導入
- [ ] 対応区分：残業/早出/夜勤/夜勤残業/休日出勤/休日残業/休日夜勤/休日夜勤残業
- [ ] 1日単価入力で初期式から自動算出
- [ ] 初期式：残業=日額÷8×1.25、早出=日額÷8×1.25、夜勤=日額×1.5、休日出勤=日額×1.35、休日夜勤=日額×1.6
- [ ] 計算結果の枠下に計算式を表示
- [ ] 単価の直接入力も可能
- [ ] 計算式の係数/数字を編集保存可能
- [ ] 各設定ページのレイアウトを見やすくバランス調整

- [ ] 時給設定時も同じ倍率計算方式を使用（残業/早出×1.25、夜勤×1.5、休日×1.35、休日夜勤×1.6。日給時のみ÷1日時間を挟む）

- [ ] 日額だけでなく時給を基準にした場合も同じ倍率体系で残業/早出/夜勤/休日系単価を自動計算し、式編集・直接入力を可能にする


### 2026-10-07 単価自動計算・計算式編集・支払証明書手当
- [ ] 支払証明書設定に名称変更可能な手当を追加方式で登録
- [ ] 支払証明書設定に福利厚生費・消費税を追加
- [ ] 請求書/支払証明書/個別給与設定/管理現場で1日単価から各種単価を自動算出
- [ ] 初期式：残業=1日単価÷8×1.25、早出=1日単価÷8×1.25、夜勤=1日単価×1.5、休日出勤=1日単価×1.35、休日夜勤=1日単価×1.6
- [ ] 夜勤残業/休日残業/休日夜勤残業も共有計算式で算出
- [ ] 各単価は自動計算値を直接上書き入力可能
- [ ] 各項目の枠下に計算式を表示し、倍率/式を変更保存可能
- [ ] 共有計算ロジックで画面間の単価算出を統一
- [ ] 参考画像の深夜割増/深夜残業/休日深夜の考え方を初期式へ反映
- [ ] ページ全体をバランスよく見やすく整える

- [x] 共通単価計算の本番関数で日給16000/時給2000とも残業2500・夜勤24000になることを確認
- [x] 日給/時給モード・式編集・直接入力・計算式表示を最新mainベースのPR #688へ統合
- [x] 支払証明書設定の名称自由手当・福利厚生費・消費税・プレビューをPR #688へ統合
- [x] 個別給与設定へ日給/時給共通式を追加し既存の支給/控除自由追加・支払日・均等5列給与明細を維持
- [ ] PR #688 最新SHA `6a7d55f39196f7220c14b1d8ecd4fe5fd971d9d4` で再CI中。Secret Scan成功。Flutter契約テスト1件の期待値修正済み。Flutter/iOS成功後main統合


### 継続検証 2026-10-10 02:20 JST

- [x] 税率設定・所得税年度PDF管理・同一会社の画面導線を統合した Draft PR #849（a45715365d4cf42055f9b448331a3329f91087f4）の Flutter・iOS Debug/Release・関連SQL・Secret Scanがすべて成功。公式料率自動確認、源泉徴収税額計算、本番反映の完了とは区別する。
- [x] 住民税 Draft PR #848 は PostgreSQL 17 の実SQLと2接続の同時保存競合検証に成功。後着の古い版による保存を拒否し、将来予約によって現行給与行を変更しないことを確認。最新修正 ebcfa7385b3c54b1113276209b0aff62d5cc15e8 の Flutter・SQL・PostgreSQL 17 は成功、iOS確認継続。
- [ ] 給与確定の保存・読み出しAPIは source-stage。確定済み行の表示で現行会社設定・調整額を読み直す依存を除去し、通常の給与更新APIとのロック順序と画面/PDFの保存値参照を継続実装する。本番DBには未適用。


### 継続実装 2026-10-10 02:36 JST

- [x] Draft PR #850 に給与確定時の条件・結果・明細の保存APIを追加。head18191706c58efa75d54f9c97e18f98a8c6e8d74d で PGlite と実 PostgreSQL 17 の同じ原典・実トリガー検証が成功。保存値の不変性、本人のみ銀行情報、監査失敗の全体rollback、旧明細非移行を確認。
- [ ] #850 の通常更新API間の同時操作は別stageで継続中。新しい確定ボタンは未接続、本番DB未適用。現行会社料率・源泉徴収表を給与計算へ採用した完了とは扱わない。
- [ ] Draft PR #851 に明細画面・PDFで現在の確認状態を明示下書きだけに適用する修正を追加。管理明細の保存会社名を保持し、状態不明の旧明細を下書きと推測しない。Flutter/iOS CI確認中。


### 継続検証 2026-10-10 03:04 JST

- [x] 給与確定・表示の Draft #850 最新 b45a6960633fe514d43b77694063c609457aeb41 の給与scope SQLが PGlite と実 PostgreSQL 17 で成功。実RPCで逆worker順の署名、車両更新×署名の両開始順、待機中の対象変更40001拒否、会社SHAREと人事子テーブルFK KEY SHAREの互換を確認（workflow37970307755/native job113954934835）。確定後の確認取消で保存確認状態を変えず、期間・発行日も保存値を返す。
- [ ] 上記は既知の署名・車両・現場・取引会社・勤怠/有給triggerの限定stage。全給与更新入口の保証ではない。勤怠修正・有給申請/決定・日報取消/再編集・単一従業員の個別給与設定保存の事前ロックを次stageで継続中。本番DBは未適用、確定ボタン未接続。
- [ ] 独立修正 Draft #852 は数値に見える会社/社員名やsnapshot版番号をPDFの支給/控除へ入れない。保存給与5fixtureの実PDF合計/差引/ラベル/元データ不変の回帰テストを追加し、Flutter CI成功、iOS Release確認中。
- [x] 新しい住民税・所得税・料率画面のnow/JST境界を照合。now瞬間はUTC+9、登録日付はcivil値を保持しており月初・年度の不要な変換を追加しない。


### 継続実装 2026-10-10 03:27 JST

- [x] #852 の実PDF回帰検証・Flutter・iOS Debug/Release・Secret Scanがすべて成功し、main `ab6d445c905ca55815ac7f68c8bc720c98d32b52` へ反映。数値に見える保存metadataを支給/控除へ加算しない。
- [ ] #850 の旧文字列依存テスト1件をshared parserの実際の確認状態テストへ修正し、head `895dcfcdd4d2941437402c92cbae2ca6a865ed5c` で再CI中。前headではSQL/実PostgreSQL17すべて成功、Flutter1030件成功・旧契約1件失敗だったため全CI完了とは扱わない。
- [ ] 新しいDraft #853 に通常給与更新の11sourceファイルを追加。root独立PGliteで実原典8入口、取消監査、raw RLS、非member専門家の委任保存を確認。実PostgreSQL17の同時操作検証は継続中。本番DB未適用、任意bulk/全入口の保証・確定ボタン接続は未完了。


### 追加指示と継続実装 2026-10-10 03:36 JST

- [ ] 税率設定の二重枠を整理。確認済みの同一companies.tax_rate重複編集をDraft #854で一本化し、一般設定保存で古い税率を書戻さない。ローカルモード既存編集は保持。Flutter/iOS CI継続。
- [ ] 税率設定ページは同社の閲覧者も閲覧可能にする。読取と管理者保存/適用を分離し、同社DB所属・有効アカウント・現存会社を必須とする。画面は現在値/確認値/適用月/情報元を表示し、閲覧者に変更操作を出さない。料率読み取り・UI実装中、所得税資料の閲覧権限は別途継続。
- [x] 通常給与更新Draft #853 最新e02fc385b47bf949d37b2ac1d0f63e2f9b77c9dfは実PostgreSQL17（workflow37973872455/native job113967076522）およびPGlite成功。逆順の勤怠操作40001再試行、取消/署名、調整/確定版拒否、確認取消/単一設定、専門家UPSERT/raw UPDATE両順、新規設定競合と削除待機後UPSERT、待機中新給与月の追加拒否/rollback/再試行を検証。任意bulk・全入口・本番適用・確定ボタン接続の完了ではない。


### 閲覧者対応の継続検証 2026-10-10 03:42 JST

- [x] Draft #855（48cff3717e5f6b2364328764c35c45d7826726ae）の会社共通料率read/write分離はPGliteと実PostgreSQL17で成功（workflow37974852745/native job113970441781）。同社owner/admin/viewer読取、viewer現在値/確認候補/適用月/情報元の表示、変更操作拒否、管理者結果/保存関数の維持、他社/未所属/匿名/無効アカウント/削除会社の拒否を検証。Flutter/iOSは継続、本番未適用。
- [ ] 所得税年度・適用期間・PDF資料も閲覧者へ読取専用で接続中。UIは所得税登録/再uploadを管理者のみ表示、同社登録済PDFのsingle read/signだけを許すStorage分離を次source stageで実装。未登録orphan/他社/list/sign_many/upload/delete/upsert/無検証共通化は閲覧対象に含めない。旧年度登録済資料を保持し、閲覧を資料検証や実給与採用と同一視しない。


### 所得税資料の閲覧者対応 2026-10-10 03:49 JST

- [x] Draft #855 を料率＋所得税資料の閲覧者対応へ集約。最新fe1032858d2ddaaef6ceb00c5482550581b3d16fの所得税viewer SQLはPGlite・実PostgreSQL17で成功（workflow37975832730/native job113973767877）。同社現在/旧年度/旧登録版のmetadataと単体PDF get/sign、viewer更新/登録拒否、他社/foreign history/未登録orphan/list/sign_many/無効アカウント/匿名/削除会社の拒否、管理者の既存保存/未検証扱い保持を確認。
- [ ] 同headのFlutter/iOS CIは継続。実Storage HTTP/JWT/bytesとiPhone PDF外部launchは未検証、本番DB未適用。今回の閲覧者対応は資料の正式検証・共通化・実税額計算の完了ではない。


### 指定初期料率の再確認・引継ぎ 2026-10-10 03:57 JST

- [x] 過去ユーザー発言（2026-10-09 21:44〜21:47 JST）から指定初期値を取得：健康保険9.9%、介護1.62%（40〜64歳）、厚生年金18.3%、雇用保険全体1.65%/従業員0.6%/会社1.05%、子ども・子育て支援金全体0.23%。健康/介護/厚生は原則労使折半。以前の『指定値不明』は当時の検索失敗による履歴であり、現在は解消。
- [ ] 上記を新規手動設定の初期入力値へ実装し、既存設定/給与を自動上書きしない。適用月・情報元・本人確認を伴う管理者保存は維持。支援金の負担内訳はユーザーの明示が無いため未確定、公式資料で照合してから実装する（直前の公式検索はユーザー中断、取得結果無し）。指定値を最新公式確認値と同一視しない。
- [ ] 次スレッドは最新mainと#854/#855/#853のexact-head CIを再確認して再開。#854 add684f066e45a54fe1441dcb7c33f5f48bff4d8 はFlutter/Secret成功、iOS継続。#855 fe1032858d2ddaaef6ceb00c5482550581b3d16f は閲覧者の料率/所得税PDFの実PostgreSQL17成功、画面/iOS検証継続。最新main ab6d445c905ca55815ac7f68c8bc720c98d32b52。本番DBはこの給与追加stage未適用。


### 2026-10-11 実機指摘・優先修正
- [x] PR #890 税率設定・経費申請を既存メニュー／ホームON/OFF／並べ替えへ統合。Flutter CI・iOS CI・Secret Scan成功後にmainへマージ（9215eb55792327a1a480edf92f4722c852c51087）。iPhone Release上書きと実機確認は未完了。
- [ ] 給料一覧：ログインできない。既存認証／権限を壊さず導線・エラー原因を調査。
- [ ] 書類登録／必要書類登録：写真を追加式（複数枚）にしてプレビュー可能にする。
- [ ] 角印：登録した印がプレビューに出ない不具合修正。
- [ ] 支払証明書：自社会社名を右へ寄せ、角印が重なる配置へ修正。既存テンプレートを保持。
- [ ] ルート出勤：出勤後は現場到着ボタンだけ青・押下可、到着後は現場移動ボタンだけ青・押下可。到着・移動ボタン欠落を復元。既存の勤怠記録・状態遷移を保持。
- [ ] Release版の既存SKOへの上書き・起動・ボタン実機確認（Bundle ID com.skworks.skWorks、Debug禁止、削除禁止）。


### 2026-10-11 ソース復旧用バックアップ保存先（Mac）
- [x] 保存成功：`/Users/ryuichi/SKO-source-backups/pre-install-20261010T182952Z-M3Tuj7`
- [x] `analysis_options.yaml` の未保存変更はGit stash `SKO-backup-20261011` に退避済み（削除していない）。
- [ ] この保存はソースコードのみ。Supabase本番DB、Storage（写真・書類・角印）、iPhone内データの復旧用バックアップは別途必要。実際の取得・復元検証が完了するまで完了扱いにしない。


### 2026-10-11 書類・資格の写真追加式（追加指示）
- [ ] 書類登録・必要書類登録・資格登録の3画面で、1枚固定ではなく複数写真を追加可能にする。表面／裏面を別々に撮影・追加し、3枚目以降も許容する。
- [ ] 撮影／選択済み写真の一覧と個別拡大プレビュー、登録後の再表示に対応。既存1枚データを保持し、保存先・権限・承認処理の整合性を検証する。
- [ ] 既存データの削除・置換は行わず、互換性を維持する。未実装・未テストは完了扱いしない。


### 2026-10-11 CI成功・main反映
- [x] PR #891 支払証明書の自社会社名右寄せ＋角印重ね：全CI成功、mainマージ `db8eadfbbbe6fcda76d7cabc81ffca56516f076d`。実機帳票の見た目は未確認。
- [x] PR #892 ルート出勤の現場到着／現場移動ボタン：Flutter/iOS/Secret成功、mainマージ `75855a2e3e67be850ef919e032813cfae4907151`。実機状態遷移は未確認。
- [x] PR #893 角印プレビューの会社整合性チェック・選択中表示明確化：Flutter/iOS/Secret/書体契約成功、mainマージ `40f8742aafcc029e6215dc72102b88acae2205b3`。保存済みフォントの表示不具合そのものの解消は未確認。
- [ ] 最新mainからRelease版をMacで上書きし、既存SKOを削除せず実機確認。書類・資格複数写真と給料一覧ログインは未完了。


### 2026-10-11 ルート出勤→日報連携の確定仕様
- [ ] 手動方式：出勤、現場到着、現場移動、次現場到着、次現場移動、退勤の各実操作時刻を記録。GPS・写真は要求しない。
- [ ] GPS＋写真方式：現場到着時に時刻・GPS位置・写真を記録。現場移動時は時刻のみ記録。次現場到着時に再び時刻・GPS位置・写真。出勤・退勤は既存記録仕様を維持。
- [ ] 出勤後は現場到着のみ青・操作可、到着後は現場移動のみ青・操作可。現場ごとに交互に切り替え、退勤で終了。青以外は操作不可。
- [ ] 実際の記録を現場名・時刻の順で日報に自動表示し、GPS＋写真の到着証跡を紐づける。記録の二重作成を禁止し、既存勤怠・日報・承認・RLSを壊さない。
- [ ] 現状のPR #892はボタン表示と既存訪問保存が中心で、手動方式・日報連携の完了ではない。実装・テスト・実機確認が必要。


### 2026-10-11 帳票角印が表示されない件・読取専用調査
- [ ] 請求書・給与明細・支払証明書で登録した角印が表示されない実機報告。3帳票のPDF描画処理自体は存在するが、各帳票の保存済み `company_seal_snapshot` を参照しており、現在選択した印影と一致しない可能性。
- [x] 本番Supabaseのスキーマ・件数のみ読取確認。`invoices` 2件中 `company_seal_snapshot` キーあり1件、なし1件。`payment_certificates` 0件。過去帳票の印影が現在設定と異なる可能性を裏付けるが、全帳票の原因確定ではない。
- [ ] 既存確定帳票のスナップショットは変更しない。新規プレビューの印影選択と新規保存時のスナップショット生成を確認し、保存済み設定が3帳票に正しく適用されるよう最小修正・テストする。既存DBデータ更新・破壊的migrationは禁止。


### 2026-10-11 実機スクリーンショット：ホーム勤怠カードに到着／移動ボタン欠落
- [ ] 実機画像で手動出勤03:04、出勤中、複数現場ルート選択済みなのにホーム「本日の勤怠報告」カードは出勤／退勤ボタンのみ。PR #892で増やしたボタンは `route_journey_capture_page.dart` 内であり、`friendly_home_content.dart` の `_PersonalAttendanceCard` には未接続。`app_v2.dart` のホームonOpenにも訪問記録用の遷移キーがない。
- [ ] ホームへ「現場到着」「現場移動」を追加し、実際の勤務のsource_clock_in_idと訪問状態を読んで正しい記録画面／保存処理へ接続。出勤中のみ状態に応じた青いボタンを操作可能にし、手動は時刻のみ、GPS＋写真は到着時に位置・写真、移動時は時刻のみ。未取得・エラー時は安全側で無効化。既存出勤／退勤、DB/RLSを破壊しない。
- [ ] ホーム画面・記録画面・日報連携・Release実機の一連のテストが必要。現時点ではホーム表示未完成。


### 2026-10-11 並走調査：給料一覧ログイン
- [ ] `lib/app_v2.dart` の `payroll_review` は `SecondaryProtectedPage(title:'給料一覧', child:PayrollReviewPage())` を使用。第2認証画面 `lib/features/auth/secondary_protected_page.dart` の `_loadState()` はRepository/ユーザーがnullの場合に早期returnし、ロード中表示が残る可能性。実機のエラー表示・認証状態と照合して原因を確定する。認証処理は未変更。
- [ ] PR #894はホーム→ルート訪問記録画面への部分導線。現在の実勤務 `openShifts.single.routeId` を使って表示条件を修正。独立した青い到着／移動ボタンと手動記録は引き続き未実装。


### 2026-10-11 並走調査：複数写真の既存データ保護
- [ ] `company_submitted_documents_page.dart` は写真を1枚選択して即 `repository.upload`。`company_submitted_document_repository.dart` の `upload` は `company_required_documents.attachment_path` 単一カラムを新パスに置換し、旧Storageパスを削除する仕様。単純な複数回uploadは表裏写真を消失させるため禁止。
- [ ] 複数写真対応は既存添付を保持する追加型の添付データ構造、個別プレビュー、登録済み履歴の読込、RLS/承認整合性の確認が必要。DB変更前に本番バックアップを確認。資格登録も同様に個別調査。


### 2026-10-11 複数写真仕様の補足（ユーザー確定）
- 既存の古い写真は、新しい表裏写真等が正常に保存・確認できた後なら削除可。保存前の削除は不可。
- 「写真を追加」で1枚ずつ増やし、表・裏を同じ書類／資格に保持する。3枚目以降も追加可能。個別プレビュー対応。
- 現行 `attachment_path` の上書きで表面が消える実装を、そのまま複数写真UIへ流用しない。旧写真削除許可は、登録済みの別の写真を上書き消失させる許可ではない。


### 2026-10-11 進捗：PR #894 main反映
- [x] PR #894 `efc48092ccef77008a8f1fa206e0dcff1f860259` Flutter/iOS/Secret全成功、mainマージ `d9b1d7a75e90e7cd9f9456fb1a27a2bbf635f7b6`。ホームから現在の単一ルート勤務の途中現場記録画面へ移動する導線を追加。
- [ ] ただし独立した青い到着・移動ボタン、手動時刻のみの保存、日報自動反映は引き続き未完成。実機確認も未実施。


### 2026-10-11 給料一覧第2認証ロード停止対策
- [x] PR #895 `7ebcd58238a2c9280411a0d9821a96893bd415e5` Flutter/iOS/Secret全成功、mainマージ `d45214dd8e5ce38276e9528c1bb7cb2ce9acd96c`。ログイン情報不在や初期状態取得失敗で無限ローディングせず、エラーと再読込を表示してfail-closed。第2パスワード検証ロジックやDBは変更なし。
- [ ] 給料一覧への実際のログイン成功は実機未確認。別原因の場合は継続修正。


### 2026-10-11 複数写真の安全性確認（読取専用）
- [x] 本番 `company_required_documents` は3件、現時点で `attachment_path` 登録済み0件（件数のみ確認、個人データ未取得）。既存の他書類・資格・Storageデータの不存在は意味しない。
- [x] PR #896で `DocumentPhotoDraft<T>` と表裏の追加・順序保持・個別プレビュー、テストを追加。保存はまだ無効であり未完成。
- [ ] 複数枚の永続化には別添付構造とRLS/Storage権限を検証する。DB/Storageバックアップ取得前の本番DDL・データ削除は行わない。


### 2026-10-13 作業優先順位と最新UIの範囲

- 最優先はLINE以外の仕上げとiPhone Release上書き。最新mainを維持し、未保存差分の破棄・巻戻し・既存アプリ削除・Debug導入・flutter runは禁止。Bundle ID com.skworks.skWorks。導入前バックアップを行う。
- #963無料OpenWeatherと#958交通ボタンはmain反映済み。無料API成功・本番キー登録済みと、アプリ/実機表示確認は別に記録する。追加契約・請求先登録は行わない。秘密値を表示しない。
- #965請求書プレビュー回復、#966日報現場/月カレンダー、#970ホーム/天気/交通6点除去等はmain反映済み。請求書の実機白紙解消は未確認。日報の写真付き/無しは実際に写真記載のある/ない保存済み日報の分類であり、出力形式を増やす意味ではない。
- #972ルート数量の根拠案内は全8CI成功、main afbc316dd06ae9bf8c65590599adb69fa8f622a6・本番反映済み。既存60関数/8表は保持。過去の退勤日時や人工を推測登録しない。iPhone表示は未確認。
- 新UI #975の変更対象は本人書類/本人資格/管理側社員書類/管理側社員資格の4一覧のみ。共通カード・操作・実添付プレビューを統一。書類0/1/実2枚、資格表裏2位置、追加添付/既存機能/権限を保持。基本情報・給与・勤怠等の別画面へ広げない。最新CIの問題修正/再検証中、main/実機未反映。
- 新UI #974は通常SKOチャットの名前上寄せ・本文最大2行・日時右上・行と5タブの未読数字・グループ写真。分類/青系/既存権限を保持。最新CI再検証中、main/本番/実機未反映。
- LINEは独立並走。#952/#956の骨組みを維持し、公式アカウント参加グループの実投稿保存/表示は本番連携と実投稿で確認する。SKOから返信しない。#969履歴月別単価・小計はmain/本番済み。#973正式請求書橋渡しは過去の明示単価/税福利条件を保持し、未承認・未確定・未編集の下書きのみ登録経費再確認。最新CIは8成功/iOS継続、main/本番未反映。9月17日を最終日と断定せず、保存対象期間を確認。実人数と延べ人工を区別。
- 給与保存・計算・日報数量から給与への接続はMac Codex担当を維持。同じファイル・DB・認証/権限を並行変更しない。専用セキュリティ追加・Web版は開始しない。各作業は実装/CI/main/本番/iPhone導入/実機確認を区別し、画面変更の「？」を更新する。
