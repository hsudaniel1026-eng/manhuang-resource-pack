[CmdletBinding()]
param(
    [string]$ArchivePath,
    [string]$LocalTestPackPath,
    [string]$BuildRoot = 'C:\Users\User\Documents\26.2\build'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manhuang-resource-pack.zip'
}
if ([string]::IsNullOrWhiteSpace($LocalTestPackPath)) {
    $LocalTestPackPath = Join-Path 'C:\Users\User\curseforge\minecraft\Instances\26.2\resourcepacks' ("$([char]0x883B)$([char]0x8352)$([char]0x9006)$([char]0x5883)-$([char]0x76DC)$([char]0x8CCA)$([char]0x982D)$([char]0x76EE)$([char]0x6750)$([char]0x8CEA)$([char]0x6E2C)$([char]0x8A66)")
}

$validator = Join-Path $PSScriptRoot 'Test-BanditCaptainDaggerPack.ps1'
$fixtureRoot = Join-Path $BuildRoot 'bandit-captain-dagger\negative-tests'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) { throw "Validator is missing: $validator" }
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw "Archive is missing: $ArchivePath" }
if (-not (Test-Path -LiteralPath $LocalTestPackPath -PathType Container)) { throw "Local test pack is missing: $LocalTestPackPath" }

if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null

function Invoke-ExpectedFailure {
    param([string]$Name, [scriptblock]$Action)

    try {
        & $Action
    } catch {
        if ($_.Exception.Message -like 'FAIL: Bandit captain dagger resource-pack validation found*') {
            Write-Host "PASS: negative test rejected $Name"
            return
        }
        throw
    }
    throw "Negative test unexpectedly passed: $Name"
}

function Copy-LocalFixture {
    param([string]$Name)

    $destination = Join-Path $fixtureRoot $Name
    Copy-Item -LiteralPath $LocalTestPackPath -Destination $destination -Recurse -Force
    return $destination
}

$oldFormatPack = Copy-LocalFixture 'old-format'
[System.IO.File]::WriteAllText((Join-Path $oldFormatPack 'pack.mcmeta'), @'
{
  "pack": {
    "pack_format": 15,
    "supported_formats": [15, 32767],
    "description": "deliberately old format"
  }
}
'@, $utf8NoBom)
Invoke-ExpectedFailure 'obsolete pack.mcmeta format' {
    & $validator -ArchivePath $ArchivePath -LocalTestPackPath $oldFormatPack
}

$stringVersionPack = Copy-LocalFixture 'string-version'
[System.IO.File]::WriteAllText((Join-Path $stringVersionPack 'pack.mcmeta'), @'
{
  "pack": {
    "min_format": ["88", "0"],
    "max_format": ["88", "0"],
    "description": "deliberately string version"
  }
}
'@, $utf8NoBom)
Invoke-ExpectedFailure 'string full-version elements' {
    & $validator -ArchivePath $ArchivePath -LocalTestPackPath $stringVersionPack
}

$decimalVersionPack = Copy-LocalFixture 'decimal-version'
[System.IO.File]::WriteAllText((Join-Path $decimalVersionPack 'pack.mcmeta'), @'
{
  "pack": {
    "min_format": [88.4, 0.4],
    "max_format": [88.4, 0.4],
    "description": "deliberately decimal version"
  }
}
'@, $utf8NoBom)
Invoke-ExpectedFailure 'decimal full-version elements' {
    & $validator -ArchivePath $ArchivePath -LocalTestPackPath $decimalVersionPack
}

$obsoleteMetadataZip = Join-Path $fixtureRoot 'obsolete-zip-metadata.zip'
Copy-Item -LiteralPath $ArchivePath -Destination $obsoleteMetadataZip -Force
$archive = [System.IO.Compression.ZipFile]::Open($obsoleteMetadataZip, [System.IO.Compression.ZipArchiveMode]::Update)
try {
    $existingMetadata = $archive.GetEntry('pack.mcmeta')
    if ($null -eq $existingMetadata) {
        throw 'Fixture archive is missing pack.mcmeta'
    }
    $existingMetadata.Delete()
    $replacementMetadata = $archive.CreateEntry('pack.mcmeta')
    $writer = [System.IO.StreamWriter]::new($replacementMetadata.Open(), $utf8NoBom)
    try {
        $writer.Write(@'
{
  "pack": {
    "pack_format": 15,
    "supported_formats": [15, 32767],
    "description": "deliberately obsolete ZIP metadata"
  }
}
'@)
    } finally {
        $writer.Dispose()
    }
} finally {
    $archive.Dispose()
}
Invoke-ExpectedFailure 'obsolete ZIP pack.mcmeta format' {
    & $validator -ArchivePath $obsoleteMetadataZip -LocalTestPackPath $LocalTestPackPath
}

$duplicateZip = Join-Path $fixtureRoot 'duplicate-entry.zip'
Copy-Item -LiteralPath $ArchivePath -Destination $duplicateZip -Force
$archive = [System.IO.Compression.ZipFile]::Open($duplicateZip, [System.IO.Compression.ZipArchiveMode]::Update)
try {
    $duplicate = $archive.CreateEntry('assets/bandit/items/bandit_captain_dagger.json')
    $writer = [System.IO.StreamWriter]::new($duplicate.Open(), $utf8NoBom)
    try { $writer.Write('{}') } finally { $writer.Dispose() }
} finally {
    $archive.Dispose()
}
Invoke-ExpectedFailure 'duplicate ZIP entry' {
    & $validator -ArchivePath $duplicateZip -LocalTestPackPath $LocalTestPackPath
}

$corruptLocalPack = Copy-LocalFixture 'corrupt-local-png'
$corruptPng = Join-Path $corruptLocalPack 'assets\bandit\textures\item\bandit_captain_dagger.png'
$pngBytes = [System.IO.File]::ReadAllBytes($corruptPng)
$pngBytes[0] = $pngBytes[0] -bxor 0xFF
[System.IO.File]::WriteAllBytes($corruptPng, $pngBytes)
Invoke-ExpectedFailure 'local PNG mismatch' {
    & $validator -ArchivePath $ArchivePath -LocalTestPackPath $corruptLocalPack
}

Write-Host 'PASS: all negative resource-pack validation tests were rejected as expected.'
