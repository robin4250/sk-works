# P36 — bounded native host-read candidate, no archive execution

This separately owned candidate does not edit the reviewed isolation/native helpers. The prior profile allowed file-read* globally. Network/outside-write checks therefore did not prove that untrusted archived SQL could not read host files through superuser file access or a spawned program. No actual archive may be executed by this candidate.

New profile construction retains default deny, system.sb, fixed UNIX socket, inside-only write and process rules, while replacing global file-data reads with:
- fixed macOS system binary/library/data roots and minimal device/locale literals;
- the specific resolved Homebrew PostgreSQL17 Cellar runtime and the running Python runtime;
- exact non-system dylib files from a bounded otool -L dependency closure;
- exact timezone alias file/directory literals, only after a bounded closed tree proves every leaf is the same package object. Unresolved @rpath/unknown metadata stops rather than broadens access.
File metadata remains readable. The system.sb import may itself include exceptions; neither a source profile nor a few canaries prove complete host isolation.

Two generated outside-file paths (direct and inside symlink) must be denied while an inside file remains readable. This is checked before PostgreSQL startup. The exact native helper from PR1213 is hash-bound and reused with the new profile builder; its same-host IPv4/IPv6/outside-write/fixed-UNIX proof and synthetic PG17 initdb/start/role/table/access/rollback/clean shutdown must all succeed. No helper source is changed, no existing cluster or archive is opened, and all child environments remain scrubbed.

## Limits and status

Seventeen offline source-boundary tests pass locally. Actual macOS CI and owner Mac compatibility are pending until exact evidence is attached. The native helper still uses fixed synthetic SQL only. A passing macOS canary/native probe is not proof against arbitrary archived code, all runtime paths, all OS versions, every syscall/IPC mechanism, or complete egress. No production restoration command, archive SQL reader, role/extension installer or approval is supplied.

The broader pre-restore gates remain:
1. Correct authoritative source identity: old TOC may expose public.can_edit_worker_personnel while current PII target is private.can_edit_worker_personnel. Do not silently alias or mark that current target restored.
2. Required extension versions, trusted/untrusted language and handler code, FDWs/foreign servers, event triggers/subscriptions/jobs and restored executable code must be inventoried and reviewed before any real archive execution. The selected definition collector and role OID/name map do not establish this closure.
3. Role ownership/NULL-default/explicit ACL/grant option/grantor recovery must match protected source evidence. P35 is synthetic only.
4. Actual isolated backup recovery, saved/current time gap, admin/company/roles/provider/updated recovery emails, normal behavior and explicit concrete production approval remain unresolved until independently verified.

No product source, RLS, existing SQL, payroll, Auth, collector or production changes.

### Exact otool header diagnosis
Diagnostic head bc9e5768 run39011136674/job117333725343 stopped before PostgreSQL startup. The exact unexpected line was the second universal-Python header ending `(architecture arm64):` for the same resolved Python3.12 executable. Apple cctools [otool/main.c](https://github.com/apple-oss-distributions/cctools/blob/main/otool/main.c) emits that per-architecture header. The parser now accepts only the exact inspected binary path plus arm64/x86_64 header forms; unknown names/architectures/lines and duplicate headers remain refused. This changes no runtime permission roots or dylib policy. MacCI must establish the final result separately.

### Canonical runtime invocation check — permission list unchanged
After the header parser fix, Mac run39011434646/job117334614240 passed the host-read canary phase and stopped during native initdb at a compiled `/opt/homebrew/share/postgresql@17/timezone` lookup. The profile allowed the resolved Cellar runtime but the reused native helper still received the logical opt path. PostgreSQL17 [find_my_exec](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/common/exec.c) normalizes executable paths to locate installation files; [get_share_path](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/port/path.c) and [timezone lookup](https://github.com/postgres/postgres/blob/REL_17_STABLE/src/timezone/pgtz.c) derive support paths from that executable. This is a hypothesis for the sandbox lookup difference, not a confirmed cause. This candidate passes the already validated canonical PGbin to the native helper, keeping all runtime permissions unchanged. A separate same-package support-alias validator draft with 13 local tests remains unadopted; no unverified alias permission is granted. Actual MacCI must determine whether canonical invocation resolves this stage.

### Canonical-only result and verified timezone alias candidate
Canonical-only Mac run39011678630/job117335342326 still stopped at the same timezone lookup; the argv-only hypothesis did not resolve it. The [official Homebrew formula](https://github.com/Homebrew/homebrew-core/blob/main/Formula/p/postgresql@17.rb) deliberately compiles datadir as HOMEBREW_PREFIX/share/postgresql@17, installs support files under Cellar/share/postgresql, and creates versioned symlink trees. The new candidate therefore validates the same Cellar pg_config/version/bindir and its exact compiled sharedir, then requires only the rejected timezone alias to resolve to that package's canonical share/postgresql/timezone. Both directory owner and non-group/world-writable mode are checked; all five executable hashes and alias metadata are rechecked after the probe. Only the timezone subtree alias receives read-only permission. Whole sharedir, extension directories, other packages, user folders and existing clusters remain excluded. Unknown/missing/drifted aliases or different pg_config fail closed. Local boundary tests cover those refusals; MacCI must prove the final result. This does not establish arbitrary-code isolation or authorize actual archive execution.

### Actual real-directory topology and exact-literal closure
Diagnostic head ca7b1fbf run39012053767/job117336481198 proved the versioned timezone alias is an existing real directory, not a direct directory symlink; canonical Cellar/share/postgresql/timezone exists in the same package. The earlier direct-root-equality refusal was retained, not bypassed. The replacement validates a maximum 4096 entries/depth16/32MiB closed correspondence of canonical and alias trees. Unknown/missing entries, foreign file/directory targets, writable/wrong-owner entries and cycles stop. Each file must be the same package object (including symlink or hardlink identity); only canonical package files are hashed. Only exact literal reads for validated timezone file/directory paths are added, replacing the earlier timezone-subpath permission proposal. No whole timezone subpath, sharedir, extension or user folder is allowed. Runtime binary hashes plus all tree records are compared again after the synthetic probe. These checks do not make the mutable host filesystem atomic or prove complete arbitrary-code isolation; actual archives remain prohibited until separate review.


### Startup directory listing follow-up (not native success)

Exact d111 Mac run 39012212673/job117336965133 passed timezone/read canary but failed native startup opening compiled `/opt/homebrew/lib/postgresql@17`; owned process shutdown was not verified. PostgreSQL REL_17_STABLE `src/backend/postmaster/postmaster.c:getInstallationPaths()` unconditionally opens and closes that directory to validate installation before module loading. This candidate validates `pg_config --pkglibdir`, same package canonical directory, closed immediate name set, corresponding same objects/owner/modes, and grants only the directory literal read for listing. No child module literal, directory subpath, extension or whole lib permission is added. Unknown entries or foreign targets stop before native execution. Exact five binary hashes/timezone and pkglib metadata are compared afterward. This is a source candidate until real Mac CI succeeds; any subsequent module requirement needs separate evidence/review. Actual archive execution/full recovery remain prohibited and unverified.

Primary source: https://github.com/postgres/postgres/blob/REL_17_STABLE/src/backend/postmaster/postmaster.c ; official Homebrew formula source referenced above.


Exact ad9495 run 39012515198/job117337854883 stopped in the new pkglib validator (`Foreign pkglib entry`) before canary/native startup. The next diagnostic reports only fixed installed-runtime entry name/type/targets; it does not expand permissions or accept a real subdirectory without evidence.


Exact 751596 diagnostic run 39012932734/job117339098822 identified `pgxs` as real directories on both sides, with different inodes, consistent with official Homebrew symlink_tree. The validator now accepts only that named directory representation after a bounded (4096 entries/depth16), closed-name recursive metadata comparison whose file leaves resolve to the same package objects and whose owner/modes match. No contents are executed or read by this validator. This correction adds **no sandbox permission**: only the parent pkglib directory literal remains allowed, with no pgxs/descendant literals or subpath. Unknown subtree entries, foreign symlinks, unsafe modes and non-pgxs top-level directories remain rejected. Native success still requires the next real Mac run.


Exact768966 Mac39013026678/job117339378525 stopped before native startup at another top-level directory not in the current named pgxs contract. Diagnostic-only follow-up reports its installed-runtime name/target; no new name is accepted and permissions remain unchanged.


Diagnostic follow-up records the complete bounded immediate runtime-directory inventory on rejection to avoid repeated permission-neutral CI diagnosis. The existing 512-entry limit applies before recording; no unknown entry is accepted.
