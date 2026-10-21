# 管理資格の保存済み写真：client能力読取の未接続準備

基準main `bedac66af938989a9e9d314ee2d96cd01b831a01`。既存 `qualification_admin_capability_20261019.md` とreview-only candidateの8key契約を再利用する。既存本人向け能力は管理権限の証拠にしない。mainに同名client実装がないことを検索してから追加した。

`AdminSavedQualificationPhotoCapability.parse` は余分・不足fieldを拒否し、整数version1、marker、要求した正規UUID会社・actor、bool availability、upload=false、self_approval=false、整数max20を全て照合する。無効応答はunavailable、正規のavailable=falseは利用不可。個人能力や未知versionへのfallbackはない。

`AdminSavedQualificationPhotoCapabilityRepository` は未接続で既定gate OFF。maybeCreateはOFFならbackend参照・購読・RPCなし。明示ONで既存 `personal_qualification_submission` の `admin_saved_photo_capability` actionへexact company_idだけを送る。新RPC、新API、新SQL、Storage、write、申請、承認は追加しない。旧backendや拒否・通信失敗はunavailableとして扱い、本人APIへ切り替えない。

repositoryの初期actor/companyへ束縛し、現在値が変わった場合、変更streamの途中で別scopeを観測した場合（A→B→Aも含む）、stream error/done、disposeで不可逆に失効する。再利用には新repositoryが必要。`capability()`は読取前後に照合する。取得済capabilityはimmutableな時点snapshotであり、後続consumerは `canUse(capability)` も再確認する必要がある。これは管理prepare/submit/approve時のサーバー権限再検査を代替しない。scope変更streamは将来の実接続時に実際の会社切替源を渡す必要があり、現UIへ接続していない。

新規pure contract＋stub transportテスト2ファイル13件成功、4ファイルanalyze問題なし（各exit0）。8key不足/余分/旧本人応答、型・値・会社/actor差異、defaultOFFの読取0、dedicated actionとexact payload、失敗時fallback0、actor/company ABA、取得後切替、streamerror、dispose後の不可を検証。実backend、実membership、実権限、実Storage、送信・承認成功、実機、native競合の証拠ではない。

Supabase skillを読了し公式Flutter rpc資料 `https://supabase.com/docs/reference/dart/rpc` のfn/params仕様を確認した。必須changelog.md取得は検索ツールがcontent-type text/markdownをUnsupportedとして拒否したため、その取得成功とは記録しない。依存・lockは変更しない。

ログは `outputs/admin-saved-photo-client-20261019/contract-repository-tests-final.log` と `contract-repository-analyze.log`。最初のtest runでrecord内Mapのidentity比較により1件失敗したが、actionとpayloadを別々にdeep比較する意味のあるassertへ修正し全件成功した。既存UI・本人申請・管理写真hold・SQL候補・migration・Auth設定・RLS・権限・本番・Mac・公開・CIには変更なし。マスター展開/本番導入HOLDを維持する。
