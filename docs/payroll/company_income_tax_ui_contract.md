# 所得税PDF資料UI・Storage接続準備

新規CompanyIncomeTaxPage/Repositoryを独立追加。既存設定画面の入口や給与計算はこのlaneで変更しない。専用DB・Storage migrationは別laneで、未導入時の取得失敗を未登録や保存成功に読み替えない。

## 短い操作手順

年度（暦年）・種類・PDF・公式情報元URLを入力。適用期間と情報元名は詳細で確認・変更し、確認dialogには年度・種類・開始／最終日・ファイル名・情報元を全表示する。画面では適用最終日を含む期間として扱い、adapter内部だけ翌日をends_beforeへ変換する。PDF登録後は未検証で、検証／共通公開のtoggleを置かない。旧年度を一覧へ残す。

一覧の確認日／種類は適用候補の参照用。日付入力を変えた時点で旧表示を外し、再読み込みで確認する。新年度事前登録と適用日での選択を支えるmetadataを扱うが、実給与計算の自動切替は未接続。

## PDF登録

- FilePicker13.1.0のpickFileでPDF1件、lengthSync/length（nullは不明）で10MiB上限を事前確認。取得bytesも拡張子・%PDF-ヘッダ・サイズを検査する。PDFの正式性・内容の完全解析をする検査ではない。
- crypto3.0.7で実bytesのSHA-256を計算、bytesは入力からコピーしたunmodifiable viewで保持する。cryptoは既存lockの版・integrityを維持しdirect mainに変更。
- UUIDv4を資料IDとして生成。company-income-tax-tables private bucketへcompanyUUID/tableUUID/1/hash.pdfをuploadBinary、application/pdf、upsert:false、retryAttempts:0で送信する。
- 成功後register_company_income_tax_tableをexpected_version0／本人確認trueで呼ぶ。返却ID・version1・全metadata・未検証／非共通の状態を検査して初めて登録成功を表示する。
- metadata RPCを呼ぶ前のupload失敗は専用型で区別。明示的な再試行は同じ資料ID・path・bytesを保持し、再確認後に1回だけ送信する。ファイルの選び直しも可能。失われたupload返却によりobjectが既に存在する場合、upsertfalseの再試行は競合で失敗するため選び直しを案内する。旧objectは削除しない。
- metadata返却不明時は資料IDと全metadataが一致する行をreadで確認する。確認できるまでは追加登録を無効化。PDFを自動再送・削除しない。孤立uploadの後始末はこのUIで行わない。
- PDF表示は会社管理者が単一pathのcreateSignedUrl（600秒）を都度取得。signed URLをmetadataへ保存せず、public URLを生成しない。

## API・domain境界

read_company_income_tax_tablesのtables/selected/historyを検査。common_data_approvedはfalseのみ。返却selectedは同一一覧内の同ID/version/value/検証状態で、確認日／種類／年度／期間に一致することを要求。

IncomeTaxTableRegistryはmetadataの期間重複と日付選択整合性の検査に利用する。この投影のpdfには本人登録source_urlを渡すが、これはmetadata検査のためで、実PDFbytesのidentityや公式検証の代用にしない。PDF閲覧は別のStorage locatorからのみ行う。署名URLをRegistryに永続保存しない。

API履歴はregistrationとverificationを区別。trusted正式検証・計算ルール検証の実運用、公式新年度自動取得、給与の税額表計算、確定snapshot、過去PDFbytesの実環境保持は未検証・未接続。

## 検証

12テスト追加：inclusive最終日の年境界／閏日変換、metadata上限・名前不正でupload/RPCゼロ、upload失敗後の明示同ID再試行、非PDF／超過サイズ、固定hash・immutable bytes・実在日付、upload失敗後RPC無し、upload→metadataの順序と返却identity不一致拒否、検証／共通状態の誤成功拒否、未検証資料の適用拒否、確認cancel・登録、lostreplyの同ID再確認と再送無し、取得失敗と再試行。

ローカルFlutter/Dart SDKなし。source reviewとgit diff --checkのみ実施、CIで実行が必要。Supabase Flutter upload/createSignedUrl公式docs、file_picker13.1.0公式docsを確認。Supabase changelog.md取得はunsupported content-typeのため未確認。

sourceURLは2048文字以下のhttpsかつ空白無し、publisherはtrim後1〜200文字、file_nameは5〜200文字・slash/backslash無し・PDF拡張子をupload前に検証する。
