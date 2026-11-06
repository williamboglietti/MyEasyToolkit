$ErrorActionPreference = 'Stop'
$workDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
New-Item -ItemType Directory $workDir | Out-Null
$previousAppData = $env:LOCALAPPDATA
$previousPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$previousProcessPath = $env:Path
try {
    $env:LOCALAPPDATA = Join-Path $workDir 'appdata'
    $script:fixture = Join-Path $workDir 'fixture'
    New-Item -ItemType Directory $script:fixture | Out-Null
    $architecture = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
        'X64' { 'amd64' }
        'Arm64' { 'arm64' }
        default { throw 'Unsupported test architecture' }
    }
    $name = "myeasytoolkit-windows-$architecture.exe"
    $fixtureBinary = Join-Path $script:fixture $name
    [IO.File]::WriteAllText($fixtureBinary, 'fixture executable')
    (Get-FileHash -Algorithm SHA256 $fixtureBinary).Hash | Set-Content (Join-Path $script:fixture "$name.sha256")
    function Invoke-WebRequest {
        param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile)
        Copy-Item (Join-Path $script:fixture ([IO.Path]::GetFileName($Uri))) $OutFile
    }
    & "$PSScriptRoot/../installers/install.ps1"
    $installed = Join-Path $env:LOCALAPPDATA 'MyEasyToolkit/bin/myeasytoolkit.exe'
    if (!(Test-Path $installed)) { throw 'The executable was not installed.' }
    'wrong checksum' | Set-Content (Join-Path $script:fixture "$name.sha256")
    $rejected = $false
    try { & "$PSScriptRoot/../installers/install.ps1" } catch { $rejected = $true }
    if (!$rejected) { throw 'An invalid checksum was accepted.' }
} finally {
    [Environment]::SetEnvironmentVariable('Path', $previousPath, 'User')
    $env:Path = $previousProcessPath
    $env:LOCALAPPDATA = $previousAppData
    Remove-Item -Recurse -Force $workDir
}
