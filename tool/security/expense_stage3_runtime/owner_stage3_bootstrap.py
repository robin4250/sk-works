"""Fixed exact-target maintenance bootstrap. No credentials or real IDs embedded."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import zipfile

SOURCE_REF = 'ad099e70b008b073882e5fa170d30e32a5524cbb'
SOURCES = {
  "owner_stage3.py": "434505b15e6c3cb8167577359642d4da3d46acb292e331053629ea7552b59236",
  "stage3_plan.mjs": "e0fc92909160cf63e567f47b71824ec80581dca157696cbea9ac1b94d417a6e4",
  "stage2_plan_reference.mjs": "e90e09584983f9803ff00e28d42ca91205ec87aa1789f0578f25a110d0e149c2",
  "maintenance.sql.review-only": "33e6a0988ddd6f747371f9d4a5b036995b0b798671ef64467e39678894d51572",
  "source/expense_direction_code_checkpoint.mjs": "9a642ea96fc3d564f6c711c2547da5954310f5fdf7f1448abdef2a0dcfa6197f",
  "source/expense_direction_default_off_preparation.mjs": "5e1401c0271be411ae6d1de9ac8f20432380cd4ebd6db2cc0ccffd46e83fdda8",
  "source/negotiation.sql.review-only": "f08628a18891c114c64f7551c33f1139879da3fb1439bac23c8eb54f1995507d"
}
PROJECT = 'ztktgquxvcxcjxtluspu'
PACKET = 'SKO_expense_conversion_packet_20261021.zip'
PACKET_SHA = '33ee132efbebb7f7fbfbb8441cd521dff8cbbe8e5ac7e6ab0b76810aef25ed32'
INPUTS = {
    'stage3-binding.private.json': '17a27852df53b142317957f00ddee7dfb7d6116fe33cfb7919d94b405819e2da',
    'stage3-approval.private.json': '74d96cfb08921d3e4b21ed75ba9a21925b51e034877d54b7460d4d6be654f212',
    'SKO_expense_before_conversion_20261021.zip': '3b5b0c0bfe386a6414d0b5e3cd20cb671d660ae256774b74c2a8f19ca86edb34',
}


def sha(raw):return hashlib.sha256(raw).hexdigest()


def private(path):
    if not path.is_absolute() or any(p.is_symlink() for p in (path,*path.parents)):
        raise RuntimeError('private_path_required')
    st=path.stat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid!=os.getuid() or st.st_mode&0o077:
        raise RuntimeError('private_directory_required')


def read_input(path,private_file=False):
    if any(p.is_symlink() for p in (path,*path.parents)):
        raise RuntimeError('packet_path_refused')
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        st=os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_mode&(0o077 if private_file else 0o022) or not 0<st.st_size<=16777216:
            raise RuntimeError('packet_file_refused')
        raw=os.read(fd,st.st_size+1)
        if len(raw)!=st.st_size:raise RuntimeError('packet_file_changed')
        return raw
    finally:os.close(fd)


def put(path,raw):
    private(path.parent)
    if path.exists() or path.is_symlink():
        if read_input(path,True)!=raw:raise RuntimeError('existing_private_file_differs')
        return
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'wb') as out:
        out.write(raw);out.flush();os.fsync(out.fileno())
    fd=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY)
    try:os.fsync(fd)
    finally:os.close(fd)


def packet_inputs(downloads):
    path=downloads/PACKET
    if path.exists() or path.is_symlink():
        raw=read_input(path)
        if sha(raw)!=PACKET_SHA:raise RuntimeError('packet_hash_differs')
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            names=archive.namelist()
            if len(names)!=4 or set(names)!=set(INPUTS)|{'README.txt'} or sum(x.file_size for x in archive.infolist())>16777216:
                raise RuntimeError('packet_entries_refused')
            values={name:archive.read(name) for name in INPUTS}
    else:
        # Safari may automatically expand a downloaded ZIP. Read only this exact
        # known folder and the three independently hash-pinned data files.
        folder=downloads/Path(PACKET).stem
        if not folder.is_dir() or folder.is_symlink():raise RuntimeError('packet_not_downloaded')
        values={name:read_input(folder/name) for name in INPUTS}
    if any(sha(values[name])!=pin for name,pin in INPUTS.items()):
        raise RuntimeError('private_packet_input_changed')
    return values


def run():
    os.umask(0o077)
    if sys.platform!='darwin' or not sys.flags.isolated:raise RuntimeError('isolated_mac_required')
    root=Path.home()/'SKO-source-backups'/('expense-default-off-production-'+PROJECT)
    private(root)
    marker=root/'expense-stage3-install-attempt.json'
    if marker.exists() or marker.is_symlink():raise RuntimeError('previous_stage3_attempt_requires_readonly_recovery')
    values=packet_inputs(Path.home()/'Downloads')
    data=root/'stage3-private'
    data.mkdir(mode=0o700,exist_ok=True);private(data)
    for name,raw in values.items():put(data/name,raw)
    repo=Path.home()/'Desktop'/'sk-works'
    subprocess.run(['git','-C',str(repo),'fetch','--no-tags','--no-write-fetch-head','origin',SOURCE_REF],
                   stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=120)
    sources={name:subprocess.check_output(['git','-C',str(repo),'show',SOURCE_REF+':tool/security/expense_stage3_runtime/'+name],
                                        stderr=subprocess.DEVNULL,timeout=30) for name in SOURCES}
    if not SOURCES or any(sha(sources[name])!=pin for name,pin in SOURCES.items()):
        raise RuntimeError('stage3_source_hash_changed')
    package=root/'stage3-runtime'
    package.mkdir(mode=0o700,exist_ok=True);private(package)
    for name,raw in sources.items():
        target=package/name
        target.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
        put(target,raw)
    spec=importlib.util.spec_from_file_location('_sko_exact_stage3_owner',package/'owner_stage3.py')
    owner=importlib.util.module_from_spec(spec);spec.loader.exec_module(owner)
    result=owner.run(root,package,SOURCES,
                     data/'stage3-binding.private.json',INPUTS['stage3-binding.private.json'],
                     data/'stage3-approval.private.json',INPUTS['stage3-approval.private.json'],
                     data/'SKO_expense_before_conversion_20261021.zip',INPUTS['SKO_expense_before_conversion_20261021.zip'])
    owner.copy_result(result)
    return 0 if result.get('conversion_verified') is True else 1


def main():
    try:return run()
    except (Exception,KeyboardInterrupt) as error:
        code=str(error) if re.fullmatch('[a-z_]{1,80}',str(error)) else 'stage3_requires_review'
        raw=json.dumps({'schema':3,'project':PROJECT,'phase':'requires_review','failure_code':code,
                        'conversion_verified':False,'retry_allowed':False,'complete':False},sort_keys=True)
        print(raw,flush=True)
        if sys.platform=='darwin':
            try:subprocess.run(['/usr/bin/pbcopy'],input=raw,text=True,check=True,timeout=10)
            except (Exception,KeyboardInterrupt):pass
        return 1


if __name__=='__main__':raise SystemExit(main())
