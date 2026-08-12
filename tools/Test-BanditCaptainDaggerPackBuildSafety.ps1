[CmdletBinding()]
param(
    [string]$BuildRoot = 'C:\Users\User\Documents\26.2\build'
)

$ErrorActionPreference = 'Stop'

$builder = Join-Path $PSScriptRoot 'Build-BanditCaptainDaggerPack.ps1'
$fixtureRoot = Join-Path $BuildRoot 'bandit-captain-dagger\build-safety-tests'
$workspaceRoot = 'C:\Users\User\Documents\26.2'
$expectedPackName = "$([char]0x883B)$([char]0x8352)$([char]0x9006)$([char]0x5883)-$([char]0x76DC)$([char]0x8CCA)$([char]0x982D)$([char]0x76EE)$([char]0x6750)$([char]0x8CEA)$([char]0x6E2C)$([char]0x8A66)"
$expectedParent = 'C:\Users\User\curseforge\minecraft\Instances\26.2\resourcepacks'
$expectedPack = Join-Path $expectedParent $expectedPackName

if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw "Builder is missing: $builder"
}

if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null

function Invoke-ExpectedGuardRejection {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Path,
        [string]$SentinelPath
    )

    try {
        & $builder -LocalTestPackPath $Path -ValidateLocalTestPackPathOnly
    } catch {
        if ($_.Exception.Message -notlike 'Refusing unsafe LocalTestPackPath:*') {
            throw "${Name}: builder failed for an unexpected reason: $($_.Exception.Message)"
        }
        if ($SentinelPath -and -not (Test-Path -LiteralPath $SentinelPath -PathType Leaf)) {
            throw "${Name}: safety guard deleted or replaced the sentinel"
        }
        Write-Host "PASS: build safety guard rejected $Name without deleting it"
        return
    }

    throw "Build safety guard unexpectedly accepted $Name"
}

$ordinaryDirectory = Join-Path $fixtureRoot 'ordinary-directory'
New-Item -ItemType Directory -Force -Path $ordinaryDirectory | Out-Null
$ordinarySentinel = Join-Path $ordinaryDirectory 'must-survive.txt'
Set-Content -LiteralPath $ordinarySentinel -Value 'must survive' -NoNewline -Encoding UTF8

Invoke-ExpectedGuardRejection 'the workspace root' $workspaceRoot
Invoke-ExpectedGuardRejection 'the drive root' 'C:\'
Invoke-ExpectedGuardRejection 'an arbitrary ordinary directory' $ordinaryDirectory $ordinarySentinel

$aliasParent = Join-Path $fixtureRoot 'resourcepacks-junction'
New-Item -ItemType Junction -Path $aliasParent -Target $expectedParent | Out-Null
try {
    Invoke-ExpectedGuardRejection 'a reparse-point alias of the dedicated parent' (Join-Path $aliasParent $expectedPackName)
} finally {
    [System.IO.Directory]::Delete($aliasParent)
}

& $builder -LocalTestPackPath $expectedPack -ValidateLocalTestPackPathOnly
Write-Host 'PASS: build safety guard accepts only the dedicated local test-pack path.'
