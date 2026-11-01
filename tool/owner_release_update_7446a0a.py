#!/usr/bin/env python3
"""Owner-only fixed Release update. Present only after exact main CI is cleared."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

TARGET = "7446a0a2ef850423d6953598b4349881c7440b86"
HELPER_SHA = "3f0c33ece0f6c0f7c1b1b24caa448c916828fbd6df66b66c7278fe3f0c93dd09"
ROOT = Path("/Users/ryuichi/Desktop/sk-works")
BACKUP = Path("/Users/ryuichi/SKO-source-backups")
BUILD_PREFIX = "Private checkpoint: "
BUILD_OK = "Owner Release build verified; NOT installed; private checkpoint: "
INSTALL_OK = "Owner Release overwrite install/launch complete; actual login/data/roles remain to test. NOT TestFlight approval."

class UpdateStopped(Exception):
    pass

def require(value, message):
    if not value:
        raise UpdateStopped(message)

def plain_file(path):
    return path.is_file() and not path.is_symlink()

def verified_checkpoint(stdout, code, backup, root):
    lines = stdout.splitlines()
    values = [line[len(BUILD_PREFIX):] for line in lines if line.startswith(BUILD_PREFIX)]
    require(code == 0 and len(values) == 1, "build_not_verified")
    stage = Path(values[0])
    require(stage.is_absolute() and re.fullmatch(r"r31-[A-Za-z0-9_]+", stage.name)
            and stage.parent == backup and stage.is_dir() and not stage.is_symlink()
            and not backup.is_symlink() and backup.resolve() == backup
            and stage.resolve().parent == backup, "checkpoint_not_verified")
    require(lines.count(BUILD_OK + str(stage)) == 1, "build_not_verified")
    for path in [stage/"built-private.json", stage/"source/tool/r31_local_release.py"]:
        require(plain_file(path), "receipt_not_verified")
    require(not (stage/"source").is_symlink() and not (stage/"source/tool").is_symlink(),
            "receipt_not_verified")
    saved = json.loads((stage/"built-private.json").read_text())
    require(saved.get("sha") == TARGET and saved.get("checkpoint_schema") == 2
            and saved.get("owner_only") is True and saved.get("testflight_approved") is False
            and saved.get("source") == str(stage/"source") and saved.get("root") == str(root),
            "receipt_not_verified")
    settings = saved.get("release_settings_proof", {})
    require(settings.get("CONFIGURATION") == "Release"
            and settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "com.skworks.skWorks"
            and settings.get("FLUTTER_BUILD_MODE", "release") == "release",
            "release_not_verified")
    require(saved.get("release_command") == ["flutter", "build", "ios", "--release",
            "--dart-define=SKO_MASTER_PASSWORD_V1=false"], "release_not_verified")
    require(hashlib.sha256((stage/"source/tool/r31_local_release.py").read_bytes()).hexdigest()
            == HELPER_SHA, "helper_not_verified")
    return stage

def save_state(path, value):
    with path.open("x") as handle:
        json.dump(value, handle)
        handle.flush()
        os.fsync(handle.fileno())

def update(helper, root, backup, runner=subprocess.run):
    require(backup.is_dir() and not backup.is_symlink() and backup.resolve() == backup,
            "backup_not_verified")
    attempt = backup/("owner-update-" + TARGET)
    try:
        attempt.mkdir(mode=0o700)
    except FileExistsError:
        raise UpdateStopped("prior_update_attempt_preserved")
    save_state(attempt/"started.json", {"sha":TARGET,"status":"build_started"})
    print("SKO Release: build started", flush=True)
    result = runner([sys.executable,str(helper),"--reviewed-sha",TARGET,
                     "--root",str(root),"--backup-root",str(backup)],
                    capture_output=True,text=True)
    stage = verified_checkpoint(result.stdout,result.returncode,backup,root)
    save_state(attempt/"build-verified.json",
        {"sha":TARGET,"checkpoint":stage.name,"status":"verified_NOT_installed"})
    print("SKO Release: build verified; checkpoint: " + stage.name, flush=True)
    log = stage/"install-private.log"
    require(not log.exists() and not log.is_symlink(), "prior_install_attempt_preserved")
    save_state(attempt/"install-started.json",
        {"sha":TARGET,"checkpoint":stage.name,"status":"install_started_result_unknown"})
    result = runner([sys.executable,str(stage/"source/tool/r31_local_release.py"),
                     "--install-checkpoint",str(stage)],capture_output=True,text=True)
    require(result.returncode == 0 and result.stdout.splitlines().count(INSTALL_OK) == 1,
            "install_result_not_confirmed")
    receipt = {"sha":TARGET,"checkpoint":stage.name,
               "status":"overwrite_install_and_launch_command_succeeded",
               "standalone_home_and_feature_checks":"pending"}
    save_state(attempt/"command-success.json", receipt)
    return receipt

def main():
    os.umask(0o077)
    require(sys.platform == "darwin", "mac_required")
    require(ROOT.is_dir() and not ROOT.is_symlink(), "source_root_not_verified")
    remote = subprocess.run(["git","-C",str(ROOT),"ls-remote","--exit-code",
        "origin","refs/heads/main"],capture_output=True,text=True,timeout=60)
    require(remote.returncode == 0 and remote.stdout.split() == [TARGET,"refs/heads/main"],
            "main_target_changed_or_unavailable")
    fetched = subprocess.run(["git","-C",str(ROOT),"fetch","--no-tags","--no-write-fetch-head",
        "origin",TARGET],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=180)
    require(fetched.returncode == 0, "source_fetch_failed")
    shown = subprocess.run(["git","-C",str(ROOT),"show",TARGET+":tool/r31_local_release.py"],
        capture_output=True,timeout=30)
    require(shown.returncode == 0 and hashlib.sha256(shown.stdout).hexdigest() == HELPER_SHA,
            "helper_not_verified")
    helper = Path(tempfile.mkdtemp(prefix="sko-reviewed-release-"))/"r31_local_release.py"
    helper.write_bytes(shown.stdout)
    receipt = update(helper,ROOT,BACKUP)
    summary = ("SKO Release update\nSHA: " + TARGET + "\ncheckpoint: " + receipt["checkpoint"]
        + "\nresult: overwrite install and launch command succeeded\n"
        + "iPhone Home and feature checks: pending")
    print(summary,flush=True)
    copied = subprocess.run(["pbcopy"],input=summary,text=True,stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    print("Result copied" if copied.returncode == 0 else "Clipboard unavailable; do not rerun update",
          flush=True)
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except UpdateStopped as error:
        print("SKO stopped: " + str(error) + "; checkpoint preserved; do not rerun automatically",
              flush=True)
        sys.exit(1)
    except Exception:
        print("SKO stopped: private result requires review; checkpoint preserved; do not rerun",
              flush=True)
        sys.exit(1)
