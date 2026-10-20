import json
import builtins
import symtable
from pathlib import Path
import tempfile
import unittest
import owner_expense_http_rehearsal as candidate

class Tests(unittest.TestCase):
    def setUp(self):
        self.http=candidate.ExpenseHttp('sko-http-db-'+'a'*12,{'auth':'http://172.18.0.2:9999','rest':'http://172.18.0.3:3000'}, {})
    def test_literal_rest_header_only(self):
        data=self.http.config('rest','/rpc/read_expense_document','a.b.c',{},'POST',{'x-sko-payment-source-version':'2'})
        self.assertIn(b'header = "x-sko-payment-source-version: 2"',data)
        self.assertIn(b'Authorization: Bearer a.b.c',data)
        self.assertEqual(data.count(b'x-sko-payment-source-version'),1)
        for service,value in [('auth','2'),('rest','1'),('rest','2\r\nInjected: x')]:
            with self.assertRaises(RuntimeError):self.http.config(service,'/rpc/read_expense_document',None,{},'POST',{'x-sko-payment-source-version':value})
    def test_shared_transport_constraints_survive(self):
        for headers in [{'arbitrary':'x'},{'Accept-Profile':'public\nX: y'}]:
            with self.assertRaises(RuntimeError):self.http.config('rest','/rpc/read_expense_document',None,{},'POST',headers)
        with self.assertRaises(RuntimeError):self.http.config('rest','//outside.invalid',None,{},'POST',None)
        self.assertNotIn(b'x-sko-payment-source-version',self.http.config('rest','/rpc/read_expense_document',None,{},'POST',None))
    def test_runtime_and_bundle_fixed(self):
        bundle=candidate.load_bundle(Path(__file__).parent)
        self.assertIn('conversion.sql',bundle['files'])
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name in ['runtime_manifest.json',*json.loads((Path(__file__).parent/'runtime_manifest.json').read_text())['files']]:
                (root/name).write_bytes((Path(__file__).parent/name).read_bytes())
            (root/'expense_off_rehearsal_bundle.json').write_text('{}')
            with self.assertRaisesRegex(RuntimeError,'runtime_hash_mismatch'):candidate.load_bundle(root)
    def test_conversion_reuses_original_contract_and_issued_actor_context(self):
        bundle=candidate.load_bundle(Path(__file__).parent)
        actor='10000000-0000-0000-0000-000000000001';session='20000000-0000-0000-0000-000000000001'
        sql=candidate.conversion_for_actor(bundle,actor,session)
        self.assertIn("actor:='"+actor+"'::uuid",sql)
        self.assertIn("role::text='admin'",sql);self.assertIn('auth.sessions',sql)
        self.assertIn("'session_id','"+session+"'",sql)
        self.assertNotIn('unique existing owner required',sql)
        for marker in ['identical retry changed result','actual conversion audit differs','conversion changed settlement history or another document','conversion function exposed to a client role']:
            self.assertIn(marker,sql)
        self.assertEqual(sql.count('private.convert_payment_expense_v1_draft('),5) # two calls plus three client ACL signatures
        with self.assertRaises(ValueError):candidate.conversion_for_actor(bundle,"';DROP DATABASE postgres;--",session)
    def test_all_referenced_globals_resolve_in_every_nested_scope(self):
        path=Path(candidate.__file__)
        table=symtable.symtable(path.read_text(),str(path),'exec')
        missing=[]
        def visit(scope):
            for symbol in scope.get_symbols():
                if symbol.is_referenced() and symbol.is_global() and symbol.get_name() not in candidate.__dict__ and not hasattr(builtins,symbol.get_name()):
                    missing.append(scope.get_name()+':'+symbol.get_name())
            for child in scope.get_children():visit(child)
        visit(table)
        self.assertEqual(missing,[])
        self.assertIs(candidate.safe_service_state,candidate.shared.safe_service_state)
        summary=candidate.safe_service_state({'State':{'Status':'running','Running':True,'ExitCode':0},'Config':{'Env':['PASSWORD=never-print']}})
        self.assertNotIn('never-print',str(summary))
    def test_claim_context_and_http_header_are_separate_and_repeatable(self):
        bundle=candidate.load_bundle(Path(__file__).parent)
        sql=candidate.conversion_for_actor(bundle,'10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001')
        # Original conversion scenario has no request.header override; the only
        # adapted claims writer retains the issued session and never switches actor.
        self.assertNotIn('request.headers',sql)
        self.assertEqual(sql.count("set_config('request.jwt.claims'"),1)
        self.assertIn("'session_id','20000000-0000-0000-0000-000000000001'",sql)
        for _ in range(2):
            supported=self.http.config('rest','/rpc/read_expense_document','a.b.c',{},'POST',{'x-sko-payment-source-version':'2'})
            legacy=self.http.config('rest','/rpc/read_expense_document','a.b.c',{},'POST',None)
            self.assertIn(b'x-sko-payment-source-version: 2',supported)
            self.assertNotIn(b'x-sko-payment-source-version',legacy)
    def test_no_http_mutation_or_production_endpoints(self):
        with self.assertRaises(RuntimeError):candidate.expense_rpc(self.http,'convert_payment_expense_v1_draft',None,{},True)
        source=(Path(__file__).parent/'owner_expense_http_rehearsal.py').read_text()
        self.assertNotIn('supabase.co',source);self.assertNotIn("docker','pull",source)
        self.assertIn("for name in reversed(containers):",source)
        self.assertIn("private_conversion_sql_not_http_mutation=True",source)
        self.assertIn("original_restore_changed=False",source.replace("'original_restore_changed':False",'original_restore_changed=False'))

if __name__=='__main__':unittest.main()
