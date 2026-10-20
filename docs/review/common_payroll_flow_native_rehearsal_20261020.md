# 社内共通手当: 保存→適用月→給与・明細の実復元DB検証候補

本番変更用ではない。前回Macで成功した依存4原本導入・rollbackを再利用し、
元の停止済み復元DBから作る通信なしの別cloneで、正規APIによる保存から給与までを検証する。
税率・加入条件・個別給与設定は変更しない。

## 再利用する原本

- `owner_payroll_common_rehearsal.py` の4原本のhash/依存guard、導入SQL生成、catalog/業務行hash
- `owner_expense_off_rehearsal.py` の既存停止DBからのclone、network none、cron OFF、DB owner/ACL照合
- `common_payroll_sources.json` のidentity→common保存→bridge→effective原本

既存unit migrationは再適用しない。これらの3ファイルは前回成功版から変更していない。
新しい `owner_payroll_common_flow_rehearsal.py` は既存導入SQLの末尾ROLLBACKだけを厳密に外し、
hash固定のフロー検証SQLを追加した後、ROLLBACKを置く。外側transactionの追加は拒否する。

## 実行する隔離シナリオ

1. 保護済み給与rowのMD5から、会社・従業員・対象月を一意に導出する。
   原本と異なる場合、対象月がJST当月でない場合、手入力/確定済みの場合は停止する。
2. 実在する一意の会社ownerと、同ownerの有効な`auth.sessions`行を選ぶ。
   clone内のtransaction限定で明示的に模擬claimsを設定する。sessionを捏造・新規登録しない。
   発行JWT、OAuth認証、PostgREST通信の証明とは呼ばない。
3. 未有効のまま現行保存sourceから対象自動下書きを計算し、比較用baselineを得る。
4. authenticated roleで公開read/save APIを使い、テスト専用の共通支給1,000円・控除250円を保存する。
   月単位なので数量1。初期extras空を確認し、旧3枠は原本の値とID参照のまま渡す。
   同request再実行は同receipt、別requestの旧versionはCAS拒否を確認する。
5. cloneの新規private表に限り、対象会社・当月のactivationを明示的に書く。
   このcandidateには公開activation APIが無いため、ここを公開保存APIとは呼ばない。
6. authenticated roleで公開publication APIを呼び、合法な当月自動下書きを通常経路で再計算する。
   対象給与の支給増分、共通控除、差引額、保存されたstable ID/会社共通originの内訳と
   公開unit明細を照合する。publication再実行/CAS拒否で給与版・内容が変わらないことも確認する。
7. 税・保険条件、個別設定、会社元料率、住民税額とsource、勤務実績を保持する。
   条件未登録なら条件行やtax resultを作らず、旧固定の税・保険detailを維持する。
   条件登録済みなら元version/開始月/overrideを維持し、新grossによる既存tax.calculateの正規結果と比較する。
   共通支給による所得税・雇用保険等の正規変動と、条件消失を混同しない。
8. 実在する手入力/確定給与、他社、他給与形態、過去月の給与全行を保持する。
   手入力/確定行が0件なら「実レコードで保護ケースを実証」と誇張せず、その件数を安全な結果JSONに残す。
9. 全変更をROLLBACKし、元catalog/業務行hashとの一致を確認する。
   clone停止失敗は成功扱いにせず、phase=clone_stop、verified=false、終了コード1にする。

## 検証

- Pythonコンパイル、source/scenario改変拒否、正常rollback、失敗cleanup、停止失敗、税保護結果不足を含む7テスト成功。
- 既存共通手当・給与fixtureで公開save→publication→実refreshを実行。
  条件未登録、固定社会保険＋所得税手入力override、甲欄所得税が共通支給で実際に変わる3ケースで成功。
  原本row hash不一致は拒否、内訳/合計/住民税/条件保持、retry/CAS、catalog/業務行rollbackを確認した。
- 上記はsynthetic PGlite検証。新シナリオの実Mac/native実行は未実施。

## 公開する結果と制限

フロー結果JSONはbool、保護行件数、再計算scope件数だけで、実ID・氏名・実額を含まない。
共通手当の1,000/250はテスト値であり、本人の保険料や本番手当ではない。
個人sourceはDB内のtemp表だけに保持し、コンソールへ出さない。エラー記録はMacの私有stage内に保存する。
安全な最終結果だけをpbcopyする。

本番配備、会社activation、本番手当保存、発行JWT/HTTP、実機、通知配信、commit後の復旧は未完。
row rollbackはsequence値の巻き戻しを保証しない。元DB・バックアップは起動・変更せず、private clone/imageを外部へ送らない。

新規公開対象: flow helper、`common_flow_scenario.json`、対応Pythonテスト、このreview。
`scenario.sql`はJSONの可読複製。`smoke_common_flow.mjs`と`install-flow-rollback-smoke.sql`はローカル検証用で公開不要。
