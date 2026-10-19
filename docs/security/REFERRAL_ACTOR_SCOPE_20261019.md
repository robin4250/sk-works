# 紹介画面の本人切替境界

基準main2896d847。紹介元確定/ポイント/登録完了通知を新規実装する変更ではない。個人入口・管理入口・招待/設定ページに、現actorとauth streamを監視する画面単位のscopeを追加。A→B→Aでも最初の変更後は無効を保持し、stream error・repository/画面用途変更・破棄も停止条件にする。

無効化時は履歴/設定snapshot/入力を破棄し、再読み込みや古い完了結果で再有効化しない。pageの同一本人でもload世代が古い結果を破棄する。既composerへscopeが有効な間だけactorを渡し、prepare待機後/外部SMS作成画面から戻った後に失効したscopeで開く/記録することを止める。既RPC名/引数/権限/配布URL保存契約は変えない。

既no-SDKのUI fixtureは同一本人の空streamを明示する。追加8testsは遅延取得の成功/失敗、個人/管理入口ABA、stream error、SMS準備中/起動中ABA、破棄後の起動0を検証する。SMS開閉は合成callbackで実送信0。既専用workflowで解析と紹介UI/SQL境界を実行する。ローカルSDK実行不在のため新headのruntime結果はCIで確認する。

serverへ送信済み操作の取消、実端末SMSの送達、実JWT/RLS、紹介/ポイント完成を証明しない。会社初回QRのcredential寿命問題は別の未完。本番/DB/Auth/権限変更0。
