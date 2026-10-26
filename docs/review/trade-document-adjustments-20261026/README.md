# 帳票の項目加減算候補（未配備）

Base main: `9b2095cf121374de943990abd46cf58afc09b544`。
本番へのSQL適用・有効化・統合・Release作成・iPhone導入は行っていない。
CI、採用PDFの描画比較、Native PostgreSQLでの真の並行試験が終わるまで
完成または本番適用可能として扱わない。検証済みbuild20/21のIPAを再作成しない。

## ユーザー指定

両帳票に「項目を追加（＋／−）」を置く。
請求書では取引会社、支払証明書では協力会社を選び、項目名・正の整数金額・
加算/減算・「今回だけ／毎月」を指定する。編集、当月取消、毎月設定の今後の
編集/停止を区別する。削除は履歴を残す取消とし、過去確定帳票を書き換えない。

各項目の計算方法はユーザー回答により次の2種類。

- `before_charges`: 既存の税・福利厚生を適用。請求書では必要な対象現場を選ぶ。
  元の自動計算の福利/税集計の直前へ明細を入れ、既存の丸めをそのまま用いる。
- `settlement_yen`: 入力額をそのまま最終額に加減算。追加の税・福利を計算しない。
  請求書の税/福利/小計を変更せず、支払証明書では加算をgross、減算をdeductionsへ反映。

画面で税率を仮定しない。プレビューは保存済みの実source設定を使い、同じrequest・
source版・結果に結び付けたサーバ保存tokenを登録時に照合する。登録後に実refreshで
再計算した合計がプレビューと異なる場合、台帳変更を含む全トランザクションを取り消す。

## 構成

- 新private台帳: 会社、帳票種別、相手、月、毎月設定の版、各月occurrence、取消、
  append-only操作受領・監査。直接client権限なし/RLS有効。
- 公開API: read/preview/apply/lookup。現在の再認証session・会社membershipを毎回確認。
  invoiceは既存can_manage_invoices、payment_certificateは既存owner/adminを維持。
- 冪等: actor+command UUID+request全文、scope版CAS、毎月設定版CAS。
  保存不明時に新UUIDで自動再送しない。同じ不変commandでの明示再試行は可能。
- 将来既存draftは年月順で再計算しscope版を更新。確定/承認済は対象外。
- 原自動計算3関数の捕捉定義から生成。prosrc MD5が異なる場合に導入を拒否し、
  新しいtrade_document_source等を古い保存版へ戻さない。OIDを維持するCREATE OR REPLACE。
- 新規rollout行なしが既定OFF。OFFへ戻すと加減算済み帳票の自動再計算を停止して
  保存額を保持し、加減算のない既存帳票は元の自動計算を継続する。

## 検証済み（隔離した合成データのみ）

`verify_adjustment_arithmetic.mjs`: PGlite 301項目。
丸め境界、減算の変更前後差、会社/相手/帳票種別分離、開始月・毎月停止・当月取消、
既定OFF、直接schemaアクセスなしを確認。

`verify_adjustment_real_refresh.mjs`: PGlite 45項目。
捕捉した本物の自動invoice/payment/certificate計算関数を実行し、両帳票の
税後加算、計算前減算の福利/税込み結果、編集/取消、毎月翌月発生/停止、
再refreshでの金額維持、同command再試行、異payload拒否、CAS拒否、確定後保存拒否、
確定snapshot保持・台帳への捕捉、一般社員/未所属/異種相手拒否、private直接読取拒否、
audit変更拒否、導入二重実行拒否を確認。
認証session helperとexpense-v2 OFF判定はfixture用の代用であり、
本番認証境界やv2 ONとの統合確認の代替ではない。

Flutter/Dartはローカルで実行していない。共通画面/接続15件とsnapshot4件の
テスト候補はCI未実行。従来のPDF/frame regressionもCI未実行。

## 導入手順（root所有。未承認・未実施）

1. rootでCI・Native並行・expense-v2 ON・PDF renderを完了する。
2. 最新main/実関数MD5/既存migration/確定状態を読み取りで再照合。
3. 対象schema・3関数・対象帳票のprivateバックアップと復元検証。
4. `document_adjustment_install.incomplete.sql`を完成確認後に一つのトランザクションで適用。
   componentファイルを個別に本番適用しない。rolloutはOFFのまま。
5. 対応版の所有者iPhoneへ導入し、特定会社のみ段階有効化して実整合を確認。

## 退避・復旧

緊急停止は会社のrolloutをOFFへ戻し、台帳/commands/audit/保存帳票を残す。
金額を保持したまま新規変更を拒否し、加減算済み帳票のrefreshを止める。
その状態で原関数だけを戻すと、後続refreshが調整額を失うため行わない。
原関数へ戻す必要がある場合は、調整済みdraftを別途安全に保護する具体差分と
バックアップ復元をrootでレビューしてから行う。台帳や過去確定snapshotを削除しない。

## 残る確認

- CI analyzer/widget/repository/PDF tests、描画比較。既定header/footer/署名枠を維持。
- Native複数sessionの同時apply/承認/refresh、毎月編集と当月操作のlock順。
- expense-v2 ONの実helper/readerと税後plus/minusの内訳整合。
- アプリ終了時のpending request端末復旧は未実装。再起動後はサーバの最新一覧と
  scope CASで競合する旧requestの二重登録を防ぐが、前回commandの専用再開表示はない。
- rollout設定・production監査閲覧/保存期限は既存管理方針と統合してから有効化。
