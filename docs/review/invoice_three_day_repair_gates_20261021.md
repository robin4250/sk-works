# 出勤3日・請求2日：実対象修復前の原本ゲート
基準main `2853e2d8d530f3fc65ce74ef307a1c63b21b0496`。GitHub MCPで保存source/docsを読取。対象個人・ID・日付・金額は転記しない。本番照会/変更・SQL実行・隔離検証再実行なし。実対象との一致は未確認であり、3日への数値変更を承認する資料ではない。

## 確認できた既経路
- `attendance_clock_only_work_completion_20261019.md` は打刻だけの日を未確定表示する修正で、勤務確定や請求修復ではない。`invoice_three_day_evidence_20261021.md` の既隔離成功は署名・参加者・勤務等のsynthetic根拠が揃った場合だけ。今回の実対象を証明しない。
- 既勤務の承認付き修正は `AttendanceCorrectionRepository.createDraft/submit` → `submit_attendance_correction_request` → `AttendanceCorrectionApprovalRepository` のpending/item読取 → `decide_attendance_correction_request`。UIは `bulk_attendance_correction_page.dart` / `attendance_correction_approvals_page.dart`。申請者の署名・現管理権限、会社の承認担当を必要とする。旧SQLは承認担当が複数の時だけ自己承認を拒否するため、常に独立承認保証と誤記しない。
- 勤務原本がない過去日は `PastAttendanceRequestRepository.submit` → `submit_past_attendance_request` → 同承認経路が存在する。元SQL `20261003164557_route_past_attendance_through_approval.sql` は過去日・署名・管理権限・承認者設定・会社内社員/現場の名称一意性を確認する。会社選択にlimit1があるので、実actorの所属会社一致を別途照合し、他社修復へ流用しない。
- 後続 `20261006103927_fix_attendance_correction_paid_leave_work_category.sql` のdecide新規勤務分岐はattendanceをINSERTし同日有給を取消するが、source_report_id/正式日報/checkout署名/参加者/訪問根拠を生成しない。既勤務分岐は既source_reportがあれば日報worker値を同期する。したがって承認済勤務追加だけで署名退勤請求の根拠が揃うとは言えない。
- `DailyReportRepository.saveDraft` と `save_daily_report_signature` の正規日報署名経路はある。途中訪問の `save_route_visit_report_signature` はcheckout署名の代用ではない。過去原本の無断再作成・署名代筆・時刻遡及を行わない。

## 原本保持上のblocker
勤怠管理の `AttendanceManagementRepository.apply` は `force_manage_attendance` を呼ぶ。初版 `20261004093435_add_force_attendance_management.sql` だけでなく後続上書き `20261008042058_fix_managed_attendance_overnight_chronology.sql` にも、対象日の既日報worker除去、空日報DELETEまたは署名解除、verification/attendance削除と再作成、既修正item FK切離しがある。この実装を「原本保持の限定補完」として本人へ案内しない。実本番定義の照合も未実施。対象勤務だけのattendance再INSERTや日数3への直接書換で代用しない。

## 実対象1件へ進む前に不足している資料
1. 非公開で今回のworker・会社・対象請求/月・不足業務日を特定し、以前の不足日調査と同一であることを確認する。打刻の3日と請求先ごとの人工契約を区別する。
2. 同日の日報原本、署名・署名日時、参加者、勤務source_report、出退勤verification（業務日/会社/社員）、route assignment/visit/journey/checkout関連付け、現場の取引先、適用単価・未登録手当/blocked診断、重複/再訪を限定読取で照合する。
3. 対象請求のdraft/確定・承認/印影固定・保存snapshot/数量基礎行と、稼働中のsource/generator/trigger/refresh・後続起源receipt候補の導入有無を確認する。保存コード存在から本番導入済みと判断しない。
4. 原本backup・変更前全行hash・限定対象・他給与/有給/請求への副作用・復元方法を準備する。確定済帳票と承認履歴を保持する。

## 原本不在時の正規手順
打刻だけなら未確定のまま、実勤務の現場/数量/内容と不足理由を本人・正規承認者が確認する。既勤務があれば既承認付き修正を使う。勤務自体がなければ過去出勤申請は候補になるが、有給取消の影響と署名請求根拠を別途確認する。正式日報/checkout根拠が存在しないなら過去署名を作らず、正規に原本を確認・記録・署名できる既手順の適用可否を調べる。現候補には既打刻を保持したまま不足checkout原本を補完する限定repair APIを確認できていないため、そこは未達として止める。

根拠が揃ってから既会社scope `refresh_signed_checkout_invoices` と対応triggerによる未確定請求更新を検討する。通常一覧の自動refreshと通知専用の読取入口を区別する。保存値・基礎数量・明細・PDF/印刷/共有、再実行重複なし・他社/確定帳票不変を確認し、本人iPhoneで同対象を確認して初めて完了へ移す。
