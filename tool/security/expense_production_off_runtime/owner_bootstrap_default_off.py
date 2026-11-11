"""Fixed Mac bootstrap for the reviewed, still-default-OFF expense install."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import zlib

SOURCE_REF = "994342fc136045d8ce6769b55f606952111808e6"
APPROVAL_SHA256 = "4a79fc645f3c2f7d4cfee885abcc3d9054048102d3e71cf17c21082887880a4f"
SOURCE_HASHES = {
    "cli_psql_transport.py": "8dee8cb358afc0f2e82232ad67e4dbfd95ea9e7542941e02a2fd8b1ad0051ede",
    "offline_generator.mjs": "a66c5d219ae0e4a27a33a92975a7a85d4775094b191a940b2e737a74867247c0",
    "expense_default_off_plan.mjs": "5c4c7acedd93fd2fd162179eb4317c0e170877007346e1a0b404e92c1d51b5b9",
    "owner_cli_preflight.py": "b44ba1adffb7fab6496b4b39c3cb4379f56b979577423f6582c38d62f5a0b279",
    "offline_docker_generator.py": "15dee287cf280a4c99cda6d24caefe24323e61cf947334f2f9f74255af6cde52",
    "review_runner.py": "a3eb27c6c0c349b9eddd68b2124b0d581e7d64eaae6f85ae99ddb71317800aab",
    "offline_docker_generator.sh": "8640e78115fc7f3f8827c710edbc603e8242a29d037b4a0eacf911b9e872471b",
    "owner_install_bound_default_off.py": "0d128154ac783d5322b11ea695f339e314189e6cc52b2125883f6bf26f5d302a",
    "owner_cli_source/owner_database_capture.py": "15875c927d90364f8dec1973f5fb1661dc12b9f5242aee5175203f7cb8a8702d",
    "owner_cli_source/owner_expense_fresh_checkpoint.py": "85713123cf507ae38f265e0f39433091c0935e0279775d01e94c1e5a8ff48d30",
    "owner_cli_source/owner_cli_database_capture.py": "e4f206b3dab91f98295f2f2a1688a02cc74adb80d00d6262a3f3ce4cc9a300e0",
    "source/expense_direction_code_checkpoint.mjs": "9a642ea96fc3d564f6c711c2547da5954310f5fdf7f1448abdef2a0dcfa6197f",
    "source/expense_direction_default_off_preparation.mjs": "5e1401c0271be411ae6d1de9ac8f20432380cd4ebd6db2cc0ccffd46e83fdda8",
    "source/expense_payment_direction_v2_20261019.sql.review-only": "770728fa45176d7bbeb77ebd0610f936659624e4b1287d63bd83e0dd9264fe5a"
}
PROJECT = "ztktgquxvcxcjxtluspu"
PREFIX = "tool/security/expense_production_off_runtime/"


class BootstrapRefused(RuntimeError):
    pass


def require_private(path):
    if not path.is_absolute() or ".." in path.parts or any(p.is_symlink() for p in (path, *path.parents)):
        raise BootstrapRefused("private_root_required")
    st = path.stat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise BootstrapRefused("private_root_required")


def put_once(path, raw, mode=0o600):
    require_private(path.parent)
    if path.exists() or path.is_symlink():
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077 or st.st_size != len(raw):
                raise BootstrapRefused("existing_runtime_refused")
            if os.read(fd, len(raw) + 1) != raw:
                raise BootstrapRefused("existing_runtime_differs")
        finally:
            os.close(fd)
        return
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    try:
        with os.fdopen(fd, "wb", closefd=False) as out:
            out.write(raw)
            out.flush()
            os.fsync(fd)
    finally:
        os.close(fd)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def run(encoded):
    os.umask(0o077)
    if sys.platform != "darwin" or not sys.flags.isolated:
        raise BootstrapRefused("isolated_mac_python_required")
    if len(encoded) > 8192:
        raise BootstrapRefused("approval_encoding_refused")
    packed = base64.b64decode(encoded, validate=True)
    unpacker = zlib.decompressobj()
    raw = unpacker.decompress(packed, 16385)
    if not unpacker.eof or unpacker.unused_data or len(raw) > 16384 or hashlib.sha256(raw).hexdigest() != APPROVAL_SHA256:
        raise BootstrapRefused("approved_manifest_changed")
    approval = json.loads(raw)
    root = Path(approval["root"])
    expected = Path.home() / "SKO-source-backups" / ("expense-default-off-production-" + PROJECT)
    if root != expected or approval.get("project") != PROJECT:
        raise BootstrapRefused("fixed_operator_root_required")
    require_private(root)
    marker = root / "expense-default-off-install-attempt.json"
    if marker.exists() or marker.is_symlink():
        raise BootstrapRefused("previous_attempt_requires_readonly_recovery")
    repo = Path.home() / "Desktop" / "sk-works"
    subprocess.run(["git", "-C", str(repo), "fetch", "--no-tags", "--no-write-fetch-head", "origin", SOURCE_REF],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=120)
    sources = {name: subprocess.check_output(["git", "-C", str(repo), "show", SOURCE_REF + ":" + PREFIX + name],
                    stderr=subprocess.DEVNULL, timeout=30) for name in SOURCE_HASHES}
    if any(hashlib.sha256(sources[name]).hexdigest() != wanted for name, wanted in SOURCE_HASHES.items()):
        raise BootstrapRefused("reviewed_runtime_hash_changed")
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700, exist_ok=True)
    require_private(runtime)
    for name, content in sources.items():
        target = runtime / name
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        put_once(target, content)
    (runtime / "offline_docker_generator.sh").chmod(0o700)
    put_once(root / "production-approval.json", raw)
    binding = "from pathlib import Path\nAPPROVED_DURABLE_ROOT = Path(" + repr(str(root)) + ")\nAPPROVED_MANIFEST_SHA256 = " + repr(APPROVAL_SHA256) + "\n"
    put_once(runtime / "production_transport_binding.py", binding.encode())
    spec = importlib.util.spec_from_file_location("_sko_bound_owner", runtime / "owner_install_bound_default_off.py")
    owner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(owner)
    source = Path.home() / "SKO-source-backups" / "expense-prepare-only-8co2mzki"
    return owner.run_owner(source, root, runtime, APPROVAL_SHA256)


def main():
    try:
        if len(sys.argv) != 2:
            raise BootstrapRefused("fixed_approval_required")
        return run(sys.argv[1])
    except (Exception, KeyboardInterrupt) as error:
        code = str(error) if isinstance(error, BootstrapRefused) else "bootstrap_incomplete"
        result = json.dumps({"schema": 1, "project": PROJECT, "phase": "requires_review",
                             "failure_code": code, "deployment_performed": None,
                             "application_data_mutations": False, "conversion_performed": False,
                             "retry_allowed": False, "complete": False}, sort_keys=True)
        print(result, flush=True)
        if sys.platform == "darwin":
            try:
                subprocess.run(["/usr/bin/pbcopy"], input=result, text=True, check=True, timeout=10)
            except (Exception, KeyboardInterrupt):
                pass
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
