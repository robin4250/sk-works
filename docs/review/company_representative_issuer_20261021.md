# 発注者の代表者名：自社設定から未保存注文書へ

基準 main2853。最新実機訂正の不足は「発注者代表者名だけ」。既会社情報欄・counterparty補完・金額等を作り直さない。80文字候補2b513f/CI44成功を再利用し、通常migration/本番適用はまだ行わない。

## 接続

既自己会社editorへ代表者専用cardを配置。旧contact writerのLIMIT1は代表者の保存に使わず、全owner/admin所属→明示会社選択→company_id付き既read/saveへ固定する。cardには保存先会社名を常時表示する。contact/bank formとは別draft/saveで、相手方directory代表者を自社へ流用しない。

repoはactor/tokenを固定してAuthorization headerも固定する。選択会社epoch・actor/tokenの前後照合、tokenABA/stream異常/背景失効、表示PII消去を持つ。save応答後に再読込してversion/nameを照合し、不明結果は再保存を拒否して明示reloadを要求する。代表者は正規化後80codepoints以内。ヘルプは?から開き初期表示を簡潔にする。

旧連絡先フォームの複数所属LIMIT1問題全体は変更していない。新代表者cardの会社選択と保存は独立したcompany_id bindingでその問題を回避し、既writerを再送しない。

## issuer-only SQL候補

current tax+directory sourceの本文MD5 c61f8835084400b68fbccd9cba35a926とowner/ACL/security/config等の固定guardを要求。未知sourceは停止。会社本人のprivate extensionを同cidで読み、owner/adminの未保存payment orderのissuer.representative_nameだけへ反映する。manager、invoice、counterparty、金額/税、fingerprint、既保存別添を変更しない。代表者変更後も既保存注文書はsnapshotを保持する。

正規部署代表者保存原本は既候補のまま、専用のsource-only patchを後段で適用する設計。本番適用には全metadata/sourceのfresh照合・guard・backup/停止区間復元証拠を統合担当が用意する。UIだけ配布してsource未配備を完了扱いしない。

## 検証境界

専用profile CIへ新repo/card解析・repository6tests・widget2testsとissuer SQL fixtureを接続。SQL fixtureは既月次別添source/saveを再利用し、current tax+directory状態へ拡張して代表者save/read→未保存default→正規別添save→後日変更でもsnapshot保持、counterparty/invoice/manager/tenant/fingerprint/catalog/金融原本保持を検査する。すべて合成データ。既44profile checksも既CI stepとして保持する。

ローカルexec/Flutter実行なし、MCPでbranch保存後のexact-head CIを確認する。製品main/既PR/本番/会社role/Auth/RLSは変更しない。実機保存→再読込→新規注文書/PDF/印刷/共有は別確認。
