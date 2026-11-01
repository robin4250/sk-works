SKO local backup encryption preparation (OFF; no production exporter)

This tool encrypts an explicitly supplied byte stream with age. It does not
connect to Supabase, discover credentials, export a database, download Storage,
create a permanent private key, upload files, schedule jobs, or restore data.
The successful receipt certifies ciphertext publication only. It deliberately
reports restoration_verified=false and production_export_performed=false.

Supply one native age public recipient in --recipient-file. Keep its matching
private identity separately from backups, source repositories and logs. Never
put a private identity in this public recipient file. The age CLI is required.

A reviewed exporter can feed stdout to encrypt_stream.py. The orchestrator must
check BOTH producer and encryption exit status before marking a backup complete.
An upstream exporter failure may still yield an encrypted but incomplete stream.
Do not label encryption success alone as a usable backup.

Only ciphertext is written by this tool. New files are mode 0600. A temporary
ciphertext is flushed before atomic publication; existing destinations are never
overwritten. Failures remove temporary ciphertext and emit only a fixed error.
Source filenames, contents and private recipient material are not logged.

Before enabling backup operation:
- Choose an approved destination outside the source checkout and a retention limit.
- Arrange recovery-key custody and demonstrate recovery without the running app.
- Capture DB schema/data/roles, Storage objects, and required configuration as
  distinct reviewed sources. A database dump does not include Storage file bodies.
- Verify exporter success and the expected inventory/counts before recording success.
- Restore to an isolated destination, verify access controls and sample document
  consistency, and record that result separately. Never restore over production.
- Account for free-tier storage/transfer quotas and the consistency window across
  DB and Storage. No scheduler or automatic deletion is enabled here.

Verification uses synthetic bytes and temporary test-only keys. It checks real
age encryption/decryption, wrong-key and tamper rejection, secret-free output,
private permissions, refusal to overwrite, and cleanup on invalid recipients.
Run: python3 -m unittest discover -s tool/security/backup -p 'test_*.py' -v
