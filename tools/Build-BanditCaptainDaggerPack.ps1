[CmdletBinding()]
param(
    [string]$ArchivePath,
    [string]$BuildRoot = 'C:\Users\User\Documents\26.2\build',
    [string]$SourceModelPath,
    [string]$SourceTexturePath = 'D:\Users\User\Downloads\assets\minecraft\textures\item\cybernetic_knife.png',
    [string]$LocalTestPackPath,
    [switch]$ValidateLocalTestPackPathOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ($null -eq ('BanditCaptainNativePath' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class BanditCaptainNativePath {
    [StructLayout(LayoutKind.Sequential)]
    private struct FileTime {
        public uint Low;
        public uint High;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileInformation {
        public uint Attributes;
        public FileTime CreationTime;
        public FileTime LastAccessTime;
        public FileTime LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string path, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
        uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(
        SafeFileHandle handle, StringBuilder buffer, uint bufferLength, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle handle, out FileInformation information);

    private static SafeFileHandle Open(string path) {
        SafeFileHandle handle = CreateFile(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
        if (handle.IsInvalid) {
            throw new IOException("Unable to inspect path identity: " + path);
        }
        return handle;
    }

    public static string CanonicalExistingPath(string path) {
        SafeFileHandle handle = Open(path);
        try {
            uint length = GetFinalPathNameByHandle(handle, null, 0, 0);
            if (length == 0) throw new IOException("Unable to resolve path: " + path);
            StringBuilder buffer = new StringBuilder((int)length + 1);
            if (GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0) == 0) {
                throw new IOException("Unable to resolve path: " + path);
            }
            return buffer.ToString();
        } finally {
            handle.Dispose();
        }
    }

    public static string ExistingFileIdentity(string path) {
        SafeFileHandle handle = Open(path);
        try {
            FileInformation information;
            if (!GetFileInformationByHandle(handle, out information)) {
                throw new IOException("Unable to inspect file identity: " + path);
            }
            return information.VolumeSerialNumber + ":" + information.FileIndexHigh + ":" + information.FileIndexLow;
        } finally {
            handle.Dispose();
        }
    }
}
'@
}

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manhuang-resource-pack.zip'
}
if ([string]::IsNullOrWhiteSpace($SourceModelPath)) {
    $SourceModelPath = Join-Path 'D:\Users\User\Downloads\assets\minecraft\models\item' ("$([char]0x5315)$([char]0x9996)4.json")
}
$localTestPackName = "$([char]0x883B)$([char]0x8352)$([char]0x9006)$([char]0x5883)-$([char]0x76DC)$([char]0x8CCA)$([char]0x982D)$([char]0x76EE)$([char]0x6750)$([char]0x8CEA)$([char]0x6E2C)$([char]0x8A66)"
$localTestPackParent = 'C:\Users\User\curseforge\minecraft\Instances\26.2\resourcepacks'
if ([string]::IsNullOrWhiteSpace($LocalTestPackPath)) {
    $LocalTestPackPath = Join-Path $localTestPackParent $localTestPackName
}

function Get-CanonicalPath {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $fullPath) {
        return ([BanditCaptainNativePath]::CanonicalExistingPath($fullPath)).TrimEnd('\\')
    }

    $parent = Split-Path -Parent $fullPath
    $leaf = Split-Path -Leaf $fullPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "Cannot resolve a non-existent parent directory for path safety check: $fullPath"
    }
    return ([System.IO.Path]::Combine(([BanditCaptainNativePath]::CanonicalExistingPath($parent)).TrimEnd('\\'), $leaf))
}

function Test-SamePath {
    param([string]$Left, [string]$Right)

    return [string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePointComponent {
    param([Parameter(Mandatory)] [string]$Path)

    $current = [System.IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $null -ne $item.LinkType) {
                throw "Refusing unsafe LocalTestPackPath: path contains a link or reparse-point component: $current"
            }
        }

        $parentInfo = [System.IO.Directory]::GetParent($current)
        if ($null -eq $parentInfo -or (Test-SamePath $parentInfo.FullName $current)) {
            break
        }
        $current = $parentInfo.FullName
    }
}

function Assert-SafeLocalTestPackPath {
    param([Parameter(Mandatory)] [string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $leaf = [System.IO.Path]::GetFileName($fullPath)
    if (-not [string]::Equals($leaf, $localTestPackName, [System.StringComparison]::Ordinal)) {
        throw "Refusing unsafe LocalTestPackPath: leaf must be exactly '$localTestPackName': $fullPath"
    }

    $parentPath = [System.IO.Path]::GetDirectoryName($fullPath)
    if ([string]::IsNullOrWhiteSpace($parentPath) -or -not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        throw "Refusing unsafe LocalTestPackPath: the dedicated parent directory does not exist: $parentPath"
    }
    if (-not [string]::Equals([System.IO.Path]::GetFileName($parentPath), 'resourcepacks', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($parentPath)), '26.2', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe LocalTestPackPath: target must be a direct child of the dedicated 26.2/resourcepacks directory: $fullPath"
    }

    Assert-NoReparsePointComponent $fullPath
    Assert-NoReparsePointComponent $localTestPackParent

    $actualParentCanonical = Get-CanonicalPath $parentPath
    $expectedParentCanonical = Get-CanonicalPath $localTestPackParent
    if (-not (Test-SamePath $actualParentCanonical $expectedParentCanonical)) {
        throw "Refusing unsafe LocalTestPackPath: parent is not the dedicated resourcepacks directory: $parentPath"
    }

    $actualCanonical = Get-CanonicalPath $fullPath
    $expectedCanonical = Get-CanonicalPath (Join-Path $localTestPackParent $localTestPackName)
    if (-not (Test-SamePath $actualCanonical $expectedCanonical)) {
        throw "Refusing unsafe LocalTestPackPath: resolved target is not the dedicated test pack: $fullPath"
    }

    if (Test-Path -LiteralPath $fullPath) {
        $targetItem = Get-Item -LiteralPath $fullPath -Force
        if (-not $targetItem.PSIsContainer) {
            throw "Refusing unsafe LocalTestPackPath: existing target is not a directory: $fullPath"
        }
        if (($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $null -ne $targetItem.LinkType) {
            throw "Refusing unsafe LocalTestPackPath: target is a link or reparse point: $fullPath"
        }
    }

    return $fullPath
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$deterministicEntryTimestamp = [System.DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
$LocalTestPackPath = Assert-SafeLocalTestPackPath $LocalTestPackPath
if ($ValidateLocalTestPackPathOnly) {
    Write-Host "PASS: LocalTestPackPath safety validation accepted the dedicated path: $LocalTestPackPath"
    return
}

$stageRoot = Join-Path $BuildRoot 'bandit-captain-dagger'
$stageAssetsRoot = Join-Path $stageRoot 'assets\bandit'
$stageItemPath = Join-Path $stageAssetsRoot 'items\bandit_captain_dagger.json'
$stageModelPath = Join-Path $stageAssetsRoot 'models\item\bandit_captain_dagger.json'
$stageTexturePath = Join-Path $stageAssetsRoot 'textures\item\bandit_captain_dagger.png'
$candidateZip = Join-Path $stageRoot 'manhuang-resource-pack.zip'
$packMetadataPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'pack.mcmeta'

$requiredEntries = @(
    'assets/bandit/items/bandit_captain_dagger.json',
    'assets/bandit/models/item/bandit_captain_dagger.json',
    'assets/bandit/textures/item/bandit_captain_dagger.png'
)

foreach ($path in @($ArchivePath, $SourceModelPath, $SourceTexturePath, $packMetadataPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required source file is missing: $path"
    }
}

$ArchivePath = [System.IO.Path]::GetFullPath($ArchivePath)
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
$archiveCanonical = Get-CanonicalPath $ArchivePath
$candidateCanonical = Get-CanonicalPath $candidateZip
$archiveDirectoryCanonical = Get-CanonicalPath (Split-Path -Parent $ArchivePath)
$worktreeCanonical = Get-CanonicalPath (Split-Path -Parent $PSScriptRoot)
$localTestPackCanonical = Get-CanonicalPath $LocalTestPackPath

if ((Test-SamePath $archiveCanonical $candidateCanonical) -or ((Test-Path -LiteralPath $candidateZip -PathType Leaf) -and ([BanditCaptainNativePath]::ExistingFileIdentity($ArchivePath) -eq [BanditCaptainNativePath]::ExistingFileIdentity($candidateZip)))) {
    throw 'Refusing to build because ArchivePath and candidateZip identify the same file.'
}
if ((Test-SamePath $localTestPackCanonical $archiveDirectoryCanonical) -or
    (Test-SamePath $localTestPackCanonical $worktreeCanonical) -or
    $localTestPackCanonical.StartsWith($worktreeCanonical + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to clear a local test-pack path that resolves inside the worktree or archive directory.'
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
    $generatedFiles = [ordered]@{
        'pack.mcmeta' = $packMetadataPath
        'assets/bandit/items/bandit_captain_dagger.json' = $stageItemPath
        'assets/bandit/models/item/bandit_captain_dagger.json' = $stageModelPath
        'assets/bandit/textures/item/bandit_captain_dagger.png' = $stageTexturePath
    }

    foreach ($entry in $sourceArchive.Entries) {
        if ($generatedFiles.Contains($entry.FullName)) {
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

    foreach ($entryName in $generatedFiles.Keys) {
        $destinationEntry = $candidateArchive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        $destinationEntry.LastWriteTime = $deterministicEntryTimestamp
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

if (Test-Path -LiteralPath $LocalTestPackPath) {
    $LocalTestPackPath = Assert-SafeLocalTestPackPath $LocalTestPackPath
    Remove-Item -LiteralPath $LocalTestPackPath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $LocalTestPackPath | Out-Null
Copy-Item -LiteralPath $packMetadataPath -Destination (Join-Path $LocalTestPackPath 'pack.mcmeta') -Force
foreach ($entryName in $requiredEntries) {
    $destination = Join-Path $LocalTestPackPath ($entryName -replace '/', '\\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $generatedFiles[$entryName] -Destination $destination -Force
}

 $testScript = Join-Path $PSScriptRoot 'Test-BanditCaptainDaggerPack.ps1'
if (-not (Test-Path -LiteralPath $testScript -PathType Leaf)) {
    throw "Candidate validator is missing: $testScript"
}
& $testScript -ArchivePath $candidateZip -SourceModelPath $SourceModelPath -SourceTexturePath $SourceTexturePath -LocalTestPackPath $LocalTestPackPath

$publishTemp = Join-Path (Split-Path -Parent $ArchivePath) ('.' + (Split-Path -Leaf $ArchivePath) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
$publishBackup = Join-Path (Split-Path -Parent $ArchivePath) ('.' + (Split-Path -Leaf $ArchivePath) + '.' + [Guid]::NewGuid().ToString('N') + '.bak')
try {
    Copy-Item -LiteralPath $candidateZip -Destination $publishTemp -Force
    [System.IO.File]::Replace($publishTemp, $ArchivePath, $publishBackup)
} finally {
    if (Test-Path -LiteralPath $publishTemp -PathType Leaf) {
        Remove-Item -LiteralPath $publishTemp -Force
    }
    if (Test-Path -LiteralPath $publishBackup -PathType Leaf) {
        Remove-Item -LiteralPath $publishBackup -Force
    }
}

Write-Host "BUILD: candidate ZIP created at $candidateZip"
Write-Host "BUILD: local test pack updated at $LocalTestPackPath"
Write-Host "BUILD: candidate validation passed and ArchivePath was atomically replaced."
