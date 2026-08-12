[CmdletBinding()]
param(
    [string]$ArchivePath,
    [string]$BuildRoot = 'C:\Users\User\Documents\26.2\build',
    [string]$SourceModelPath,
    [string]$SourceTexturePath = 'D:\Users\User\Downloads\assets\minecraft\textures\item\cybernetic_knife.png',
    [string]$LocalTestPackPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manhuang-resource-pack.zip'
}
if ([string]::IsNullOrWhiteSpace($SourceModelPath)) {
    $SourceModelPath = Join-Path 'D:\Users\User\Downloads\assets\minecraft\models\item' ("$([char]0x5315)$([char]0x9996)4.json")
}
if ([string]::IsNullOrWhiteSpace($LocalTestPackPath)) {
    $LocalTestPackPath = Join-Path 'C:\Users\User\curseforge\minecraft\Instances\26.2\resourcepacks' ("$([char]0x883B)$([char]0x8352)$([char]0x9006)$([char]0x5883)-$([char]0x76DC)$([char]0x8CCA)$([char]0x5315)$([char]0x9996)$([char]0x6E2C)$([char]0x8A66)")
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$stageRoot = Join-Path $BuildRoot 'bandit-captain-dagger'
$stageAssetsRoot = Join-Path $stageRoot 'assets\bandit'
$stageItemPath = Join-Path $stageAssetsRoot 'items\bandit_captain_dagger.json'
$stageModelPath = Join-Path $stageAssetsRoot 'models\item\bandit_captain_dagger.json'
$stageTexturePath = Join-Path $stageAssetsRoot 'textures\item\bandit_captain_dagger.png'
$candidateZip = Join-Path $stageRoot 'manhuang-resource-pack.zip'

$requiredEntries = @(
    'assets/bandit/items/bandit_captain_dagger.json',
    'assets/bandit/models/item/bandit_captain_dagger.json',
    'assets/bandit/textures/item/bandit_captain_dagger.png'
)

foreach ($path in @($ArchivePath, $SourceModelPath, $SourceTexturePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required source file is missing: $path"
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stageItemPath), (Split-Path -Parent $stageModelPath), (Split-Path -Parent $stageTexturePath) | Out-Null

$itemDefinition = @'
{
  "model": {
    "type": "minecraft:model",
    "model": "bandit:item/bandit_captain_dagger"
  }
}
'@
[System.IO.File]::WriteAllText($stageItemPath, $itemDefinition, $utf8NoBom)

$sourceModel = [System.IO.File]::ReadAllText($SourceModelPath, [System.Text.Encoding]::UTF8)
$oldTexture = '"item/cybernetic_knife"'
$newTexture = '"bandit:item/bandit_captain_dagger"'
if ([regex]::Matches($sourceModel, [regex]::Escape($oldTexture)).Count -ne 2) {
    throw 'Source model must contain exactly two cybernetic_knife texture references.'
}
$daggerModel = $sourceModel.Replace($oldTexture, $newTexture)
if ([regex]::Matches($daggerModel, [regex]::Escape($newTexture)).Count -ne 2) {
    throw 'Generated model did not contain exactly two dagger texture references.'
}
[System.IO.File]::WriteAllText($stageModelPath, $daggerModel, $utf8NoBom)
Copy-Item -LiteralPath $SourceTexturePath -Destination $stageTexturePath -Force

if (Test-Path -LiteralPath $candidateZip -PathType Leaf) {
    Remove-Item -LiteralPath $candidateZip -Force
}

$sourceArchive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ArchivePath))
$candidateArchive = [System.IO.Compression.ZipFile]::Open($candidateZip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($entry in $sourceArchive.Entries) {
        if ($requiredEntries -contains $entry.FullName) {
            continue
        }
        $destinationEntry = $candidateArchive.CreateEntry($entry.FullName, [System.IO.Compression.CompressionLevel]::Optimal)
        $destinationEntry.LastWriteTime = $entry.LastWriteTime
        $input = $entry.Open()
        $output = $destinationEntry.Open()
        try {
            $input.CopyTo($output)
        } finally {
            $output.Dispose()
            $input.Dispose()
        }
    }

    $generatedFiles = @{
        'assets/bandit/items/bandit_captain_dagger.json' = $stageItemPath
        'assets/bandit/models/item/bandit_captain_dagger.json' = $stageModelPath
        'assets/bandit/textures/item/bandit_captain_dagger.png' = $stageTexturePath
    }
    foreach ($entryName in $requiredEntries) {
        $destinationEntry = $candidateArchive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $input = [System.IO.File]::OpenRead($generatedFiles[$entryName])
        $output = $destinationEntry.Open()
        try {
            $input.CopyTo($output)
        } finally {
            $output.Dispose()
            $input.Dispose()
        }
    }
} finally {
    $candidateArchive.Dispose()
    $sourceArchive.Dispose()
}

New-Item -ItemType Directory -Force -Path $LocalTestPackPath | Out-Null
[System.IO.File]::WriteAllText((Join-Path $LocalTestPackPath 'pack.mcmeta'), @'
{
  "pack": {
    "pack_format": 15,
    "supported_formats": [15, 32767],
    "description": "[manhuang] bandit captain dagger test"
  }
}
'@, $utf8NoBom)
foreach ($entryName in $requiredEntries) {
    $destination = Join-Path $LocalTestPackPath ($entryName -replace '/', '\\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $generatedFiles[$entryName] -Destination $destination -Force
}

Write-Host "BUILD: candidate ZIP created at $candidateZip"
Write-Host "BUILD: local test pack updated at $LocalTestPackPath"
