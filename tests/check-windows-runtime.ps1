param([Parameter(Mandatory = $true)][string]$Executable)

$ErrorActionPreference = 'Stop'
$stream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $Executable))
$reader = New-Object IO.BinaryReader($stream)
try {
    function Read-U16([long]$offset) {
        $null = $stream.Seek($offset, [IO.SeekOrigin]::Begin)
        return $reader.ReadUInt16()
    }
    function Read-U32([long]$offset) {
        $null = $stream.Seek($offset, [IO.SeekOrigin]::Begin)
        return $reader.ReadUInt32()
    }
    function Read-AsciiZ([long]$offset) {
        $null = $stream.Seek($offset, [IO.SeekOrigin]::Begin)
        $bytes = New-Object 'System.Collections.Generic.List[byte]'
        for ($i = 0; $i -lt 256; $i++) {
            $byte = $reader.ReadByte()
            if ($byte -eq 0) { return [Text.Encoding]::ASCII.GetString($bytes.ToArray()) }
            $bytes.Add($byte)
        }
        throw 'Nom de bibliothèque PE trop long.'
    }

    if ((Read-U16 0) -ne 0x5a4d) { throw 'Exécutable DOS/PE invalide.' }
    $pe = [long](Read-U32 0x3c)
    if ((Read-U32 $pe) -ne 0x00004550) { throw 'En-tête PE invalide.' }
    $coff = $pe + 4
    $machine = Read-U16 $coff
    if ($machine -notin @(0x8664, 0xaa64)) { throw 'Architecture PE inattendue.' }
    $numberOfSections = Read-U16 ($coff + 2)
    $optionalSize = Read-U16 ($coff + 16)
    $optional = $coff + 20
    if ((Read-U16 $optional) -ne 0x20b) { throw 'En-tête PE32+ attendu.' }
    $numberOfDirectories = Read-U32 ($optional + 108)
    if ($numberOfDirectories -lt 14) { throw 'Tables PE incomplètes.' }
    $sectionStart = $optional + $optionalSize
    $sections = @()
    for ($i = 0; $i -lt $numberOfSections; $i++) {
        $s = $sectionStart + (40 * $i)
        $sections += [pscustomobject]@{
            VirtualSize = [long](Read-U32 ($s + 8))
            VirtualAddress = [long](Read-U32 ($s + 12))
            RawSize = [long](Read-U32 ($s + 16))
            RawOffset = [long](Read-U32 ($s + 20))
        }
    }
    function Resolve-Rva([long]$rva) {
        foreach ($section in $sections) {
            $relative = $rva - $section.VirtualAddress
            if ($relative -ge 0 -and $relative -lt $section.RawSize) {
                return $section.RawOffset + $relative
            }
        }
        throw 'Adresse PE non présente dans les sections du fichier.'
    }
    $dlls = New-Object 'System.Collections.Generic.List[string]'
    $directory = $optional + 112
    $importRva = Read-U32 ($directory + 8)
    if ($importRva -eq 0) { throw 'Table des importations PE absente.' }
    $imports = Resolve-Rva $importRva
    for ($i = 0; $i -lt 4096; $i++) {
        $entry = $imports + (20 * $i)
        $nameRva = Read-U32 ($entry + 12)
        if ($nameRva -eq 0) { break }
        $dlls.Add((Read-AsciiZ (Resolve-Rva $nameRva)))
        if ($i -eq 4095) { throw 'Table des importations PE trop longue.' }
    }
    $delayRva = Read-U32 ($directory + 13 * 8)
    if ($delayRva -ne 0) {
        $delayed = Resolve-Rva $delayRva
        for ($i = 0; $i -lt 4096; $i++) {
            $entry = $delayed + (32 * $i)
            $attributes = Read-U32 $entry
            $nameRva = Read-U32 ($entry + 4)
            if ($nameRva -eq 0) { break }
            if (($attributes -band 1) -eq 0) { throw 'Format de chargement differe PE non pris en charge.' }
            $dlls.Add((Read-AsciiZ (Resolve-Rva $nameRva)))
            if ($i -eq 4095) { throw 'Table des importations différées PE trop longue.' }
        }
    }
    $runtime = @($dlls | Where-Object { $_ -match '^(vcruntime|msvcp|msvcr|concrt|vcomp)[0-9].*\.dll$' })
    if ($runtime.Count -gt 0) { throw "Redistribuable Visual C++ requis : $($runtime -join ', ')." }
    Write-Output 'Aucune dépendance dynamique au redistribuable Visual C++.'
} finally {
    $reader.Dispose()
    $stream.Dispose()
}
