"""Conservative, offline LINE preparation. No production writes or invoice issuance."""
import collections
import datetime as dt
import decimal
import hashlib
import json
import re
import sqlite3
import unicodedata

D = decimal.Decimal


def normalize(value):
    return unicodedata.normalize('NFKC', value)


def parse(text, workers, sites, allowances=('鉄骨', 'PC')):
    """Dictionary-based tokens; shared quantities remain unresolved."""
    source = normalize(text)
    lookup = {}
    for category, names in [('site', sites), ('worker', workers), ('allowance', allowances)]:
        for name in names:
            lookup.setdefault(normalize(name), []).append((category, name))
    labels = {'残業': 'overtime', '早出': 'early', '定時': 'regular', '夜勤': 'night'}
    words = sorted(set(lookup) | set(labels), key=lambda x: (-len(x), x))
    if not words or any(not word for word in words):
        raise ValueError('空の辞書語句は使用できません')
    pattern = re.compile('|'.join(map(re.escape, words)))
    rows, issues, tokens = [], [], []
    site, pending, current = None, [], []
    cursor = 0
    for match in pattern.finditer(source):
        if match.start() < cursor:
            continue
        gap = source[cursor:match.start()]
        if gap.strip(' \t\n\r、,/:：・'):
            issues.append('未分類語句: ' + gap)
        word = match.group()
        tokens.append(word)
        cursor = match.end()
        if word in lookup:
            if len(lookup[word]) != 1:
                issues.append('辞書の分類重複: ' + word)
                pending = []
                current = []
                continue
            kind, name = lookup[word][0]
            if kind == 'site':
                site, pending, current = name, [], []
                continue
            if kind == 'worker':
                pending.append(name)
                current = []
                continue
            kind = 'allowance:' + name
        else:
            kind = labels[word]
        value = None
        if kind in ('overtime', 'early') or kind.startswith('allowance:'):
            quantity = re.match(r'\s*[:：]?\s*(\d+(?:\.\d+)?)(時間|分|[hH])?', source[cursor:])
            if quantity:
                value = D(quantity[1]) / (60 if quantity[2] == '分' else 1)
                cursor += quantity.end()
            elif kind.startswith('allowance:'):
                value = D(1)
            else:
                issues.append(word + 'の数量未指定')
        if pending:
            current = []
            for person in pending:
                row = {'site': site, 'worker': person, 'overtime': None, 'early': None,
                       'regular': False, 'night': False, 'allowances': {}, 'issues': []}
                rows.append(row)
                current.append(row)
            pending = []
        if not current:
            issues.append(word + 'の対象者未指定')
            continue
        if len(current) > 1 and (kind in ('overtime', 'early') or kind.startswith('allowance:')):
            for row in current:
                row['issues'].append(word + 'の対象者要確認')
            continue
        for row in current:
            if kind.startswith('allowance:'):
                key = kind.split(':', 1)[1]
                if key in row['allowances']:
                    row['issues'].append(word + 'の重複数量')
                else:
                    row['allowances'][key] = value
            elif kind in ('regular', 'night'):
                row[kind] = True
            elif row[kind] is not None:
                row['issues'].append(word + 'の重複数量')
            else:
                row[kind] = value
    if source[cursor:].strip():
        issues.append('未分類語句: ' + source[cursor:])
    for person in pending:
        rows.append({'site': site, 'worker': person, 'overtime': None, 'early': None,
                     'regular': False, 'night': False, 'allowances': {}, 'issues': ['勤務内容未指定']})
    for row in rows:
        if row['site'] is None:
            row['issues'].append('現場未指定')
        if row['regular'] and row['overtime'] not in (None, D(0)):
            row['issues'].append('定時と残業の併記')
        row['issues'].extend(issues)
        row['status'] = '要確認' if row['issues'] else '解析候補・未承認'
    return {'rows': rows, 'issues': issues, 'tokens': tokens, 'original': text}


def ranking(results):
    counts = collections.Counter(token for result in results for token in result['tokens'])
    return sorted(counts.items(), key=lambda item: (-item[1], item[0]))


class SourceStore:
    """Append-only originals. Identity includes group; conflicting edits are retained."""
    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.execute('create table if not exists sources (group_id text, message_id text, digest text, payload text, primary key(group_id,message_id,digest))')

    def import_messages(self, group_id, messages):
        added = conflicts = 0
        with self.db:
            for message in messages:
                if not isinstance(message.get('id'), str) or not message['id']:
                    raise ValueError('元メッセージIDが必要です')
                if message.get('communication_group_id', group_id) != group_id:
                    raise ValueError('異なるグループのメッセージです')
                payload = json.dumps(message, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
                digest = hashlib.sha256(payload.encode()).hexdigest()
                existing = self.db.execute('select digest from sources where group_id=? and message_id=?', (group_id, message['id'])).fetchall()
                cursor = self.db.execute('insert or ignore into sources values (?,?,?,?)', (group_id, message['id'], digest, payload))
                added += cursor.rowcount
                conflicts += int(bool(existing) and cursor.rowcount == 1)
        return {'fetched': len(messages), 'added': added, 'conflicts': conflicts}


def reconcile(rows):
    """Exact replay IDs collapse; matching work facts across sources require review."""
    identities, facts, output = set(), {}, []
    for source in rows:
        row = dict(source)
        identity = (row['source_kind'], row['source_id'], row.get('source_line', ''), row['site'], row['worker'], row.get('shift', 'day'))
        if identity in identities:
            continue
        identities.add(identity)
        fact = (row['date'], row['site'], row['worker'], row.get('shift', 'day'))
        dt.date.fromisoformat(row['date'])
        row['status'] = '要確認'
        row['reason'] = row.get('reason', '勤務実績の承認待ち')
        if fact in facts:
            row['reason'] = '同日・現場・従業員の重複候補'
            output[facts[fact]]['reason'] = row['reason']
        else:
            facts[fact] = len(output)
        output.append(row)
    return output


def invoice_preview(days, overtime, steel, *, day_rate='32800', hours='8', multiplier='1.25', steel_rate='3000', welfare='0.15', tax='0.10'):
    """Draft arithmetic only. Decimal strings, no expression evaluation."""
    values = list(map(lambda x: D(str(x)), (days, overtime, steel, day_rate, hours, multiplier, steel_rate, welfare, tax)))
    if any(not x.is_finite() or x < 0 for x in values) or values[4] == 0:
        raise ValueError('単価・数量・標準時間を確認してください')
    days, overtime, steel, rate, hours, multiplier, steel_rate, welfare, tax = values
    yen = lambda value: value.quantize(D(1), rounding=decimal.ROUND_HALF_UP)
    overtime_rate = yen(rate / hours * multiplier)
    subtotal = yen(days * rate) + yen(overtime * overtime_rate) + yen(steel * steel_rate)
    welfare_amount = yen(subtotal * welfare)
    tax_amount = yen((subtotal + welfare_amount) * tax)
    return {'status': '下書き・未承認', 'overtime_rate': overtime_rate,
            'subtotal': subtotal, 'welfare': welfare_amount, 'tax': tax_amount,
            'total': subtotal + welfare_amount + tax_amount}
