# TestFlight候補だけを作る独立wrapper（実Mac未実行）

新helper `tool/testflight_private_candidate.py` は、元checkoutのdirty変更・旧Archive/IPA/端末appを保護して、新規private clone内だけで候補IPAを作る準備。upload/install/配布を実装しない。PR #1244の進行中headを承認済みとみなさず、配布対象SHAも未固定。source保護branchの公開は候補作成・配布の開始ではない。

## 既成果再利用と最小変更

R31の `source_state`、private JSON、bundle、native inventory/copy、symlink依存隔離、Flutter3.47.5/Xcode27.1検査、clean確認を再利用する。既TestFlight provenanceのsource/exact-main CI/configuration/start/create/validateをそのまま呼ぶ。既testflight_preflightも呼ぶ。候補のBundle ID、App Store profile/署名、version/build、Release構築記録、IPAのSHA、Google callback、master=false等は既provenanceの検査に委ね、省略しない。

既candidate.shは内部prepare/pubgetを再実行するので、R31隔離後にそのまま呼ぶとplugin linkが共有cacheへ戻り得る。mainに新skip分岐を追加する案を採用せず、独立wrapperから既prepare_iosを一度実行→R31 isolate/audit→既preflight/provenance→同じ固定 `flutter build ipa --release --no-pub --export-method app-store` を実行する。build-nameはselected sourceのpubspec、build-numberはApp Store Connectで未使用と確認した引数を必須とする。既candidate/prepare/provenance/R31の製品sourceは変更しない。

## 保護・停止条件

- 元rootのHEAD/index/staged/unstaged/untrackedをprivate checkpointとbundleへ保存。未追跡原本もコピー。元branch/mainへcheckout/reset/clean/stashしない。
- 元iosをコピーし、存在する旧build/ios/archive・ipa・iphoneosも別private保存。元Archiveと端末appは上書きしない。成功後に元source/native/artifactの完全inventory不変を確認。
- 独立local cloneでのみmainを作る。固定public originをfetchし、origin/mainと明示approved SHAが一致しなければ停止。helper自身のSHAとbuild対象の承認SHAは別。helperをmainへ追加するためだけの全Flutter CIを要求しない。
- exact mainのFlutter CI/iOS CI/Secret Scan/TestFlight provenance成功をbuild前と既provenanceで確認。CI進行中、欠落、未保存native変更がprivate clean gateへ出る場合は停止。検査を通すためtracked signing設定を自動commitしない。
- 公式iconは既repo指定pathまたは既指定Downloadsの1ファイルだけ。仮生成を許可しない。icon digestの前後不変を確認。
- 元known local environmentはshellでsourceし子processへ渡すだけ。envコピー・秘密鍵/API認証探索・値の表示なし。ログはprivate。CI=falseではなくビルド前にCI変数を除去し、正式icon不足をCI例外で通さない。
- flockで本wrapperの同時実行を拒否。durable started/complete/failed checkpointで終了不明を拒否、同approved SHA/buildの二度目のattemptも拒否する。未知のcheckpointを自動削除して再実行しない。既R31やOrganizerの別buildが終了済みである確認はrootの別前提であり、このlockはそれらを包括制御しない。
- エラー時はprivate checkpoint・元成果・原本を保持し、自動復元・再試行しない。結果summaryをpbcopyする。成功でもuploaded=false/installed=false/testflight_approved=false。

## 検証範囲・未完

合成Gitで3テスト：durable unknown/同key拒否、固定IPA commandにupload/installなし、dirty staged/unstaged/untracked不変と旧Archive保持・env非コピー。SDK/network/署名/buildをfake runnerへ置き換えた制御試験であり、実Macのarchive成功ではない。実testflight provenanceの既署名検査自体をmock成功で認定しない。

このwrapperだけではLINE本番非開放、実帳票・役割境界、Apple配布署名/Team、ASC未使用番号、実Macの権限・依存コピー、審査、外部テスター招待を完了にしない。現在はsource準備。実行案内は選定SHAのCIと既承認条件が揃った後にrootが一行へまとめる。TF build/upload中の旧成果を重複生成・送信する指示は出さない。

独立loaderはwrapperと同じreviewed helper SHAから sibling `tool/r31_local_release.py` もprivate helper directoryへ取得する。既R31のSHA256は `3f0c33ece0f6c0f7c1b1b24caa448c916828fbd6df66b66c7278fe3f0c93dd09`。wrapperはimport前にbyte digestと非symlinkを検査し、不明なローカルdirty helperを暗黙実行しない。R31 source自体の変更はない。
