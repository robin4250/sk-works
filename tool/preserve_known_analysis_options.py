#!/usr/bin/env python3
"""Preserve only the reported generated-directory exclusions before installation."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

PREFIX = b"analyzer:\n  exclude:\n    - build/**\n    - android/**\n    - ios/**\n"


def git(*args):
    return subprocess.check_output(["git", *args], stderr=subprocess.DEVNULL)


def main():
    os.umask(0o077)
    root = Path(git("rev-parse", "--show-toplevel").decode().strip())
    os.chdir(root)
    if git("branch", "--show-current").strip() != b"main":
        raise ValueError("mainブランチで実行してください。")
    status = git("status", "--porcelain=v1", "-z", "--untracked-files=all")
    if not status:
        print("✓ 保存されていないソース変更はありません。")
        return
    if status != b" M analysis_options.yaml\0":
        raise ValueError("既知のanalysis_options変更以外があります。変更を保持して停止しました。")
    source = root / "analysis_options.yaml"
    if source.is_symlink() or not source.is_file():
        raise ValueError("通常のanalysis_options.yamlではありません。停止しました。")
    head = git("rev-parse", "HEAD").strip()
    original = git("show", "HEAD:analysis_options.yaml")
    current = source.read_bytes()
    if current != PREFIX + original:
        raise ValueError("報告済みの先頭5行追加と一致しません。変更を保持して停止しました。")
    backup_root = Path(os.environ.get("SKO_SOURCE_BACKUP_DIR", str(Path.home() / "SKO-source-backups")))
    backup_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup_dir = Path(tempfile.mkdtemp(prefix="analysis-options-", dir=backup_root))
    backup = backup_dir / "analysis_options.yaml"
    with backup.open("xb") as stream:
        stream.write(current)
        stream.flush()
        os.fsync(stream.fileno())
    (backup_dir / "commit.txt").write_bytes(head + b"\n")
    if backup.read_bytes() != current:
        raise ValueError("保存コピーの照合に失敗しました。元ファイルは変更していません。")
    # Reject an edit or branch change made while the copy was being written.
    if (source.is_symlink() or source.read_bytes() != current
            or git("rev-parse", "HEAD").strip() != head
            or git("branch", "--show-current").strip() != b"main"
            or git("status", "--porcelain=v1", "-z", "--untracked-files=all") != status):
        raise ValueError("保存中に作業状態が変わりました。コピーを保持して停止しました。")
    subprocess.run(["git", "restore", "--source=" + head.decode(), "--worktree", "--", "analysis_options.yaml"], check=True)
    if source.read_bytes() != original:
        raise ValueError("復元後の照合に失敗しました。保存コピーを確認してください。")
    print("✓ 既知の5行追加を保存・照合して、Git管理版へ戻しました。")
    print("✓ 保存コピー: " + str(backup))
    print("既存のRelease導入前チェックは引き続き実行してください。")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Never print a git diff, environment values or source content.
        print("✗ " + (str(error) if isinstance(error, ValueError) else "安全な保存処理に失敗しました。元の変更と保存コピーを確認してください。"), file=sys.stderr)
        sys.exit(1)
