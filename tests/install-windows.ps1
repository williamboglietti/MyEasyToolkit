$ErrorActionPreference = 'Stop'
$workDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory $workDir | Out-Null
$previousAppData = $env:LOCALAPPDATA
$previousPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$previousProcessPath = $env:Path
$previousArchitecture = $env:PROCESSOR_ARCHITECTURE
$previousNativeArchitecture = $env:PROCESSOR_ARCHITEW6432
try {
    $env:LOCALAPPDATA = Join-Path $workDir 'appdata'
    $env:MET_TEST_FIXTURE = Join-Path $workDir 'fixture'
    New-Item -ItemType Directory $env:MET_TEST_FIXTURE | Out-Null
    foreach ($architecture in @('amd64', 'arm64')) {
        $name = "myeasytoolkit-windows-$architecture.exe"
        $fixtureBinary = Join-Path $env:MET_TEST_FIXTURE $name
        [IO.File]::WriteAllText($fixtureBinary, "fixture $architecture")
        (Get-FileHash -Algorithm SHA256 $fixtureBinary).Hash | Set-Content (Join-Path $env:MET_TEST_FIXTURE "$name.sha256")
    }
    function Invoke-WebRequest {
        param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile)
        Copy-Item (Join-Path $env:MET_TEST_FIXTURE ([IO.Path]::GetFileName($Uri))) $OutFile
    }
    $installer = "$PSScriptRoot/../installers/install.ps1"
    $installed = Join-Path $env:LOCALAPPDATA 'MyEasyToolkit/bin/myeasytoolkit.exe'
    $cases = @(
        @{ Process = 'AMD64'; Native = $null; Expected = 'amd64' },
        @{ Process = 'ARM64'; Native = $null; Expected = 'arm64' },
        @{ Process = 'x86'; Native = 'AMD64'; Expected = 'amd64' },
        @{ Process = 'x86'; Native = 'ARM64'; Expected = 'arm64' }
    )
    foreach ($case in $cases) {
        $env:PROCESSOR_ARCHITECTURE = $case.Process
        $env:PROCESSOR_ARCHITEW6432 = $case.Native
        # Match the public irm ... | iex command, without making a network request.
        Get-Content -Raw $installer | Invoke-Expression
        if ((Get-Content -Raw $installed) -ne "fixture $($case.Expected)") {
            throw "Incorrect binary for $($case.Process) / $($case.Native)"
        }
    }
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $env:PROCESSOR_ARCHITEW6432 = $null
    'wrong checksum' | Set-Content (Join-Path $env:MET_TEST_FIXTURE 'myeasytoolkit-windows-amd64.exe.sha256')
    $rejected = $false
    try { Get-Content -Raw $installer | Invoke-Expression } catch { $rejected = $true }
    if (!$rejected) { throw 'An invalid checksum was accepted.' }
    $env:PROCESSOR_ARCHITECTURE = 'x86'
    $rejected = $false
    try { Get-Content -Raw $installer | Invoke-Expression } catch {
        if ($_.Exception.Message -notmatch 'Architecture non prise en charge') { throw }
        $rejected = $true
    }
    if (!$rejected) { throw 'An unsupported architecture was accepted.' }
} finally {
    [Environment]::SetEnvironmentVariable('Path', $previousPath, 'User')
    $env:Path = $previousProcessPath
    $env:LOCALAPPDATA = $previousAppData
    $env:PROCESSOR_ARCHITECTURE = $previousArchitecture
    $env:PROCESSOR_ARCHITEW6432 = $previousNativeArchitecture
    Remove-Item Env:MET_TEST_FIXTURE -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $workDir
}

# La CI construit le binaire avant ce test. Vérifier ses importations PE évite
# de masquer une dépendance au redistribuable préinstallé sur les runners.
$release = Join-Path $PSScriptRoot '../target/release/myeasytoolkit.exe'
if (Test-Path $release) {
    & "$PSScriptRoot/check-windows-runtime.ps1" -Executable $release
    # Un faux import MSVCR doit être détecté, même sur un runner ayant déjà le runtime.
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path $release))
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    # Le nom peut également apparaître dans des chaînes de code, avant la table
    # d'importation. Remplacer toutes les occurrences de même longueur garantit
    # que le nom référencé par la table PE fait partie de la fixture modifiée.
    $fakeImport = [Text.Encoding]::ASCII.GetBytes('MSVCR120.dll')
    $offset = $text.IndexOf('KERNEL32.dll', [StringComparison]::OrdinalIgnoreCase)
    if ($offset -lt 0) { throw 'Import système KERNEL32.dll introuvable dans le binaire de test.' }
    while ($offset -ge 0) {
        [Array]::Copy($fakeImport, 0, $bytes, $offset, $fakeImport.Length)
        $offset = $text.IndexOf('KERNEL32.dll', $offset + $fakeImport.Length, [StringComparison]::OrdinalIgnoreCase)
    }
    $fakePe = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    try {
        [IO.File]::WriteAllBytes($fakePe, $bytes)
        $rejected = $false
        try { & "$PSScriptRoot/check-windows-runtime.ps1" -Executable $fakePe } catch { $rejected = $true }
        if (!$rejected) { throw 'Un import dynamique MSVCR aurait dû être refusé.' }
    } finally {
        Remove-Item -Force $fakePe -ErrorAction SilentlyContinue
    }
} elseif ($env:GITHUB_ACTIONS -eq 'true') {
    throw 'Binaire Windows de publication introuvable pour le contrôle PE.'
}
