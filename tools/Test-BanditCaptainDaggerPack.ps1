[CmdletBinding()]
param(
    [string]$ArchivePath,
    [string]$SourceModelPath,
    [string]$SourceTexturePath = 'D:\Users\User\Downloads\assets\minecraft\textures\item\cybernetic_knife.png',
    [string]$LocalTestPackPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path $PSScriptRoot '..\manhuang-resource-pack.zip'
}
if ([string]::IsNullOrWhiteSpace($SourceModelPath)) {
    $SourceModelPath = Join-Path 'D:\Users\User\Downloads\assets\minecraft\models\item' ("$([char]0x5315)$([char]0x9996)4.json")
}
if ([string]::IsNullOrWhiteSpace($LocalTestPackPath)) {
    $LocalTestPackPath = Join-Path 'C:\Users\User\curseforge\minecraft\Instances\26.2\resourcepacks' ("$([char]0x883B)$([char]0x8352)$([char]0x9006)$([char]0x5883)-$([char]0x76DC)$([char]0x8CCA)$([char]0x5315)$([char]0x9996)$([char]0x6E2C)$([char]0x8A66)")
}

$requiredEntries = @(
    'assets/bandit/items/bandit_captain_dagger.json',
    'assets/bandit/models/item/bandit_captain_dagger.json',
    'assets/bandit/textures/item/bandit_captain_dagger.png'
)

$baselineHashes = @{
    'assets/bandit/items/bandit_dagger.json' = 'b59bf2e9fe26646fe162cc9dd195508e39d854107587d26cd5112b1840f99cd8'
    'assets/bandit/models/item/bandit_dagger.json' = '29b6a56f97a9eb7c86ccfc90f057e3121db2bc1b32f7d0f290fbfde562753797'
    'assets/bandit/items/abominable_scythe.json' = '306d9de403a8cea89baf5c10bc69b2f866aa8a257e982907a2f24111f12f7288'
    'assets/bandit/models/item/abominable_scythe.json' = '7efb0a5617969fae18a206b2c8b0c9de2b2a01658d050e0d95e7c5ecf3ff9cd8'
}

function Get-EntryBytes {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)

    $stream = $Entry.Open()
    try {
        $memory = [System.IO.MemoryStream]::new()
        try {
            $stream.CopyTo($memory)
            return $memory.ToArray()
        } finally {
            $memory.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Get-BytesHash {
    param([byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Add-Failure {
    param([string]$Message)

    $script:failures.Add($Message)
}

$failures = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    Add-Failure "Archive is missing: $ArchivePath"
} else {
    $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ArchivePath))
    try {
        $entries = @{}
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match '\\') {
                Add-Failure "ZIP entry uses a backslash: $($entry.FullName)"
            }
            if ($entry.FullName.StartsWith('/')) {
                Add-Failure "ZIP entry is rooted instead of archive-relative: $($entry.FullName)"
            }
            $entries[$entry.FullName] = $entry
        }

        if (-not $entries.ContainsKey('pack.mcmeta')) {
            Add-Failure 'ZIP root is missing pack.mcmeta'
        }
        if (-not ($entries.Keys | Where-Object { $_.StartsWith('assets/') })) {
            Add-Failure 'ZIP root is missing assets/'
        }

        foreach ($requiredEntry in $requiredEntries) {
            if (-not $entries.ContainsKey($requiredEntry)) {
                Add-Failure "Missing required ZIP entry: $requiredEntry"
            }
        }

        foreach ($baselineEntry in $baselineHashes.Keys) {
            if (-not $entries.ContainsKey($baselineEntry)) {
                Add-Failure "Missing baseline ZIP entry: $baselineEntry"
                continue
            }
            $actualHash = Get-BytesHash (Get-EntryBytes $entries[$baselineEntry])
            if ($actualHash -ne $baselineHashes[$baselineEntry]) {
                Add-Failure "Baseline hash changed for ${baselineEntry}: expected $($baselineHashes[$baselineEntry]), got $actualHash"
            }
        }

        if ($entries.ContainsKey('assets/bandit/items/bandit_captain_dagger.json')) {
            try {
                $itemDefinition = ([System.Text.Encoding]::UTF8.GetString((Get-EntryBytes $entries['assets/bandit/items/bandit_captain_dagger.json'])) | ConvertFrom-Json)
                if ($itemDefinition.model.type -ne 'minecraft:model' -or $itemDefinition.model.model -ne 'bandit:item/bandit_captain_dagger') {
                    Add-Failure 'Item definition must select minecraft:model bandit:item/bandit_captain_dagger'
                }
            } catch {
                Add-Failure "Item definition is not valid JSON: $($_.Exception.Message)"
            }
        }

        if ($entries.ContainsKey('assets/bandit/models/item/bandit_captain_dagger.json')) {
            try {
                $sourceModel = Get-Content -Raw -Encoding utf8 -LiteralPath $SourceModelPath | ConvertFrom-Json
                $model = ([System.Text.Encoding]::UTF8.GetString((Get-EntryBytes $entries['assets/bandit/models/item/bandit_captain_dagger.json'])) | ConvertFrom-Json)
                if ($model.textures.'0' -ne 'bandit:item/bandit_captain_dagger' -or $model.textures.particle -ne 'bandit:item/bandit_captain_dagger') {
                    Add-Failure '3D model texture 0 and particle must both be bandit:item/bandit_captain_dagger'
                }
                if (($model.elements | ConvertTo-Json -Depth 100 -Compress) -ne ($sourceModel.elements | ConvertTo-Json -Depth 100 -Compress)) {
                    Add-Failure '3D model elements differ from the source model'
                }
                if (($model.display | ConvertTo-Json -Depth 100 -Compress) -ne ($sourceModel.display | ConvertTo-Json -Depth 100 -Compress)) {
                    Add-Failure '3D model display differs from the source model'
                }
            } catch {
                Add-Failure "3D model is not valid JSON or source comparison failed: $($_.Exception.Message)"
            }
        }

        if ($entries.ContainsKey('assets/bandit/textures/item/bandit_captain_dagger.png')) {
            $archiveTextureHash = Get-BytesHash (Get-EntryBytes $entries['assets/bandit/textures/item/bandit_captain_dagger.png'])
            $sourceTextureHash = (Get-FileHash -LiteralPath $SourceTexturePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($archiveTextureHash -ne $sourceTextureHash) {
                Add-Failure "PNG differs from source texture: expected $sourceTextureHash, got $archiveTextureHash"
            }
        }
    } finally {
        $archive.Dispose()
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $LocalTestPackPath 'pack.mcmeta') -PathType Leaf)) {
    Add-Failure "Local test pack is missing pack.mcmeta: $LocalTestPackPath"
}
foreach ($requiredEntry in $requiredEntries) {
    $localFile = Join-Path $LocalTestPackPath ($requiredEntry -replace '/', '\\')
    if (-not (Test-Path -LiteralPath $localFile -PathType Leaf)) {
        Add-Failure "Local test pack is missing: $requiredEntry"
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine($_) }
    throw "FAIL: Bandit captain dagger resource-pack validation found $($failures.Count) problem(s)."
}

Write-Host 'PASS: Bandit captain dagger resource pack is complete.'
