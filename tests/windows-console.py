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
INSTALLER_SHA256 = 'ea690607d10a412c9f2bf0f4028f21230fbf6e4bf0eb928cea4b8bd55d4a3f25'
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
            # ConPTY can render spacing with cursor moves instead of literal spaces.
            if ''.join(needle.split()) in ''.join(ANSI.sub('', output).split()):
                return
        if not process.isalive():
            break
    raise AssertionError(f'Expected {needle!r} in console output: {ANSI.sub("", output)[-2500:]!r}')


def run_interactive(binary, expected_text):
    powershell = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
    process = PtyProcess.spawn([str(powershell), '-NoLogo', '-NoProfile'], dimensions=(30, 120))
    try:
        process.write("Write-Output ('__MET_PS_' + $PSVersionTable.PSVersion.Major + '__')\r")
        wait_for(process, '__MET_PS_5__')
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


def run_published_installer(installer, expected_hash, directory):
    """Install into an isolated runner profile and launch by command name."""
    powershell = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
    env = dict(os.environ)
    env['LOCALAPPDATA'] = str(Path(directory) / 'appdata')
    Path(env['LOCALAPPDATA']).mkdir()
    # A PS7-hosted runner may pass a PSModulePath without Windows PowerShell's
    # built-in modules. Restore the default 5.1 system location for this test.
    system_modules = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/Modules'
    env['PSMODULEPATH'] = str(system_modules) + os.pathsep + env.get('PSMODULEPATH', '')
    process = PtyProcess.spawn([str(powershell), '-NoLogo', '-NoProfile'],
                               cwd=directory, env=env, dimensions=(30, 120))
    try:
        process.write("Write-Output ('__MET_PS_' + $PSVersionTable.PSVersion.Major + '__')\r")
        wait_for(process, '__MET_PS_5__')
        process.write("if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) { "
                      "Write-Output ('__MET_HASH_' + 'READY__') }\r")
        wait_for(process, '__MET_HASH_READY__')
        quoted = str(installer).replace("'", "''")
        process.write(f"Get-Content -Raw -LiteralPath '{quoted}' | Invoke-Expression; "
                      "Write-Output ('__MET_INSTALL_' + 'DONE__')\r")
        wait_for(process, '__MET_INSTALL_DONE__', timeout=60)
        installed = Path(env['LOCALAPPDATA']) / 'MyEasyToolkit/bin/myeasytoolkit.exe'
        if hashlib.sha256(installed.read_bytes()).hexdigest() != expected_hash:
            raise AssertionError('The installed executable did not match the published 0.1.0 build.')
        process.write("$v = myeasytoolkit --version; if ($v -eq 'myeasytoolkit 0.1.0' -and $LASTEXITCODE -eq 0) "
                      "{ Write-Output ('__MET_VERSION_' + 'OK__') }\r")
        wait_for(process, '__MET_VERSION_OK__')
        process.write("myeasytoolkit; Write-Output ('__MET_EXIT_' + $LASTEXITCODE + '__')\r")
        wait_for(process, 'Adresse du')
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
    # Exercise installation under a Windows profile path containing spaces.
    with tempfile.TemporaryDirectory(prefix='met published ') as directory:
        published = Path(directory) / name
        published.write_bytes(data)
        try:
            run_interactive(published, 'Adresse du')
        except Exception as error:
            print(f'Published 0.1.0 interactive diagnostic failed: {error}', file=sys.stderr, flush=True)
        else:
            print('Published 0.1.0 displayed its address prompt and exited normally.', flush=True)
        with urllib.request.urlopen('https://myeasytoolkit.com/install.ps1', timeout=30) as response:
            installer_data = response.read(1024 * 1024)
        if hashlib.sha256(installer_data).hexdigest() != INSTALLER_SHA256:
            print('The public installer changed; its end-to-end diagnostic was skipped.', flush=True)
            return
        installer = Path(directory) / 'install.ps1'
        installer.write_bytes(installer_data)
        try:
            run_published_installer(installer, expected_hash, directory)
        except Exception as error:
            print(f'Public installer diagnostic failed: {error}', file=sys.stderr, flush=True)
        else:
            print('Public installer and command-name launch succeeded in PowerShell 5.', flush=True)


if __name__ == '__main__':
    main()
