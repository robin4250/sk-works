#!/usr/bin/env python3
"""Explicit private TestFlight candidate build only. Never uploads or installs."""
import argparse
import fcntl
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
# External loaders must fetch this sibling from the reviewed helper SHA too.
R31_SHA256='3f0c33ece0f6c0f7c1b1b24caa448c916828fbd6df66b66c7278fe3f0c93dd09'
_r31_path=Path(__file__).with_name('r31_local_release.py')
if _r31_path.is_symlink() or not _r31_path.is_file() or hashlib.sha256(_r31_path.read_bytes()).hexdigest()!=R31_SHA256:
    raise RuntimeError('reviewed R31 dependency required')
_spec=importlib.util.spec_from_file_location('reviewed_r31_dependency',_r31_path)
r31=importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(r31)


def safe_directory(path):
    r31.require(path.is_dir() and not any(p.is_symlink() for p in (path,*path.parents)), 'unsafe private directory')


def read_record(path):
    r31.require(path.is_file() and not path.is_symlink() and path.stat().st_size<4*1024*1024,'checkpoint unavailable')
    return json.loads(path.read_text())


def reject_previous(backups,sha,number):
    entries=list(backups.glob('tf-candidate-*'))
    r31.require(len(entries)<=1000,'checkpoint inventory limit')
    for stage in entries:
        safe_directory(stage)
        record=read_record(stage/'started-private.json')
        r31.require((stage/'complete-private.json').is_file() or (stage/'failed-private.json').is_file(),'previous candidate result unknown; do not rebuild')
        r31.require((record.get('sha'),record.get('build_number'))!=(sha,number),'candidate already attempted; inspect existing checkpoint')


def candidate_command(env_file,stage,sha,number,icon,version,*,preflight=False):
    # Existing preflight + provenance stay intact; only the one fixed IPA build is new.
    return ['bash','-c','set -euo pipefail; set +x; source "$1" >/dev/null 2>&1; set +x; '
      'export SUPABASE_URL SUPABASE_PUBLISHABLE_KEY; '
      'export SKO_AUDITED_SHA="$3" SKO_APP_ICON_SOURCE="$5"; unset CI; '
      + ('python3 tool/testflight_provenance.py configuration; bash tool/testflight_preflight.sh' if preflight else
      'python3 tool/testflight_provenance.py start --marker build/ios/sko-testflight-build-start.json; '
      'flutter build ipa --release --no-pub --export-method app-store '
      '--dart-define=SKO_MASTER_PASSWORD_V1=false --build-number="$4" --build-name="$6" '
      '--dart-define="SUPABASE_URL=$SUPABASE_URL" --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"'),
      'tf-private',str(env_file),str(stage),sha,number,str(icon),version]


def build(root,sha,number,backups):
    r31.require(sys.platform=='darwin','Mac required')
    r31.require(re.fullmatch('[0-9a-f]{40}',sha) and re.fullmatch('[1-9][0-9]*',number),'explicit reviewed SHA and unused build number required')
    safe_directory(root)
    backups.mkdir(mode=0o700,parents=True,exist_ok=True);safe_directory(backups)
    r31.require(backups.stat().st_mode&0o077==0,'private backup permissions required')
    fd=os.open(backups/'testflight-candidate.lock',os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        reject_previous(backups,sha,number)
        stage=Path(tempfile.mkdtemp(prefix='tf-candidate-',dir=backups))
        r31.write_private(stage/'started-private.json',{'schema':1,'sha':sha,'build_number':number,'uploaded':False,'installed':False})
        print('TestFlight候補の作成場所: '+str(stage),flush=True)
        phase='preflight'
        try:
            with (stage/'private.log').open('xb') as log:
                original=r31.Runner(root,log);r31.tools_ready(original)
                before=r31.source_state(original);r31.write_private(stage/'original-private.json',before)
                for name in before['untracked']:
                    origin=root/name;destination=stage/'untracked-before'/name;destination.parent.mkdir(parents=True,exist_ok=True)
                    if origin.is_symlink():destination.symlink_to(os.readlink(origin))
                    else:shutil.copy2(origin,destination)
                original.git('bundle','create',str(stage/'source-before.bundle'),'HEAD');original.git('bundle','verify',str(stage/'source-before.bundle'))
                native=r31.copy_checked(root/'ios',stage/'original-ios')
                old={}
                for name in ('archive','ipa','iphoneos'):
                    target=root/'build/ios'/name
                    if target.exists():old[name]=r31.copy_checked(target,stage/('previous-'+name))
                phase='isolated_source'
                source=stage/'source'
                original.run(['git','clone','--no-hardlinks','--no-checkout',str(root),str(source)])
                runner=r31.Runner(source,log)
                runner.git('remote','set-url','origin','https://github.com/robin4250/sk-works.git')
                runner.git('fetch','--no-tags','origin','+refs/heads/main:refs/remotes/origin/main')
                r31.require(runner.git('rev-parse','origin/main').decode().strip()==sha,'reviewed SHA is not current main')
                runner.git('checkout','-B','main',sha) # Only the brand-new private clone.
                r31.verify_clean(runner,sha)
                phase='exact_ci'
                runner.run(['env','SKO_AUDITED_SHA='+sha,'python3','-c',"import sys;sys.path.insert(0,'tool');import testflight_provenance as p;p.check_ci(p.source())"])
                shutil.copytree(stage/'original-ios',source/'ios',dirs_exist_ok=True,symlinks=True)
                copies=r31.isolate_native_links(root/'ios',source/'ios',cache_root=Path.home()/'.pub-cache',dependencies=stage/'native-dependencies')
                r31.save_dependency_checkpoint(stage,copies)
                icon=next((p for p in (root/'assets/branding/SKO正式アイコン.png',Path.home()/'Downloads/SKO正式アイコン.png') if p.is_file() and not p.is_symlink()),None)
                r31.require(icon is not None,'official icon required')
                env_file=root/'tool/local_supabase_env.sh';r31.require(env_file.is_file() and not env_file.is_symlink(),'local environment unavailable')
                phase='native_prepare'
                runner.run(['env','SKO_APP_ICON_SOURCE='+str(icon),'CI=false','bash','tool/prepare_ios.sh'])
                r31.isolate_native_links(source/'ios',source/'ios',cache_root=Path.home()/'.pub-cache',dependencies=stage/'native-dependencies',approved=copies)
                r31.audit_isolated_links(source/'ios',stage/'native-dependencies')
                r31.verify_clean(runner,sha)
                r31.write_private(stage/'prepared-private.json',{'schema':1,'sha':sha,'native_digest':r31.digest(source/'ios'),'icon_sha256':hashlib.sha256(icon.read_bytes()).hexdigest()})
                phase='candidate_build'
                version_match=re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+\s*$',(source/'pubspec.yaml').read_text(),re.M)
                r31.require(version_match is not None,'version unavailable')
                version=version_match.group(1)
                phase='candidate_preflight'
                runner.run(candidate_command(env_file,stage,sha,number,icon,version,preflight=True))
                # Preflight invokes pub get: its regenerated plugin links must be
                # isolated again before any IPA build or provenance start.
                r31.isolate_native_links(source/'ios',source/'ios',cache_root=Path.home()/'.pub-cache',dependencies=stage/'native-dependencies',approved=copies)
                r31.audit_isolated_links(source/'ios',stage/'native-dependencies')
                r31.verify_clean(runner,sha)
                phase='candidate_build'
                runner.run(candidate_command(env_file,stage,sha,number,icon,version))
                ipas=list((source/'build/ios/ipa').glob('*.ipa'))
                r31.require(len(ipas)==1,'exactly one new IPA required')
                runner.run(['env','SKO_AUDITED_SHA='+sha,'python3','tool/testflight_provenance.py','create','--ipa',str(ipas[0]),'--marker','build/ios/sko-testflight-build-start.json','--manifest','build/ios/sko-testflight-provenance.json','--version',version,'--build',number])
                runner.run(['env','SKO_AUDITED_SHA='+sha,'python3','tool/testflight_provenance.py','validate','--manifest','build/ios/sko-testflight-provenance.json'])
                r31.require(hashlib.sha256(icon.read_bytes()).hexdigest()==read_record(stage/'prepared-private.json')['icon_sha256'],'official icon changed')
                r31.rebase_built_links(source,stage,copies)
                r31.verify_clean(runner,sha)
                manifest=read_record(source/'build/ios/sko-testflight-provenance.json')
                r31.require(manifest.get('commit')==sha and manifest.get('build')==number and manifest.get('bundle_id')==r31.BUNDLE and manifest.get('distribution')=='app-store','candidate manifest mismatch')
                r31.require(r31.source_state(original)==before and r31.inventory(root/'ios')==native,'original checkout changed; never restore automatically')
                r31.require(all(r31.inventory(root/'build/ios'/name)==value for name,value in old.items()),'original artifacts changed')
                r31.write_private(stage/'complete-private.json',{'schema':1,'sha':sha,'build_number':number,'ipa_sha256':manifest['sha256'],'uploaded':False,'installed':False,'testflight_approved':False})
            return stage
        except BaseException:
            r31.write_private(stage/'failed-private.json',{'schema':1,'phase':phase,'uploaded':False,'installed':False})
            raise


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path('/Users/ryuichi/Desktop/sk-works'))
    parser.add_argument('--approved-sha');parser.add_argument('--unused-build-number')
    parser.add_argument('--backup-root',type=Path,default=Path('/Users/ryuichi/SKO-source-backups'))
    args=parser.parse_args()
    os.umask(0o077)
    try:
        stage=build(args.root,args.approved_sha or '',args.unused_build_number or '',args.backup_root)
        result='TestFlight候補の作成と検証が完了しました。アップロード・インストールはしていません。確認場所: '+stage.name
        code=0
    except BaseException:
        result='TestFlight候補の作成は完了確認できません。既存成果を保持しています。再実行せず結果確認が必要です。'
        code=1
    print(result,flush=True)
    if sys.platform=='darwin':
        try:subprocess.run(['/usr/bin/pbcopy'],input=result.encode('utf-8'),check=True)
        except (OSError,subprocess.SubprocessError):pass
    raise SystemExit(code)


if __name__=='__main__':main()
