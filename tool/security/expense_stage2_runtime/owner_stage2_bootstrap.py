"""Pinned Mac supplemental expense installer; no gate activation or conversion."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

SOURCE_REF = "1cef07c7d0d16b83b07df14ff3c4b5a9d4c0d37a"
PREFIX = "tool/security/expense_stage2_runtime/"
PROJECT = "ztktgquxvcxcjxtluspu"
SOURCES = {
  "owner_stage2.py": "8a3a403b7f8daea5420ee60987440c91515bdd64703f19c30192b0cf26e5e8ad",
  "stage2_plan.mjs": "e90e09584983f9803ff00e28d42ca91205ec87aa1789f0578f25a110d0e149c2",
  "source/expense_direction_code_checkpoint.mjs": "9a642ea96fc3d564f6c711c2547da5954310f5fdf7f1448abdef2a0dcfa6197f",
  "source/negotiation.sql.review-only": "f08628a18891c114c64f7551c33f1139879da3fb1439bac23c8eb54f1995507d",
  "source/expense_direction_default_off_preparation.mjs": "5e1401c0271be411ae6d1de9ac8f20432380cd4ebd6db2cc0ccffd46e83fdda8",
  "source/converter.sql.review-only": "725ff2533539c63759c92c0bbc45d37c131fa431c421fd76deb127bdff2604d7"
}
RUNTIME_SOURCES = {
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

def private(path):
    if not path.is_absolute() or any(p.is_symlink() for p in (path,*path.parents)):
        raise RuntimeError("private_path_required")
    st=path.stat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid!=os.getuid() or st.st_mode&0o077:
        raise RuntimeError("private_directory_required")

def put(path,raw):
    private(path.parent)
    if path.exists() or path.is_symlink():
        fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
        try:
            st=os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_mode&0o077 or st.st_size!=len(raw) or os.read(fd,len(raw)+1)!=raw:
                raise RuntimeError("existing_package_differs")
        finally:os.close(fd)
        return
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,"wb") as out:
        out.write(raw);out.flush();os.fsync(out.fileno())
    fd=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY)
    try:os.fsync(fd)
    finally:os.close(fd)

def run():
    os.umask(0o077)
    if sys.platform!="darwin" or not sys.flags.isolated:
        raise RuntimeError("isolated_mac_required")
    root=Path.home()/"SKO-source-backups"/("expense-default-off-production-"+PROJECT)
    private(root)
    marker=root/"expense-stage2-install-attempt.json"
    if marker.exists() or marker.is_symlink():
        raise RuntimeError("previous_stage2_attempt_requires_readonly_recovery")
    repo=Path.home()/"Desktop"/"sk-works"
    subprocess.run(["git","-C",str(repo),"fetch","--no-tags","--no-write-fetch-head","origin",SOURCE_REF],
                   stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=120)
    sources={name:subprocess.check_output(["git","-C",str(repo),"show",SOURCE_REF+":"+PREFIX+name],
                                        stderr=subprocess.DEVNULL,timeout=30) for name in SOURCES}
    if any(hashlib.sha256(sources[name]).hexdigest()!=pin for name,pin in SOURCES.items()):
        raise RuntimeError("package_source_hash_changed")
    package=root/"stage2-runtime"
    package.mkdir(mode=0o700,exist_ok=True);private(package)
    for name,raw in sources.items():
        target=package/name
        target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
        put(target,raw)
    spec=importlib.util.spec_from_file_location("_sko_stage2_owner",package/"owner_stage2.py")
    owner=importlib.util.module_from_spec(spec);spec.loader.exec_module(owner)
    receipt=owner.prepare(root,package,owner.offline_docker,SOURCES,RUNTIME_SOURCES)
    stage=root/receipt["stage"]
    result=owner.install_prepared(root,package,stage,owner.offline_docker,receipt["install_sha256"])
    owner.copy_result(result)
    return 0 if result.get("deployment_performed") is True else 1

def main():
    try:return run()
    except (Exception,KeyboardInterrupt):
        result=json.dumps({"schema":1,"project":PROJECT,"phase":"requires_review","deployment_performed":None,
                           "application_data_mutations":False,"conversion_performed":False,"retry_allowed":False,"complete":False},sort_keys=True)
        print(result,flush=True)
        if sys.platform=="darwin":
            try:subprocess.run(["/usr/bin/pbcopy"],input=result,text=True,check=True,timeout=10)
            except (Exception,KeyboardInterrupt):pass
        return 1

if __name__=="__main__":
    raise SystemExit(main())
