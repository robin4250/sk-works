# 新規署名入力に限定したサーバー幾何検証候補

本番HOLD。READ ONLY採取した実3writerを原典に、認証・会社・権限・入場条件と既存の読み取り専用ACKを保ったまま、新しい書き込み前へvalidator呼び出しを加える。訪問の新規書き込みでは元のpoint全走査より先に資源上限を確認し、completed/skippedの旧読み取り経路と明示確定のexact ACKは元の位置・チェックのまま残す。shared submit／管理／承認済み責任者の入力は普通rolewriterへ収束する。直接呼べる旧finalizerも対象に含める。

`checkout_report_registration_private.has_signature` は履歴の解釈であり、変更しない。旧原本・receipt・履歴・点だけの既保存署名を削除・修正・一括再判定しない。既存の保存済み署名を返す読み取り専用の正規ACKは維持する。新たに確定を書き込む要求には有効な筆跡が必要であり、旧点署名の再採用は拒否する。

## 新入力の契約

- role値は `{"strokes":[[{"x":数値,"y":数値},…],…]}`。座標は正規化0～1。現在のcodecが付ける `canvas_width`／`canvas_height` は各pointで同じ組として扱う。
- 1stroke内の累積線長が1px以上。別々の点を結ぶ線は合成しない。既定canvasは既clientと同じ400×120。実capture寸法付きも同じ計算を行う。
- 現codecは最初のcaptureSizeを固定し、リサイズ後も全pointに同じ寸法を出力する。混在寸法・片方だけの寸法・余計なkeyや数値文字列は新しいcanonical入力として受け付けない。元JSONは正規化・書換えしない。
- 新APIの資源上限はJSONテキスト4MiB、256stroke、1stroke16384point、全体65536point、canvas各辺0より大きく16384以下。履歴への遡及制限ではない。
- 直接finalizerは上記role値か、現在の正式なversion3の代表者／責任者ペアを受け付け、両方を検証する。

これは線の有無の検証で、署名者本人の生体認証や署名の真正性を証明するものではない。既存の認証・承認・対象版・権限は引き続き必要。

`prepare.py` は採取済み実sourceを固定anchorで置換し、3関数の非本文catalogを維持する候補を生成する。新private純validatorはSECURITY INVOKER・IMMUTABLE・公開grantなし。新schemaと関数のACL/owner/config/bodyはpostassertし、未知の権限が残れば全TXを中止する。実本番導入にはfresh完全catalog guardと明確な承認が別途必要。日時を捏造したmigrationや本番適用は作らない。

専用native PG17は実3writer本文と公開wrapperを使用する一方、認証／入場／金融依存は明示した合成・中立fixture。JSON共有fixtureによりclientの実stroke計算と整合し、普通・訪問の両roleと直接finalizerで空白・点・同一点・短線・異常値・巨大入力を拒否する。正常入力、再確定、旧原本閲覧と旧ACK保持を検証する。既金融producer／実GoTrue／実機全体の完了とは扱わない。
