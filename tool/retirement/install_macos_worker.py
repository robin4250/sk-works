"""Install the approved broker worker as a login LaunchAgent."""
import argparse
import os
import plistlib
import shutil
import subprocess
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

LABEL = "jp.sko.retirement-renderer"

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--broker", required=True)
    parser.add_argument("--renderer", type=Path, required=True)
    parser.add_argument("--node", type=Path, default=Path("/usr/local/bin/node"))
    args = parser.parse_args()
    broker = urlsplit(args.broker)
    if (broker.scheme != "https" or not broker.hostname or broker.username
            or broker.password or broker.path not in ("", "/", "/functions/v1/retirement-render-broker") or broker.query or broker.fragment):
        parser.error("The broker must be an HTTPS origin.")
    renderer = args.renderer.resolve(strict=True)
    node = args.node.resolve(strict=True)
    if not os.access(renderer, os.X_OK) or not os.access(node, os.X_OK):
        parser.error("The renderer and Node must be executable.")
    worker = (Path(__file__).resolve().parents[2] / "docs" / "review"
              / "retirement-vault-workflow" / "macos_broker_worker.mjs")
    if not worker.is_file():
        parser.error("The worker script is missing.")
    token = subprocess.check_output(
        ["/usr/bin/security", "find-generic-password", "-w", "-s", LABEL],
        text=True, timeout=5, stderr=subprocess.DEVNULL,
    ).strip()
    origin = f"https://{broker.netloc}{broker.path.rstrip('/')}"
    with build_opener(NoRedirect).open(
            Request(origin + "/render/health", headers={"Authorization": "Bearer " + token}),
            timeout=10) as response:
        if response.status != 204:
            parser.error("The broker did not confirm the worker credential.")
    del token

    agents = Path.home() / "Library" / "LaunchAgents"
    agents.mkdir(mode=0o700, exist_ok=True)
    destination = agents / (LABEL + ".plist")
    service = f"gui/{os.getuid()}"
    if destination.exists():
        parser.error("An existing renderer is installed. Remove it before installing a replacement.")
    support = Path.home() / "Library" / "Application Support" / "SKO" / "RetirementRenderer"
    spool = support / "PrivateSpool"
    runtime = support / "Worker"
    runtime.mkdir(parents=True,mode=0o700,exist_ok=True)
    runtime.chmod(0o700)
    for name in ("macos_broker_worker.mjs","macos_job_runner.mjs","macos_renderer.mjs","renderer_files.mjs"):
        shutil.copyfile(worker.with_name(name),runtime/name)
        (runtime/name).chmod(0o600)
    worker = runtime / worker.name
    spool.mkdir(parents=True, mode=0o700, exist_ok=True)
    spool.chmod(0o700)
    values = {
        "Label": LABEL,
        "ProgramArguments": ["/usr/bin/caffeinate", "-is", str(node), str(worker)],
        "EnvironmentVariables": {
            "SKO_RETIREMENT_BROKER": origin,
            "SKO_RETIREMENT_RENDERER": str(renderer),
            "SKO_RETIREMENT_PRIVATE_SPOOL": str(spool),
        },
        "RunAtLoad": True,
        "KeepAlive": True,
        "ThrottleInterval": 10,
    }
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        plistlib.dump(values, f)
    try:
        subprocess.run(["/bin/launchctl", "bootstrap", service, str(destination)], check=True)
    except Exception:
        destination.unlink()
        raise

if __name__ == "__main__":
    main()
