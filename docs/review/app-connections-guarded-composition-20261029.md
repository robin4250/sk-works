# 保護条件を維持したアプリ接続の構成候補

基点main `b37a73bb3c66d567206e2ed5e598fbf2e13dd108` の給与・承諾日修正（PR1564、統合CI40/40成功）を保持した上で、独立レビューしたアプリ接続を構成する。main反映・コードのCI成功・本番有効化・公開配送・実iPhone確認は別段階として記録する。

- Apple1554/1563:ログアウトintent時のprivate Navigator隔離と既存SDK LocalStorageの保存フェンスを実bootstrapへ接続。資格情報を含まないmarker、既存key/format維持、直列化、platformACK/freshreload、marker解除後session再確認。cacheだけが空になる削除失敗を拒否する専用回帰を含む46試験成功。全rawSDK書込所有・serverrevocation・電断耐久性は未保証。
- QR1555:固定OFFの未公開登録画面、owner-bound native journalと固定HTTPS。専用17試験とnative APIcompile/transition/query、全16CI成功。15秒全体期限後・遅延header・owner失効で応答bodyを解放し、実TLS socket終了を確認。native Keychain本人presence/実保存/再起動の実機成功ではない。既存のhosting/route/nativegateは公開しない。
- 請求1556:固定OFFの既存ページfactory→authoritative open→実PDF完了→金融/角印それぞれの明示同意→保存後不明結果のfresh read-only照合。実GoTrue/TLS/SDK/PGと既存1MiB登録印影のbytes/hash/version保持、COMMIT後応答欠落・旧SID/foreign/newSID/logout拒否の専用試験成功。公開HTTP hosting、本番権限、通常旧承認処理は変更しない。16KiB文書本文制限と原本helperを弱めない。
- 監査1558:archive専用NOLOGIN runtime roleと狭いSECURITY DEFINER helperをreview-onlyとして用意し、実Native fixtureだけ専用LOGINpoolで実行。元guard、完全descriptor、company/owner/deployment、元順序SHARElockを維持。直接registry/auth/credentials/Master/management読取やDML/CREATE/SET ROLEを拒否する実試験成功。runtimeroleのclaims GUCは信頼backendが設定する構成であり、DB独立JWT認証とは主張しない。真正source-owner registry・独立custody/WORM・本番pool配備は未完。
- 給与振替1565:既存daily限定契約を維持し、正規monthly/hourlyの保存snapshotだけ振替せず不要warningを抑止。daily不一致・未知版/種別・破損snapshotの警告は保持。基本給/手当/総支給/控除/差引/残業と原detailを変更しない。本人OFF・本番再計算なし。最終headの専用3job・解析・15試験・実PDF13件の確認が成功（件数は重複なし合算として扱わない）。

個別書類免除はOFF。新規本番DML/DDL/RLS/ACL/Authprovider/key登録、真正根拠の捏造、原本削除、署名再生成、公開hosting/配送は行わない。sourceのexacthead/全CIと統合tree/祖先はPRと保存証拠で照合する。実証済fixture・codeと外部運用・物理端末の未完了を区別する。
