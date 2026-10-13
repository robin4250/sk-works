# Release installation source backup

`tool/device_day.sh` checks that Xcode is exactly 27.0 and the Git working
tree has no tracked changes or non-ignored untracked files before generating
the iOS project. It stops on a dirty tree rather than exporting potentially
sensitive local changes. Ignored local connection settings and build outputs
are excluded.

It saves the current committed source history as a verified Git bundle, the
full commit SHA, and the clean Git status in a private timestamped directory
under `~/SKO-source-backups`. `SKO_SOURCE_BACKUP_DIR` may override that location.
This backup supports source recovery only; it does not back up the iPhone
application data or Supabase database. Complete those backups separately before
installation. The installed app is Release and its built Bundle ID must remain
`com.skworks.skWorks`; the existing app is not deleted.

Before overwriting the app, open Finder on the Mac, select the connected iPhone,
and open General. Choose to back up all iPhone data to this Mac, enable encrypted
local backup, and select Back Up Now. Retain the encryption password securely.
Wait for completion and verify that the latest backup timestamp reflects this
backup. A connected, unlocked iPhone does not confirm backup completion. This
does not back up the Supabase database.

After approved layouts, CI, main integration, and device/data backups are ready,
run this command from a terminal already inside the existing SKO repository
(its root or a subdirectory). It resolves the repository root without assuming
a folder name, and selects the connected physical iPhone automatically. If more
than one iPhone is connected, installation stops and asks for an explicit device.

```bash
cd "$(git rev-parse --show-toplevel)" && git switch main && git pull --ff-only origin main && bash tool/device_day.sh
```

To restore the saved committed source to a separate directory:

```bash
git clone /absolute/path/to/source.bundle ~/sko-source-recovery
```

Never replace main with an older backup commit. Apply a forward fix to current
main when recovery is needed.

## Macで生成したiOSプロジェクトと署名設定

このリポジトリの `ios/` は `tool/prepare_ios.sh` が生成・再利用するMacローカルの
プロジェクトです。`.idea/`、`.metadata`、`sk_works.iml` と合わせてルートに限定して
Gitの対象外にします。未保存の登録済みソースや、これら以外の未登録ソースは従来どおり
インストール前ゲートが拒否します。ゲート自体を緩めていません。

既存の `ios/` を削除したりstashへ移したりしないでください。既存のSigning Team設定を
保持して再利用します。初回の設定再適用前に、MacローカルのiOSプロジェクトを別途
非公開のバックアップへコピーしてください。Git bundleにはこのコピーが含まれません。
このコピーもiPhone本体・Supabaseデータ・キーチェーン内の署名証明書のバックアップではありません。
署名証明書の秘密鍵はこの手順でGitHubへ保存しません。

Finderでの暗号化iPhoneバックアップが完了し、最新版mainのCI・実機導入条件が整った後に、
既存のMacリポジトリ内で次の1行を実行します。iOSプロジェクトがある場合だけ、内容を変更せず
権限を限定した `~/SKO-source-backups` の新規フォルダへコピーしてからRelease導入を開始します。

```bash
cd "$(git rev-parse --show-toplevel)" && git switch main && git pull --ff-only origin main && (umask 077; mkdir -p "$HOME/SKO-source-backups" && sko_ios_backup=$(mktemp -d "$HOME/SKO-source-backups/local-ios-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX") && if [ -d ios ]; then ditto ios "$sko_ios_backup/ios"; fi) && bash tool/device_day.sh
```

バックアップコピーをGitリポジトリ内へ置かないでください。端末が複数接続されている場合は
`tool/device_day.sh` に対象の実機UDIDを指定します。上のコマンドの実行・署名コピー・
iPhoneバックアップ完了は、実際のMacで確認して初めて完了と判断します。
