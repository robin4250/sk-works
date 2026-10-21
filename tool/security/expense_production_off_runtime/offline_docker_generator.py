"""Fixed offline generator bridge for the unchanged runner; no pull/network/SQL."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import stat
import subprocess
import sys
from urllib.parse import urlsplit

RUNTIME=Path(__file__).absolute().parent
IMAGE='sha256:23c24e85395992be118734a39903e08c8f7d1abc73978c46b6bda90060091a49'
SOURCE_HASHES={
 'offline_generator.mjs':'a66c5d219ae0e4a27a33a92975a7a85d4775094b191a940b2e737a74867247c0',
 'expense_default_off_plan.mjs':'5c4c7acedd93fd2fd162179eb4317c0e170877007346e1a0b404e92c1d51b5b9',
 'source/expense_direction_code_checkpoint.mjs':'9a642ea96fc3d564f6c711c2547da5954310f5fdf7f1448abdef2a0dcfa6197f',
 'source/expense_direction_default_off_preparation.mjs':'5e1401c0271be411ae6d1de9ac8f20432380cd4ebd6db2cc0ccffd46e83fdda8',
 'source/expense_payment_direction_v2_20261019.sql.review-only':'770728fa45176d7bbeb77ebd0610f936659624e4b1287d63bd83e0dd9264fe5a',
}
SEARCH='/opt/homebrew/bin:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin:/usr/bin:/bin'

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def private_directory(path):
 if not path.is_absolute() or '..' in path.parts or ',' in str(path) or any(p.is_symlink() for p in (path,*path.parents)):raise RuntimeError('private_path_required')
 metadata=path.stat()
 if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid!=os.getuid() or metadata.st_mode&0o077:raise RuntimeError('private_path_required')

def bound_root():
 path=RUNTIME/'production_transport_binding.py'
 if path.is_symlink():raise RuntimeError('binding_refused')
 spec=importlib.util.spec_from_file_location('_sko_expense_offline_binding',path)
 binding=importlib.util.module_from_spec(spec);spec.loader.exec_module(binding)
 root=binding.APPROVED_DURABLE_ROOT
 if root is None or binding.APPROVED_MANIFEST_SHA256 is None:raise RuntimeError('binding_unapproved')
 private_directory(root)
 approval=root/'production-approval.json'
 metadata=approval.stat()
 if approval.is_symlink() or not stat.S_ISREG(metadata.st_mode) or metadata.st_uid!=os.getuid() or metadata.st_mode&0o077 or digest(approval)!=binding.APPROVED_MANIFEST_SHA256:raise RuntimeError('approval_refused')
 value=json.loads(approval.read_bytes())
 if value.get('schema')!=2 or value.get('transport')!='owner_cli_psql' or value.get('root')!=str(root):raise RuntimeError('approval_refused')
 for name in ('offline_docker_generator.py','offline_docker_generator.sh'):
  file=RUNTIME/name
  if file.is_symlink() or digest(file)!=value.get('code',{}).get(name):raise RuntimeError('wrapper_hash_changed')
 if value.get('node',{}).get('path')!=str(RUNTIME/'offline_docker_generator.sh'):raise RuntimeError('launcher_path_changed')
 return root

def validate_args(arguments,root):
 if len(arguments)!=3 or arguments[0]!=str(RUNTIME/'offline_generator.mjs') or arguments[1] not in ('verify','classify'):raise RuntimeError('generator_arguments_refused')
 stage=Path(arguments[2]);private_directory(stage)
 if stage.parent!=root or not stage.name.startswith(('expense-production-off-review-','expense-production-off-observation-')):raise RuntimeError('stage_scope_refused')
 for name,expected in SOURCE_HASHES.items():
  path=RUNTIME/name
  if path.is_symlink() or not path.is_file() or digest(path)!=expected:raise RuntimeError('generator_source_changed')
 return stage

def docker_command(docker,stage,mode):
 return [docker,'run','--rm','--pull=never','--network=none','--log-driver=none',
  '--read-only','--cap-drop=ALL','--security-opt=no-new-privileges','--pids-limit=64',
  '--user',str(os.getuid())+':'+str(os.getgid()),
  '--mount','type=bind,source='+str(RUNTIME)+',target='+str(RUNTIME)+',readonly',
  '--mount','type=bind,source='+str(stage)+',target='+str(stage),
  '--workdir',str(stage),'--entrypoint','node',IMAGE,str(RUNTIME/'offline_generator.mjs'),mode,str(stage)]

def main():
 try:
  if sys.platform!='darwin' or any(k.startswith('DOCKER_') for k in os.environ):raise RuntimeError('docker_environment_refused')
  root=bound_root();private_directory(RUNTIME)
  stage=validate_args(sys.argv[1:],root)
  docker=shutil.which('docker',path=SEARCH)
  if not docker:raise RuntimeError('existing_docker_required')
  docker=str(Path(docker).resolve(strict=True))
  metadata=Path(docker).stat()
  if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid not in (0,os.getuid()) or metadata.st_mode&0o022:raise RuntimeError('docker_binary_refused')
  # Unchanged runner intentionally passes PATH only. Recover actual user's HOME
  # from the OS account database, never from inherited HOME/DOCKER overrides.
  home=pwd.getpwuid(os.getuid()).pw_dir
  env={'HOME':home,'PATH':SEARCH,'LANG':'C','LC_ALL':'C'}
  def run(args,timeout):
   result=subprocess.run(args,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,timeout=timeout,close_fds=True)
   if result.returncode:raise RuntimeError('offline_docker_failed')
   return result.stdout
  contexts=json.loads(run([docker,'context','inspect'],15))
  if not isinstance(contexts,list) or len(contexts)!=1:raise RuntimeError('local_docker_required')
  endpoint=urlsplit(contexts[0]['Endpoints']['docker']['Host'])
  if endpoint.scheme!='unix' or endpoint.netloc or not endpoint.path.startswith('/') or endpoint.query or endpoint.fragment:raise RuntimeError('local_docker_required')
  images=json.loads(run([docker,'image','inspect',IMAGE],15))
  if not isinstance(images,list) or len(images)!=1 or images[0].get('Id')!=IMAGE or images[0].get('Os')!='linux' or images[0].get('Architecture') not in ('arm64','amd64'):raise RuntimeError('existing_image_changed')
  run(docker_command(docker,stage,sys.argv[2]),25)
  return 0
 except (Exception,KeyboardInterrupt):
  # Existing runner only needs exit status; private inputs/daemon text never log.
  return 2

if __name__=='__main__':raise SystemExit(main())
