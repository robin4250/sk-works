# Release20 統合・導入記録

基準 main: `22ba6ec4349c66a14244fc76f0e823a0831ae142`。既存build19とその成果物は保持する。新たに作るReleaseはbuild20とし、既存番号の再作成や番号変更だけの配布は行わない。

## 統合する検証済み修正

- #1417 `a72282bd`：日報は面表紙のある報告単位で数え、添付写真は加算しない。サイン枠へ「画面を横向きにしてサインしてください」を表示。全対象CI成功。
- #1418 `24d1aa2a`：Apple連携の準備状態を認証イベント履歴に束縛。Appleの利用開始を意味しない。
- #1421/#1423/#1425 `3b67e32e`：第二認証の履歴保護・旧再設定fallback禁止・既存Google/Face ID保持、登録共通手当UI、個別/一括の登録・編集・削除の操作proof接続。最終16 CI成功。Functions SDKの実isolate完了を待つUI検証の上限だけを統合時に拡大し、遅い実機のfixture待機不足を避ける。
- #1422 `eddca834`：登録共通手当ID・版・既存明細の保持。製品SQLは`f26d761`から不変。Native109、独立した未使用復元55成功。
- #1424 `4e1e8e59`：既存第2PWの無証明上書きを閉鎖し、実PW検証と操作proof発行を原子化。PW変更で旧grantを拒否。実writer Native108・実Auth/Edge検証・全自動CI成功。
- #1419 `1b0255cc`：書類専用日報の明示手直し→実績確認→通常経路の新しい実サイン。Native transition111/readiness75、未使用復元で原本・ACL・署名trigger・データ一致を証明。
- #1426 `baf8cdc3`：全員の実区分・適用手当・必要時間を確認して一括保存し、再読込後に新しい報告者/現場責任者サインへ進む。source-anchor/再起動でも旧draft writerを回避。97対象tests・全15 CI成功。

## 残る利用上の条件

Appleの新規利用は準備中。#1420のbroker/Swift/Flutter adapterはOFFの検証候補として別保存し、このReleaseで有効化しない。Googleの新しい本人認証取得保証、trusted challenge接続、PKCE連携前の防止策、実provider設定が未完了。

第2PWを忘れたGoogle-only利用者の安全な回復brokerも未完成。忘れ回復は準備中とし、通常Google/Face IDログインと既知の第2PWによる変更は保持する。device proof候補の新規導入は対象外。

過去の未作成日報や実績を自動生成しない。既存の打刻・写真・実サイン・履歴を保持する。書類専用日報を給与実績へ移すには、本人/管理者が実際の区分・適用手当・必要時間を確認し、実際に両サインを取り直す必要がある。勤怠6日と給与/請求2日の数値を推測で一致させない。請求書の最終実額/実日数は実入力後に確認する。

## 導入順と復元

1. 本番原本・所有者・ACL・source pinsを照合し、バックアップを更新する。本番への追加モジュールは全てdefault OFF。既存データdigestと実署名の不変を確認する。
2. readiness→financial transition、registered allowance→core proof→attendance proofの各依存順を守り、一担当が順番に適用する。Apple/未配備device proofは導入しない。
3. 本番復元SQLには取得した正確な原本・ACLを使用する。未使用OFFの場合だけ、attendance→core、管理共通手当、financial transition→readinessの依存逆順で復元する。使用済みの履歴/署名/実績を消すuninstallは行わない。
4. 統合mainの必須Flutter/iOS CI成功後、exact SHAで新build20 Releaseを作成する。Mac操作は利用者が実行し、アップロード/実iPhone導入結果を確認する。
5. 旧build19はproof非対応のため、新しい第二認証の強制はbuild20の実iPhone導入確認後にする。旧setter閉鎖とattendance enforcementは同じtransactionで有効化し、read-only capabilities/権限を照合する。既存Google/Face IDと本人ID/会社は保持する。

この記録の作成時点では本番・main・既存build19は変更していない。最終cohortの必須CIと本番導入の証跡は別途追記する。
