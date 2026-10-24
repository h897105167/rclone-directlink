<#
.SYNOPSIS
    Build a Windows amd64 rclone with the TelDrive direct-link patch applied.

.DESCRIPTION
    Clones upstream gulp79/rclone-extra at the pinned commit, applies
    patches/rclone-extra.diff, and builds with the same ldflags used for the
    released binary, so `rclone version` reports the same string.

.EXAMPLE
    .\scripts\build-windows.ps1
    .\scripts\build-windows.ps1 -OutDir D:\tmp\rclone-out
#>
[CmdletBinding()]
param(
    [string]$WorkDir  = (Join-Path $PSScriptRoot '..\_build'),
    [string]$OutDir   = (Join-Path $PSScriptRoot '..\out'),
    [string]$Upstream = 'https://github.com/gulp79/rclone-extra.git',
    [string]$Commit   = '066443b420e185d8795f832d29055174a68b7694',
    [string]$Version  = 'v1.75.2-extra-11-g066443b4-directlink',
    [string]$GoOS     = 'windows',
    [string]$GoArch   = 'amd64',
    [switch]$ReuseSrc
)

$ErrorActionPreference = 'Stop'
$patch = Join-Path $PSScriptRoot '..\patches\rclone-extra.diff'
$src   = Join-Path $WorkDir 'rclone-extra'

if (-not (Test-Path $patch)) { throw "patch not found: $patch" }
New-Item -ItemType Directory -Force -Path $WorkDir, $OutDir | Out-Null

if ($ReuseSrc -and (Test-Path (Join-Path $src '.git'))) {
    Write-Host "== reusing source tree $src"
} else {
    if (Test-Path $src) { Remove-Item $src -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    Write-Host "== fetching $Upstream @ $Commit"
    git -C $src init -q
    git -C $src remote add origin $Upstream
    git -C $src fetch --depth 1 origin $Commit
    git -C $src checkout -q FETCH_HEAD
}

$head = (git -C $src rev-parse HEAD).Trim()
if ($head -ne $Commit) { throw "source tree is at $head, expected $Commit (drop -ReuseSrc or use a clean WorkDir)" }

git -C $src apply --check $patch
if ($LASTEXITCODE -ne 0) { throw 'patch does not apply cleanly' }
git -C $src apply $patch
if ($LASTEXITCODE -ne 0) { throw 'git apply failed' }
Write-Host "== patch applied"

$env:CGO_ENABLED = '0'
$env:GOOS        = $GoOS
$env:GOARCH      = $GoArch
$out = Join-Path $OutDir "rclone-$Version-$GoOS-$GoArch.exe"

Push-Location $src
try {
    Write-Host "== go build -> $out"
    & go build -trimpath `
        -ldflags "-s -w -X github.com/rclone/rclone/fs.Version=$Version" `
        -o $out .
    if ($LASTEXITCODE -ne 0) { throw "go build failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
}

$f = Get-Item $out
$h = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower()
Write-Host ''
Write-Host ("built  : {0}" -f $f.FullName)
Write-Host ("size   : {0:N0} B" -f $f.Length)
Write-Host ("sha256 : {0}" -f $h)
Write-Host ("version: {0}" -f (& $out version 2>&1 | Select-Object -First 1))
