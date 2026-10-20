"""Offline connector to the existing unused-undo generator. Never connects to a DB."""
import json
import os
import re
from pathlib import Path
import sys
import common_payroll_unused_undo as undo


def generate(source,target):
    source=Path(source);target=Path(target)
    for path in (source,target.parent):
        if any(p.is_symlink() for p in (path,*path.parents)):raise RuntimeError('private_path_required')
    if not source.is_file() or source.stat().st_mode&0o077 or source.stat().st_size>536870912:raise RuntimeError('private_checkpoint_required')
    if not target.parent.is_dir() or target.parent.stat().st_mode&0o077:raise RuntimeError('private_output_directory_required')
    proof=json.loads(source.read_text())
    if proof.get('schema')!=1 or proof.get('source_hashes')!=undo.common.EXPECTED:raise RuntimeError('source_set_mismatch')
    sql=undo.build_unused_undo(proof['before'],proof['after'])
    all_hash=proof.get('all_application_rows_hash','')
    if not re.fullmatch(r'[a-f0-9]{32}',all_hash):raise RuntimeError('all_application_rows_hash_missing')
    scan=undo.common.BUSINESS_SQL.rsplit('SELECT md5(',1)[0].replace(undo.common.SCOPES,undo.CATALOG_SCOPE)
    guard=scan+"\nDO $all_rows_undo$ BEGIN IF (SELECT md5(coalesce(jsonb_agg(jsonb_build_array(name,hash) ORDER BY name),'[]')::text) FROM common_data_fingerprints) IS DISTINCT FROM "+undo.literal(all_hash)+" THEN RAISE EXCEPTION 'all application rows changed: undo refused'; END IF; END $all_rows_undo$;DROP TABLE common_data_fingerprints;\n"
    marker='END $unused_guard$;'
    if sql.count(marker)!=1:raise RuntimeError('unused_undo_shape_changed')
    sql=sql.replace(marker,marker+'\n'+guard)
    fd=os.open(target,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
    with os.fdopen(fd,'w') as handle:handle.write(sql+'\n')


def main():
    os.umask(0o077)
    if len(sys.argv)!=3:return 1
    try:generate(sys.argv[1],sys.argv[2]);return 0
    except Exception:return 1

if __name__=='__main__':sys.exit(main())
