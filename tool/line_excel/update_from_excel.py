"""Read xlsx controls with stdlib; fetch originals only, never edit the xlsx."""
import datetime as dt
import json
import os
from pathlib import Path
import posixpath
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

N = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
     'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}


def controls(path):
    with zipfile.ZipFile(path) as archive:
        sheets = ET.fromstring(archive.read('xl/workbook.xml')).find('s:sheets', N)
        sheet = next(s for s in sheets if s.get('name') == 'LINE連携設定')
        rel_id = sheet.get('{' + N['r'] + '}id')
        relations = ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))
        target = next(r.get('Target') for r in relations if r.get('Id') == rel_id)
        target = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)
        if not target.startswith('xl/worksheets/') or '..' in target:
            raise ValueError('設定ページの参照が不正です')
        strings = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            for item in ET.fromstring(archive.read('xl/sharedStrings.xml')):
                strings.append(''.join(item.itertext()))
        cells = {}
        for cell in ET.fromstring(archive.read(target)).findall('.//s:c', N):
            if cell.get('r') not in ('B4', 'B5', 'B6', 'B7'):
                continue
            if cell.find('s:f', N) is not None:
                raise ValueError('接続設定は数式ではなく直接入力してください')
            value = cell.find('s:v', N)
            text = value.text if value is not None else ''
            if cell.get('t') == 's':
                text = strings[int(text)]
            elif cell.get('t') == 'inlineStr':
                text = ''.join(cell.find('s:is', N).itertext())
            cells[cell.get('r')] = text or ''
        for address in ('B5', 'B6'):
            text = cells.get(address, '')
            if text.isdigit():
                text = (dt.date(1899, 12, 30) + dt.timedelta(days=int(text))).isoformat()
            dt.date.fromisoformat(text)
            cells[address] = text
        if not cells.get('B4', '').strip():
            raise ValueError('LINE連携設定にグループ名を入力してください')
        return cells


def main():
    root = Path(__file__).resolve().parent
    try:
        values = controls(root / 'SKO_LINE管理.xlsx')
    except (ValueError, KeyError, StopIteration, zipfile.BadZipFile):
        raise SystemExit('ExcelのLINE連携設定で、グループ名・開始日・終了日を確認してください。') from None
    command = [sys.executable, str(root / 'sync.py'), '--url', 'https://ztktgquxvcxcjxtluspu.supabase.co',
               '--group', values['B4'].strip(), '--from-date', values['B5'], '--to-date', values['B6'],
               '--output', str(root / '原文')]
    if values.get('B7', '').strip():
        command += ['--group-id', values['B7'].strip()]
    environment = dict(os.environ)
    config_path = root / '接続設定.json'
    if not environment.get('SKO_ANON_KEY') and config_path.exists():
        environment['SKO_ANON_KEY'] = json.loads(config_path.read_text(encoding='utf-8'))['publishable_key']
    if not environment.get('SKO_ACCESS_TOKEN'):
        command.append('--login')
    return subprocess.call(command, cwd=root, env=environment)


if __name__ == '__main__':
    raise SystemExit(main())
