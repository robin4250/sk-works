# 未添付の注文請書を自動生成する修正

基準source `cb9fe326`。build7にも通常draftの自動生成はあるが、印影固定済み・
未添付では明示添付へ誘導していた。本人の最新要望に合わせ、この除外をやめる。

保存済み別添は従来どおり優先。未添付・autoONならsource_locked=trueでも、
権限確認済みworkspaceと既invoice issueDateから読取りPDFとして生成し、共通
buildPdfで1頁目直後に追加する。sourceChanged/blocked/unknown readinessと
issueDate不明は拒否。autoOFFは未保存分だけ除外する。通常preview/印刷/共有は
同じ生成経路を使う。旧missing-locked callbackは互換用引数として残すが、この
自動生成から手動確認Noticeを発火しない。新しい確認ボタンは追加しない。

workspaceの印影defaultsは現在会社の印であり、固定親の印ではない。自動生成時
には親PDFが実際に使うinvoice.companySealSnapshotとeffectiveSettingsのON/OFF
を明示して引き継ぐ。登録済PNG・uploadedPNGとも親の画像/版/会社情報を保持し、
別会社不一致は拒否。旧parentのmetadataがない場合も現在PNGへ代用しない。
保存済別添にはこの置換を適用しない。相手印の取得は追加しない。

DB/RPC保存・親invoice更新・承認・凍結解除・印影変更・自動保存は追加しない。
生成はその時点の読取り出力であり、別添を保存したと偽らない。親金額・固定印影・
承認履歴・既存別添の永続値は維持する。

専用CIはresolver/既workspace guard/共通PDF/旧Notice互換を検証する。実PDFで
通常/locked未添付は2頁、autoOFFは1頁、保存済別添は保存日付を保持し2頁、
全caseの親1頁目のtext/rasterが基準と完全一致することを確認してartifact化する。
ローカルFlutter起動は既拒否境界のため行わない。CI/配布/iPhone確認が終わるまで
実機反映完了とはしない。今回の対象は配送だけでは解決しなかったが、修正後の
Release配送が別途必要。

共通ヘルプへの追補案（統合担当所有）：
注文請書の自動生成がONの場合、未添付の請求書には印影固定の有無にかかわらず
注文請書を自動で2ページ目へ表示します。保存済みの注文請書は保持します。
元請求書の金額・印影・承認履歴は変更せず、注文請書を自動保存することもありません。
