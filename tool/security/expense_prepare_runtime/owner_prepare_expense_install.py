#!/usr/bin/env python3
"""Prepare private expense SQL offline using an already captured fresh checkpoint."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


RUNTIME_SHA256={'expense_default_off_plan.mjs': '5c4c7acedd93fd2fd162179eb4317c0e170877007346e1a0b404e92c1d51b5b9', 'private_generator.mjs': '9d00f4f7914121a538a97e57eded6dc91b27fb6581af963de9b085602090abcb', 'source/expense_direction_code_checkpoint.mjs': '9a642ea96fc3d564f6c711c2547da5954310f5fdf7f1448abdef2a0dcfa6197f', 'source/expense_direction_default_off_preparation.mjs': '5e1401c0271be411ae6d1de9ac8f20432380cd4ebd6db2cc0ccffd46e83fdda8', 'source/expense_payment_direction_v2_20261019.sql.review-only': '770728fa45176d7bbeb77ebd0610f936659624e4b1287d63bd83e0dd9264fe5a'}

def check(value,code):
    if not value:raise RuntimeError(code)


def private_path(path):
    check(not any(p.is_symlink() for p in (path,*path.parents)),'symlink_refused')
    check(not path.stat().st_mode&0o077,'private_permissions_required')


def main():
    os.umask(0o077);stage=None;state={'schema':1,'verified':False,'prepare_only':True,'production_connected':False,'deployment_performed':False,'conversion_performed':False};code=1
    try:
        check(sys.platform=='darwin','mac_required')
        check(not os.environ.get('DOCKER_HOST') and not os.environ.get('DOCKER_CONTEXT'),'docker_override_refused')
        root=Path.home()/'SKO-source-backups';private_path(root)
        candidates=sorted((p for p in root.glob('expense-fresh-checkpoint-*') if p.is_dir() and not p.is_symlink()),key=lambda p:p.stat().st_mtime)
        check(bool(candidates),'fresh_checkpoint_required');source=candidates[-1];private_path(source)
        record_path=source/'private-fresh-before.json';status_path=source/'checkpoint-status.json'
        private_path(status_path);status=json.loads(status_path.read_text())
        check(status.get('verified') is True and status.get('scope_guard_matched') is True and status.get('readonly_verified') is True,'latest_fresh_checkpoint_not_verified')
        private_path(record_path);record_bytes=record_path.read_bytes();check(len(record_bytes)<16777216 and hashlib.sha256(record_bytes).hexdigest()==status.get('artifact_sha256'),'fresh_checkpoint_integrity_failed')
        record=json.loads(record_bytes)
        check(record.get('read_only')=='on' and record.get('exact_target_count')==1 and record.get('global_v2_or_basis_count')==0,'fresh_scope_invalid')
        stage=Path(tempfile.mkdtemp(prefix='expense-prepare-only-',dir=root));state['phase']='local_generator'
        env={k:v for k,v in os.environ.items() if not k.startswith('PG') and k not in ('SUPABASE_DB_PASSWORD','DB_PASSWORD')}
        def run(args):
            result=subprocess.run(args,env=env,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=120)
            check(result.returncode==0,'local_generator_failed');return result.stdout
        context=json.loads(run(['docker','context','inspect']));check(context[0]['Endpoints']['docker']['Host'].startswith('unix://'),'remote_docker_refused')
        info=json.loads(run(['docker','image','inspect','node:22.21.0']))[0];image=info['Id']
        check(re.fullmatch(r'sha256:[a-f0-9]{64}',image) is not None and info.get('Os')=='linux' and info.get('Architecture') in ('arm64','amd64'),'existing_node_image_invalid')
        work=Path(__file__).parent
        for name,expected in RUNTIME_SHA256.items():
            file=work/name
            check(file.is_file() and not file.is_symlink() and hashlib.sha256(file.read_bytes()).hexdigest()==expected,'runtime_source_integrity_failed')
        check(set(p.name for p in (work/'source').iterdir())==set(Path(n).name for n in RUNTIME_SHA256 if n.startswith('source/')),'runtime_source_scope_changed')
        for name in ('private_generator.mjs','expense_default_off_plan.mjs'):shutil.copyfile(work/name,stage/name)
        (stage/'source').mkdir(mode=0o700)
        for file in (work/'source').iterdir():
            check(file.is_file() and not file.is_symlink(),'source_file_invalid');shutil.copyfile(file,stage/'source'/file.name)
        (stage/'private-fresh-before.json').write_bytes(record_bytes)
        run(['docker','run','--rm','--network=none','--log-driver=none','--user',str(os.getuid())+':'+str(os.getgid()),'--mount','type=bind,source='+str(stage)+',target=/work','--workdir','/work',image,'node','private_generator.mjs'])
        for name in ('private-prepared-install.sql.review-only','private-read-actual-after.sql.read-only'):
            p=stage/name;private_path(p);check(p.is_file() and p.stat().st_size>0,'prepared_artifact_missing')
            state.setdefault('artifacts',{})[name]={'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}
        state.update(verified=True,phase='prepared',source_checkpoint_sha256=status['artifact_sha256'],generator_image_id=image);code=0
    except (Exception,KeyboardInterrupt) as error:
        if isinstance(error,RuntimeError) and error.args and isinstance(error.args[0],str) and re.fullmatch(r'[a-z_]{1,80}',error.args[0]):state['failure_code']=error.args[0]
    finally:
        if stage:(stage/'prepare-status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
    result=('経費の導入前SQLとCOMMIT結果照合用SQLを非公開で準備: '+stage.name+'。' if state['verified'] else '経費の導入前準備は未完了（'+state.get('failure_code','prepare_failed')+'）。')+'本番接続・導入・金額変換は行っていません。'
    print(result,flush=True)
    if sys.platform=='darwin':subprocess.run(['/usr/bin/pbcopy'],input=result,text=True,check=False)
    return code

if __name__=='__main__':sys.exit(main())
