"""OFF process-bounded observations, never an authenticated privacy receipt.

Linux resource limits contain parser resource use; this is NOT an OS sandbox.
The child retains the parent's OS user/filesystem/network permissions. Host
isolation, trusted snapshot ownership and independent attestation remain required.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import selectors
import signal
import struct
import subprocess
import sys
import tempfile
import threading
import time

MAX_PDF = 50 * 1024 * 1024
MAX_HEADER = 65536
MAX_OUTPUT = 4096
ERROR = "vault_observation_unavailable"
POLICY = "text-pdf-observations-v1"
_ADMISSION = threading.BoundedSemaphore(2)


def _metadata(data, expected_sha256, expected_owner, forbidden_markers):
    if (type(data) is not bytes or not 12 <= len(data) <= MAX_PDF
            or type(expected_sha256) is not str or len(expected_sha256) != 64
            or any(c not in '0123456789abcdef' for c in expected_sha256)
            or hashlib.sha256(data).hexdigest() != expected_sha256
            or type(expected_owner) is not str or not expected_owner.strip()
            or len(expected_owner) > 200
            or type(forbidden_markers) not in (tuple, list)
            or len(forbidden_markers) > 128
            or any(type(x) is not str or not x or len(x) > 200 for x in forbidden_markers)):
        raise ValueError(ERROR)
    return {'expected_sha256': expected_sha256, 'expected_owner': expected_owner,
            'forbidden_markers': list(forbidden_markers), 'byte_length': len(data)}


def _result(raw, expected_sha256):
    def unique(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(ERROR)
            result[key] = value
        return result
    value = json.loads(raw, object_pairs_hook=unique)
    if (type(value) is not dict or set(value) != {
            'candidate_policy', 'pdf_sha256', 'page_count', 'text_sha256'}
            or value['candidate_policy'] != POLICY
            or value['pdf_sha256'] != expected_sha256
            or type(value['page_count']) is not int or not 1 <= value['page_count'] <= 100
            or type(value['text_sha256']) is not str or len(value['text_sha256']) != 64
            or any(c not in '0123456789abcdef' for c in value['text_sha256'])):
        raise ValueError(ERROR)
    return value


def _stop(process):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()  # Reap our child; no detached parser survives return.


def _supervise(source, expected_sha256, timeout_seconds, command):
    """Private fixed-command boundary. Tests inject local child faults here only."""
    process = None
    end = time.monotonic() + timeout_seconds
    try:
        process = subprocess.Popen(command, stdin=source, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, env={'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8'},
            close_fds=True, start_new_session=True)
        output = bytearray()
        with selectors.DefaultSelector() as ready:
            ready.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = end - time.monotonic()
                if remaining <= 0:
                    raise ValueError(ERROR)
                events = ready.select(remaining)
                if not events:
                    raise ValueError(ERROR)
                chunk = os.read(process.stdout.fileno(), MAX_OUTPUT + 1 - len(output))
                if not chunk:
                    break
                output.extend(chunk)
                if len(output) > MAX_OUTPUT:
                    raise ValueError(ERROR)
        remaining = end - time.monotonic()
        if remaining <= 0:
            raise ValueError(ERROR)
        # Observe exit without reaping: keep the PID reserved until group cleanup.
        while True:
            status = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
            if status is not None:
                if status.si_code != os.CLD_EXITED or status.si_status != 0:
                    raise ValueError(ERROR)
                break
            remaining = end - time.monotonic()
            if remaining <= 0:
                raise ValueError(ERROR)
            time.sleep(min(.005, remaining))
        return _result(bytes(output), expected_sha256)
    except Exception:
        raise ValueError(ERROR) from None
    finally:
        if process is not None:
            # Kill the owned process group even if its leader exited; descendant
            # stdout holders must not outlive this request.
            _stop(process)
            if process.stdout is not None:
                process.stdout.close()


def observe_in_worker(data, *, expected_sha256, expected_owner,
                      forbidden_markers=(), timeout_seconds=5, enabled=False):
    """Server-owned OFF adapter. No worker command/path or credential input."""
    admitted = False
    try:
        if enabled is not True or not _ADMISSION.acquire(blocking=False):
            raise ValueError(ERROR)
        admitted = True
        if (sys.platform != 'linux' or type(timeout_seconds) not in (int, float)
                or not math.isfinite(timeout_seconds) or not 0 < timeout_seconds <= 30):
            raise ValueError(ERROR)
        metadata = _metadata(data, expected_sha256, expected_owner, forbidden_markers)
        header = json.dumps(metadata, ensure_ascii=True, separators=(',', ':')).encode()
        if len(header) > MAX_HEADER:
            raise ValueError(ERROR)
        # Unlinked private temporary input; no reusable source path is accepted.
        # The parser deadline starts at spawn; staging filesystem IO is not a
        # hard real-time guarantee and requires bounded host storage/admission.
        with tempfile.TemporaryFile(mode='w+b') as source:
            source.write(struct.pack('>I', len(header)))
            source.write(header)
            source.write(data)
            source.seek(0)
            return _supervise(source, expected_sha256, timeout_seconds,
                [sys.executable, '-I', str(Path(__file__).resolve()), '--bounded-child'])
    except Exception:
        raise ValueError(ERROR) from None
    finally:
        if admitted:
            _ADMISSION.release()


def _child():
    # Set limits before importing the PDF parser or reading the request.
    import resource
    for kind, limit in ((resource.RLIMIT_AS, 512 * 1024 * 1024),
                        (resource.RLIMIT_CPU, 3), (resource.RLIMIT_FSIZE, 0),
                        (resource.RLIMIT_CORE, 0), (resource.RLIMIT_NOFILE, 32)):
        resource.setrlimit(kind, (limit, limit))
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from inspect_pdf_candidate import inspect_candidate
    source = sys.stdin.buffer
    prefix = source.read(4)
    if len(prefix) != 4:
        raise ValueError(ERROR)
    count = struct.unpack('>I', prefix)[0]
    if not 1 <= count <= MAX_HEADER:
        raise ValueError(ERROR)
    header = source.read(count)
    metadata = json.loads(header)
    if type(metadata) is not dict or set(metadata) != {
            'expected_sha256', 'expected_owner', 'forbidden_markers', 'byte_length'}:
        raise ValueError(ERROR)
    size = metadata.pop('byte_length')
    if type(size) is not int or not 12 <= size <= MAX_PDF:
        raise ValueError(ERROR)
    data = source.read(size)
    if len(data) != size or source.read(1):
        raise ValueError(ERROR)
    _metadata(data, metadata['expected_sha256'], metadata['expected_owner'],
              metadata['forbidden_markers'])
    result = inspect_candidate(data, **metadata)
    payload = json.dumps(_result(json.dumps(result), metadata['expected_sha256']),
                         separators=(',', ':')).encode()
    if len(payload) > MAX_OUTPUT:
        raise ValueError(ERROR)
    sys.stdout.buffer.write(payload)


if __name__ == '__main__':
    try:
        if sys.argv[1:] != ['--bounded-child']:
            raise ValueError(ERROR)
        _child()
    except BaseException:
        # Parser exceptions/text/paths never leave the private worker.
        sys.exit(1)
