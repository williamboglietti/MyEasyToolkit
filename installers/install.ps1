$ErrorActionPreference = 'Stop'
$baseUrl = 'https://packages.myeasytoolkit.com/releases/latest'
# A 32-bit PowerShell process on 64-bit Windows reports the native
# architecture through PROCESSOR_ARCHITEW6432.
$nativeArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$arch = switch ($nativeArch) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    default { throw 'Architecture non prise en charge.' }
}
$file = "myeasytoolkit-windows-$arch.exe"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
try {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $binary = Join-Path $tempDir $file
    $checksum = Join-Path $tempDir "$file.sha256"
    Invoke-WebRequest -UseBasicParsing "$baseUrl/$file" -OutFile $binary
    Invoke-WebRequest -UseBasicParsing "$baseUrl/$file.sha256" -OutFile $checksum
    $expected = ((Get-Content -Raw $checksum).Trim() -split '\s+')[0]
    if ($expected -notmatch '^[a-fA-F0-9]{64}$') { throw 'Somme de contrôle invalide.' }
    if ((Get-FileHash -Algorithm SHA256 $binary).Hash -ne $expected) { throw 'La somme de contrôle ne correspond pas.' }
    $binDir = Join-Path $env:LOCALAPPDATA 'MyEasyToolkit\bin'
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    Copy-Item -Force $binary (Join-Path $binDir 'myeasytoolkit.exe')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $binDir) {
        [Environment]::SetEnvironmentVariable('Path', (($userPath, $binDir | Where-Object { $_ }) -join ';'), 'User')
    }
    if (($env:Path -split ';') -notcontains $binDir) { $env:Path += ";$binDir" }
    Write-Host 'Installation terminée. Lancez : myeasytoolkit'
} finally {
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
}
