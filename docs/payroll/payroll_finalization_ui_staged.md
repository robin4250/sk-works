# 個別給与の保存確定UI stage

#853 exact e02fc385 依存。本番DB未適用、main未統合。専用セキュリティ追加/Web/一括月確定は対象外。

給料一覧から開く明細に、読取専用capability RPCと厳密なrevisionが揃った時だけ保存確定を表示。isAdmin/canConfirmやrevision=1のfallbackを権限に使用しない。旧DBのmissing capability RPCだけunsupported。認可/通信失敗は明示と再読込を用意し、既存明細閲覧を継続する。

月の確認登録を維持し、明示popup後に1件のfinalizeを送信。再計算変更・版競合・結果不明時に自動再送しない。状態再照会後に確認をやり直す。成功の管理snapshotはID/版/期間/金額/銀行非開示を検証して同じPDF生成へ渡す。現在会社名・料率・調整を保存snapshotへ重ねない。本人銀行情報は既存本人RPC境界を保持する。
