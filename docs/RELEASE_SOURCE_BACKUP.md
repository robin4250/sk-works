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

After approved layouts, CI, main integration, and device/data backups are ready:

```bash
cd ~/sko-restore && git switch main && git pull --ff-only origin main && bash tool/device_day.sh 00008110-00120536010A801E
```

To restore the saved committed source to a separate directory:

```bash
git clone /absolute/path/to/source.bundle ~/sko-source-recovery
```

Never replace main with an older backup commit. Apply a forward fix to current
main when recovery is needed.
