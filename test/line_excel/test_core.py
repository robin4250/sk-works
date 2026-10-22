import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import contextlib
import io

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tool' / 'line_excel'))
from core import D, SourceStore, invoice_preview, parse, ranking, reconcile
from sync import Client
import sync

GID = '00000000-0000-4000-8000-000000000001'
ACTOR = '00000000-0000-4000-8000-000000000002'


class CoreTest(unittest.TestCase):
    def test_explicit_id_resolves_different_sko_display_name(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(sync, 'Client') as factory:
                client = factory.return_value
                client.groups.return_value = [{'group_id': GID, 'name': 'SKO側の別名'}]
                client.messages.return_value = []
                args = ['sync.py', '--url', 'https://example.supabase.co', '--group', 'LINE側の名前', '--group-id', GID, '--output', directory]
                with patch.object(sys, 'argv', args), contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(sync.main(), 0)
                client.groups.assert_called_once_with('')
                self.assertEqual(client.messages.call_args.args[0], GID)

    def parse(self, text):
        return parse(text, ['三上', '三嶋'], ['東京海上'])

    def test_separate_workers(self):
        rows = self.parse('東京海上三上定時三嶋残業1')['rows']
        self.assertEqual([(r['worker'], r['regular'], r['overtime']) for r in rows], [('三上', True, None), ('三嶋', False, D(1))])
        self.assertTrue(all(not r['issues'] for r in rows))

    def test_units(self):
        for text, hours in [('1', '1'), ('2h', '2'), ('1時間', '1'), ('1H', '1'), ('30分', '0.5'), ('３０分', '0.5')]:
            with self.subTest(text=text):
                self.assertEqual(self.parse('東京海上三上残業' + text)['rows'][0]['overtime'], D(hours))

    def test_shared_regular(self):
        rows = self.parse('東京海上三上三嶋定時')['rows']
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(r['regular'] and not r['issues'] for r in rows))

    def test_ambiguous_shared_quantity(self):
        rows = self.parse('東京海上三上三嶋残業2H鉄骨1')['rows']
        self.assertTrue(all(r['status'] == '要確認' and r['overtime'] is None and not r['allowances'] for r in rows))

    def test_person_allowance(self):
        row = self.parse('東京海上三上残業2H鉄骨1')['rows'][0]
        self.assertEqual(row['allowances'], {'鉄骨': D(1)})
        self.assertEqual(row['overtime'], D(2))

    def test_unknown_and_duplicate(self):
        for text in ['東京海上三上残業', '東京海上三上残業1残業2', '東京海上不明三上定時', '東京海上三上定時残業1']:
            self.assertEqual(self.parse(text)['rows'][0]['status'], '要確認')

    def test_ranking(self):
        self.assertEqual(dict(ranking([self.parse('東京海上三上定時三嶋定時')]))['定時'], 2)

    def test_replay_and_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            store = SourceStore(Path(directory) / 'sources.db')
            original = {'id': 'message', 'body': '=1+2'}
            self.assertEqual(store.import_messages(GID, [original])['added'], 1)
            self.assertEqual(store.import_messages(GID, [original])['added'], 0)
            self.assertEqual(store.import_messages(GID, [{**original, 'body': '訂正'}])['conflicts'], 1)
            self.assertEqual(store.db.execute('select count(*) from sources').fetchone()[0], 2)
            self.assertIn('=1+2', store.db.execute('select payload from sources order by rowid').fetchone()[0])
            with self.assertRaises(ValueError):
                store.import_messages(GID, [{'id': 'another'}, {'id': ''}])
            self.assertEqual(store.db.execute('select count(*) from sources').fetchone()[0], 2)
            store.db.close()

    def test_cross_source_overlap(self):
        row = {'date': '2026-10-15', 'site': 'S', 'worker': 'W', 'source_id': 'image1', 'source_kind': 'image'}
        result = reconcile([row, row, {**row, 'source_kind': 'line', 'source_id': 'message1'}])
        self.assertEqual(len(result), 2)
        self.assertTrue(all(r['status'] == '要確認' and '重複候補' in r['reason'] for r in result))

    def test_invoice(self):
        preview = invoice_preview('1', '2', '1')
        self.assertEqual(preview['overtime_rate'], D(5125))
        self.assertEqual(preview['welfare'], D('6908'))
        self.assertEqual(preview['tax'], D('5296'))
        self.assertEqual(preview['total'], D('58254'))
        self.assertEqual(invoice_preview('1', '0', '0', day_rate='40000')['subtotal'], D(40000))
        for kwargs in [{'hours': '0'}, {'tax': 'NaN'}, {'day_rate': '-1'}]:
            with self.assertRaises(ValueError):
                invoice_preview(1, 0, 0, **kwargs)

    def test_sync_contract_and_short_pages(self):
        calls = []
        def transport(path, params, body):
            calls.append((path, params, body))
            if path == '/auth/v1/user':
                return {'id': ACTOR}
            if 'rpc/' in path:
                return [{'group_id': GID, 'name': '現場'}, {'group_id': ACTOR, 'name': '現場'}]
            offset = dict(params)['offset']
            return [{'id': str(offset)}] if offset < 2 else []
        client = Client('https://example.supabase.co', 'publishable', 'user-token', transport)
        self.assertEqual(len(client.groups('現場')), 2)
        self.assertEqual(len(client.messages(GID, '2026-10-16', '2026-10-19')), 2)
        params = [c[1] for c in calls if c[0].endswith('chat_messages')][0]
        self.assertEqual(dict(params)['origin'], 'eq.line')
        self.assertEqual([v for k, v in params if k == 'sent_at'], ['gte.2026-10-16T00:00:00+09:00', 'lt.2026-10-20T00:00:00+09:00'])

    def test_reject_changed_actor_and_secret(self):
        actors = iter([ACTOR, GID])
        client = Client('https://example.supabase.co', 'publishable', 'token', lambda p, q, b: {'id': next(actors)} if p.endswith('user') else [])
        with self.assertRaises(ValueError):
            client.messages(GID, '2026-10-16', '2026-10-19')
        for url in ['http://example.com', 'https://user:pass@example.com', 'https://example.com/path']:
            with self.assertRaises(ValueError):
                Client(url, 'key', 'token')
        with self.assertRaises(ValueError):
            Client('https://example.com', 'sb_secret_x', 'token')


if __name__ == '__main__':
    unittest.main()
