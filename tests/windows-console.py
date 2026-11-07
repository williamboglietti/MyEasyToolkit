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
PUBLISHED = {
    'AMD64': ('amd64', 'a47e3518c96fcde44f08d571076d48822e82116db2dec8bb1c65cab088e9838b'),
    'ARM64': ('arm64', 'f61efde2152118ac588786ebefb3f6a83b28dd59a6c0ace6186a43947525b7c4'),
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
            raise AssertionError('The installed executable did not match the published 0.1.1 build.')
        process.write("$v = myeasytoolkit --version; if ($v -eq 'myeasytoolkit 0.1.1' -and $LASTEXITCODE -eq 0) "
                      "{ Write-Output ('__MET_VERSION_' + 'OK__') }\r")
        wait_for(process, '__MET_VERSION_OK__')
        process.write("myeasytoolkit; Write-Output ('__MET_EXIT_' + $LASTEXITCODE + '__')\r")
        wait_for(process, 'vos scripts en un seul endroit')
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
    if native not in PUBLISHED:
        raise RuntimeError(f'Unexpected Windows architecture: {native}')
    arch, expected_hash = PUBLISHED[native]
    name = f'myeasytoolkit-windows-{arch}.exe'
    url = f'https://packages.myeasytoolkit.com/releases/latest/{name}'
    with urllib.request.urlopen(url, timeout=30) as response:
        data = response.read(20 * 1024 * 1024)
    if hashlib.sha256(data).hexdigest() != expected_hash:
        raise AssertionError('The public executable differs from the approved hotfix.')
    # Exercise installation under a Windows profile path containing spaces.
    with tempfile.TemporaryDirectory(prefix='met published ') as directory:
        published = Path(directory) / name
        published.write_bytes(data)
        run_interactive(published, 'vos scripts en un seul endroit')
        print('Published 0.1.1 opened interactively and exited normally.', flush=True)
        with urllib.request.urlopen('https://myeasytoolkit.com/install.ps1', timeout=30) as response:
            installer_data = response.read(1024 * 1024)
        if hashlib.sha256(installer_data).hexdigest() != INSTALLER_SHA256:
            raise AssertionError('The public installer changed since the deployment check.')
        installer = Path(directory) / 'install.ps1'
        installer.write_bytes(installer_data)
        run_published_installer(installer, expected_hash, directory)
        print('Public installer and command-name launch succeeded in PowerShell 5.', flush=True)



if __name__ == '__main__':
    main()
