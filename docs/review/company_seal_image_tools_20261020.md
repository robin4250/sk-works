# 角印画像化・追加保存候補（本番未適用）

基準 main: `a74f479321bcaef028c066c1bc9eee5316e0da55`。既存 PNG #1296 の immutable versions / selection / common PDF renderer を再利用する。課金区分・価格・entitlement 台帳は追加しない。

## 利用経路

会社角印設定 → 撮影／写真／画像・PDF → PDFは表示ページを選択（1–20ページ目）→ 印影の範囲をドラッグ → 回転・白背景透明化・薄い赤の保護／元に戻す → PNG化 → 透明背景を確認 → 追加候補 → 既存共通PDFプレビュー → 追加保存 → 明示的に「この印影を使用」。追加保存のみでは現行選択を変更しない。履歴の選択もプレビューしてからCASで切り替える。

生成物は縦横比を維持した1024×1024 RGBA PNG。960pxの内容領域に透明余白を置く。請求書・支払証明書・給料明細の既存 physical stamp box は変更しない。元写真のsession bytes・編集前フレームを保持し、回転・切抜き・透明化は別バッファで行う。写真ライブラリや元ファイルへ書き戻さない。画面を閉じると未保存の作業は破棄する。PDF全文の自動抽出・外部送信はしない。

## 既存依存と対応範囲

新規依存なし。file_picker13.1.0 の静的 pickFile、image_picker1.1.2（iOS0.8.13+9/Web3.1.1）、printing5.15.1、Flutter dart:ui を利用する。

- iOS写真のHEIC/HEIFは現行image_picker_iosがUIImageへ読み込みJPEG作業コピーへ変換する。実機確認が必要。iOS simulatorのHEICはサポート確認に使わない。
- 直接ファイルのHEICやWebのHEICはcodec依存。対応しない環境はJPEG/PNGまたはiPhoneの写真経路を案内する。読めないものを成功表示しない。
- Webのカメラ入口はブラウザーのcapture実装依存。モバイルSafari/Chrome実機確認が必要。
- PDFはPrinting.rasterへ選択した1ページだけ渡す。初回は1ページ目。存在しないページ・暗号化／破損PDFはエラーを表示し、前の正常表示を保持する。

参考: https://pub.dev/packages/image_picker/versions/1.1.2 、https://api.flutter.dev/flutter/dart-ui/instantiateImageCodec.html 、flutter/packages tag `image_picker_ios-v0.8.13+9` のFLTPHPickerSaveImageToPathOperation/FLTImagePickerMetaDataUtil。

## 上限

入力20MiB、codec入力32以上/8192px以下/3200万画素以下、作業フレーム最大2048px/約420万画素。静止画のみ。PDF144dpi/選択ページ1–20、ラスタ取得後4096px/1600万画素以下を確認する。ただしPrintingのネイティブラスタ取得以前のメモリー割当をDart側で制限できる保証はない。巨大用紙PDFの事前解析は未実装。PNG結果は既存1MiB/32–2048px/magic/CRC/hash validatorを再利用し、超過は保存不可。

## Gateとサーバー契約

中央 `MasterFeatureAvailability.companySealImageTools` と `company_seal_image_tools` を表示・編集開始・生成前後・追加保存／履歴読取前後・選択前に再確認する。新キー未対応serverでは新画像化入口を非表示にし、従来PNG経路・既存角印選択肢を残す。保存serverでも `private.require_master_optional_feature('company_seal_image_tools')` を使用する。

review-only SQLは既存private.company_seal_png_versions表のみへappend/dedupし、現行selectionを変更しないregister、20件cursor履歴、単体byte読取をowner/admin範囲で追加する。既存saveをsource-anchor guard付きでpatchし、PNG追加／有効化・切替にもserver gateを要求する。OFF時の既存PNG使用解除は許可する。現在の画像読取・確定snapshotの描画にはgateを追加しない。

backend未適用時は追加保存RPCが失敗し、成功表示も印影選択変更も行わない。DBのimmutabilityを維持し、過去確定帳票のPNG snapshotや会社スタイルを更新しない。

## 検証

PGlite fixture成功: append後に現行selection完全不変、同一SHA dedup、history/read、CAS競合、master OFFでregister/select拒否、OFFでも使用解除可、他user拒否、immutable delete拒否、確定snapshot不変。

追加Dart tests: 薄い赤画素のalpha残存、原本不変、透明余白、縦横比、4回回転、空印影／範囲／サイズ拒否、PNG実codec roundtrip alpha、入力サイズ/PDF magic。ローカルFlutter SDKなしにつき未実行。Flutter analyze/tests/既存PNG回帰/Android・iOS/Web実機の撮影・HEIC・PDF・保存・三帳票目視は未完了。本候補を本番完了扱いしない。

適用前に既存DBバックアップ・隔離復元・旧PNG候補導入・中央gate導入を確認し、実JWT/HTTPとスナップショット保持を隔離DBで検証する。本候補に本番実行の指示は含まない。
