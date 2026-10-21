"""Local fixture transport only: line JSON over stdio, tmp-only real sqlite3."""
import json
import os
import sqlite3
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
if root.parent != Path('/tmp') or not root.name.startswith('sko-qualification-sqlite-'):
    raise RuntimeError('fixture requires dedicated tmp root')
path = Path(sys.argv[2]).resolve()
if path.parent != root or path.name != 'pending.sqlite3':
    raise RuntimeError('fixture database path is fixed')
connection = sqlite3.connect(str(path), timeout=3, isolation_level=None)
connection.row_factory = sqlite3.Row
for line in sys.stdin:
    request = json.loads(line)
    try:
        sql = request['sql']
        parameters = request.get('parameters', [])
        if request.get('kill') == 'before':
            os._exit(71)
        cursor = connection.execute(sql, parameters)
        rows = [dict(row) for row in cursor.fetchall()] if cursor.description else []
        changed = max(cursor.rowcount, 0)
        if request.get('kill') == 'after':
            os._exit(72)
        print(json.dumps({'rows': rows, 'changed': changed}), flush=True)
    except Exception as error:
        print(json.dumps({'error': type(error).__name__ + ': ' + str(error)}), flush=True)
