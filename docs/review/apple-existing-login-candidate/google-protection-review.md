# 全Google UIDと直通Apple自動リンクのOFF候補

この追加候補は未統合・未配備・既定OFF。既存のowner-policy hook、保護UID、
同UID Apple subject permitを再利用する。一般の再認証、勤怠の第二パスワード、
給与、会社所属、署名、Apple/Google provider設定は変更しない。

## 対象と動作

既owner-policyのtoken hookだけでは、PKCEでidentityが先にコミットされた後に
token発行を拒否してもidentityを取り消せないことが実証済みである。そのため
追加のdefault-OFF `auth.identities` BEFORE INSERT/UPDATE/DELETE guardを用意する。
Auth user/identity行を別UIDに編集する補修処理や削除の捏造は行わない。

- 全既存Google identityのUIDを、表ロック下で既保護UID台帳へ登録する。
- 新しい正規Google identityも同じ取引で保護する。user_metadata、email一致、
  callerのprovider自己申告から保護対象を選ばない。
- 保護されたGoogle UIDへのApple identity書込は、実確認済み同UID permitが
  必要。token hookに届く前、PKCEの早期identity取引でも拒否する。
- 未承認Apple-first UIDへGoogleを自動合流する逆経路もidentity書込前に拒否。
- 一度観測したGoogle provider subjectは元UIDと紐付けて保持する。Googleの
  unlinkやAuth user削除で台帳は連鎖削除しない。公式soft deleteの消去/難読化は、
  実deleted_at・同UID/provider/行ID・公式SHA256式が一致する場合だけ通す。
  user_metadataのdeleted_atでは許可しない。その後のcascade hard purgeも妨げず、
  難読化subjectを本物として台帳へ増やさない。元UIDへの復帰は許容し、
  削除後に同じGoogle subjectから黙って新UIDを作る経路は拒否する。
- 正規のGoogleログイン・新規Google登録・メールPWは維持する。既Googleと
  Appleが未承認状態で混在していれば有効化をSTOPし、permitを自動作成しない。
- token-hook側のrolloutが後でOFFになっても、有効なwrite guardは無効化しない。

Googleまたは登録subjectと関係のないApple-only新規登録は、今回の最小候補では
旧挙動を維持する。これはアプリ全体のApple新規登録whitelistではない。
全Apple書込にpermitを要求する政策は、既Apple-only利用者と正規登録フローの
影響を別途照合する必要がある。

## 切替・復旧の境界

install時はrollout行・Google所有台帳を追加しない。Auth行の書換・providerの
有効化・hook設定も行わない。`enable_reviewed()`は公開/一般/管理者JWT/
service_roleへ実行権限を与えないowner専用であり、通常画面から呼ばない。

ownerによる有効化はGoogle identity表をロックし、既存Googleと既Appleの
整合性を確認、全件保護、既hookとwrite guardのONを一つの取引で行う。
Google subjectの形式不明、既Appleの同UID permit不足、既に使用した切替履歴
ならSTOPする。資料取得やフラグだけを有効化成功としない。

disable/ロールバックでは、先にApple provider/関連入口を安全に停止してから
別途手動レビューが必要。token hookだけに戻すと既知のPKCE境界が再開する。
使用後に保護/subject所有台帳や登録済みpermitを削除して未使用復元と偽らない。
削除済みsubjectの再登録、誤検知解除、台帳の保持期限/復旧/未使用復元の正式な
操作経路はこの候補にまだ含めていない。本番有効化前の未達条件である。

## 検証

- PGlite固定0.5.8：OFF/ACL、全Google seed、新Google/メールidentity維持、
  metadata改変、Apple直通/UID変更、同UID permit、逆方向の自動合流、混在STOP、
  unlink/削除/再作成、後続失敗rollback、hookフラグ漂流、公式soft deleteと
  metadata偽装、切替前soft-deleted行を含む14ケース。
- Native PostgreSQL 17：同14ケースと実二接続Google/Apple同UID競合をCI実行。
- 本番報告と同じ公式GoTrue v2.197.0 source
  `4eee58f296d9698a1c2c0ae14d7a0b379c7622d3`：実HTTP/RSA native token、
  PKCEの先行identity取引、Google新規/既ログイン、メールPW、同UID Apple許可、
  metadata自己編集、hard/soft削除/再作成、unlink後の元UID復帰、未知ACKを想定した
  Google再送の同UID保持と元refresh保持をCI実行。
  provider公開鍵は合成鍵のみ、外部通信は固定のoffline transportで拒否する。

実GoTrue/Native CIの結果、既存本番catalog/trigger/owner/権限差分、本番配備、
hosted hook/native-only条件、入口/復旧/保持期限、iPhone確認は別々に記録する。
特にmanaged Auth schemaへのtrigger作成権限・既存triggerとの依存順は未確認。
本番applyやtrigger権限昇格の回避手段をこの候補から実行してはならない。

この台帳が保護するのは切替時に存在するGoogle identityと、その後に観測する
identityである。切替前に正規soft delete済みの難読化行はseedから除外し、
勝手に元subjectとして登録しない。未知ACK後も台帳やAuth行を削除して
取り消しを偽装しない。Google再送でsessionが増える場合も本人UIDは維持する。
切替前に削除済みで記録がない古いGoogle subjectの所有者を
推測で復元しない。既存の会社・本人IDや過去IPAを変更しない。
