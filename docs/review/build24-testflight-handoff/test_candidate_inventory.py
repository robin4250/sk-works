import ast, json, pathlib, re, tempfile, types, unittest

source = pathlib.Path(__file__).with_name("testflight_private_candidate.py").read_text()
tree = ast.parse(source)
nodes = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in {"safe_directory", "read_record", "reject_previous"}]
class Stub:
    @staticmethod
    def require(condition, message):
        if not condition: raise RuntimeError(message)
env = {"Path": pathlib.Path, "json": json, "re": re, "r31": Stub()}
exec(compile(ast.Module(body=nodes, type_ignores=[]), "<candidate>", "exec"), env)
class TestInventory(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def entry(self, number, sha="a"*40, finish=True):
        stage = self.root / ("tf-candidate-" + str(len(list(self.root.iterdir()))))
        stage.mkdir()
        (stage/"started-private.json").write_text(json.dumps({"build_number":number,"sha":sha}))
        if finish: (stage/"complete-private.json").write_text("{}")
    def check(self, sha="b"*40, number="24"):
        env["reject_previous"](self.root, sha, number)
    def test_previous_number_allowed(self):
        self.entry("23"); self.check()
    def test_same_number_other_commit_rejected(self):
        self.entry("24")
        with self.assertRaises(RuntimeError): self.check()
    def test_later_number_rejected(self):
        self.entry("25")
        with self.assertRaises(RuntimeError): self.check()
    def test_incomplete_rejected(self):
        self.entry("23",finish=False)
        with self.assertRaises(RuntimeError): self.check()
    def test_invalid_number_rejected(self):
        self.entry("01")
        with self.assertRaises(RuntimeError): self.check()
if __name__ == "__main__": unittest.main()
