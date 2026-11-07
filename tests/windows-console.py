"""Exercise the real executable inside Windows PowerShell 5 and a ConPTY."""
import hashlib
import os
from pathlib import Path
import re
import select
import sys
import tempfile
import time
import urllib.request

from winpty import PtyProcess

ROOT = Path(__file__).resolve().parents[1]
LEGACY = {
    'AMD64': ('amd64', '9a6d916cf825627bab1902b08cfe8ed42555f755e5c531ceb4dec7134eeaac98'),
    'ARM64': ('arm64', '6f5104ff39c2e1fbfcfa26033d823244c154b1d278eca0046f2ce16ef632c4ee'),
}
ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')


def wait_for(process, needle, timeout=35):
    deadline = time.monotonic() + timeout
    output = ''
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.fileobj], [], [], 1)
        if ready:
            try:
                output += process.read(4096)
            except EOFError:
                break
            if needle in ANSI.sub('', output):
                return
        if not process.isalive():
            break
    raise AssertionError(f'Expected {needle!r} in console output: {ANSI.sub("", output)[-2500:]!r}')


def run_interactive(binary, expected_text):
    powershell = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
    process = PtyProcess.spawn([str(powershell), '-NoLogo', '-NoProfile'], dimensions=(30, 120))
    try:
        process.write("Write-Output '__MET_READY__'\r")
        wait_for(process, '__MET_READY__')
        quoted = str(binary).replace("'", "''")
        process.write(f"& '{quoted}'; Write-Output ('__MET_EXIT_' + $LASTEXITCODE + '__')\r")
        wait_for(process, expected_text)
        process.write('\x1b')
        wait_for(process, '__MET_EXIT_0__')
    finally:
        if process.isalive():
            process.write('exit\r')
            time.sleep(0.5)
        process.close(force=True)


def main():
    print('Testing the current executable with Windows PowerShell 5 in ConPTY.', flush=True)
    run_interactive(ROOT / 'target/release/myeasytoolkit.exe', 'vos scripts en un seul endroit')
    native = os.environ.get('PROCESSOR_ARCHITEW6432') or os.environ.get('PROCESSOR_ARCHITECTURE', '')
    if native not in LEGACY:
        raise RuntimeError(f'Unexpected Windows architecture: {native}')
    arch, expected_hash = LEGACY[native]
    name = f'myeasytoolkit-windows-{arch}.exe'
    url = f'https://packages.myeasytoolkit.com/releases/latest/{name}'
    with urllib.request.urlopen(url, timeout=30) as response:
        data = response.read(20 * 1024 * 1024)
    if hashlib.sha256(data).hexdigest() != expected_hash:
        print('The published executable changed; the historical 0.1.0 diagnostic was skipped.', flush=True)
        return
    with tempfile.TemporaryDirectory(prefix='met-published-') as directory:
        published = Path(directory) / name
        published.write_bytes(data)
        try:
            run_interactive(published, 'Adresse du')
        except Exception as error:
            print(f'Published 0.1.0 interactive diagnostic failed: {error}', file=sys.stderr, flush=True)
        else:
            print('Published 0.1.0 displayed its address prompt and exited normally.', flush=True)


if __name__ == '__main__':
    main()
