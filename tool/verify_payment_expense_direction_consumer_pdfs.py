"""Check actual common-pipeline exports, rather than a source-text expectation."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/payment-direction-consumer-proof")
for name in ("v2_expense_only", "v2_with_work", "v1_preserved"):
    text = subprocess.check_output(["pdftotext", "-layout", str(root / (name + ".pdf")), "-"], text=True)
    if name == "v2_expense_only":
        assert "経費差引（原額）" in text and "¥-1,000" in text
        assert re.search(r"小計\s+-1,000", text)
        assert "帳票から差し引いた経費の原額内訳です" in text
        assert "帳票に加算した" not in text
    elif name == "v2_with_work":
        assert "20,000" in text and "19,000" in text and "経費差引（原額）" in text
    else:
        assert "別途経費（原額）" in text and "¥1,000" in text
        assert "経費差引（原額）" not in text and "帳票に加算した" in text
    print("PASS", name)
