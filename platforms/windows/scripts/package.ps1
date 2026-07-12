# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [Parameter(Mandatory = $true)] [string] $PublishDirectory,
    [Parameter(Mandatory = $true)] [string] $OutputDirectory,
    [string] $Version = "0.1.0-preview",
    [string] $Commit = "unknown"
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$publish = (Resolve-Path $PublishDirectory).Path
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
$name = "MouseBridge-v$Version-win-x64"
$stagingRoot = Join-Path $output "staging"
$stage = Join-Path $stagingRoot $name
$legal = Join-Path $stage "Legal"
$licenses = Join-Path $legal "LICENSES"

if (Test-Path $stagingRoot) { Remove-Item $stagingRoot -Recurse -Force }
New-Item $stage -ItemType Directory -Force | Out-Null
New-Item $licenses -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $publish "*") $stage -Recurse -Force
Copy-Item (Join-Path $repo "platforms\windows\README.md") (Join-Path $stage "README.md")
Copy-Item (Join-Path $repo "LICENSE") (Join-Path $legal "GPL-3.0.txt")
Copy-Item (Join-Path $repo "COPYRIGHT") $legal
Copy-Item (Join-Path $repo "THIRD_PARTY_NOTICES.md") $legal
Copy-Item (Join-Path $repo "SOURCE.md") $legal
Copy-Item (Join-Path $repo "LICENSES\Apache-2.0.txt") $licenses
Copy-Item (Join-Path $repo "LICENSES\GPL-2.0.txt") $licenses
Copy-Item (Join-Path $repo "LICENSES\Scroll-Reverser-NOTICE.txt") $licenses

@"
MouseBridge Windows $Version
Repository: https://github.com/gmch1/mousebridge-macos
Source commit: $Commit
Build: .NET 8, framework-dependent, win-x64
Hardware status: Windows M750 L Bluetooth support is not yet physically verified.
"@ | Set-Content (Join-Path $stage "BUILD-INFO.txt") -Encoding utf8

New-Item $output -ItemType Directory -Force | Out-Null
$asset = Join-Path $output "$name.zip"
if (Test-Path $asset) { Remove-Item $asset -Force }
Compress-Archive -Path $stage -DestinationPath $asset -CompressionLevel Optimal
$hash = (Get-FileHash $asset -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([System.IO.Path]::GetFileName($asset))" | Set-Content "$asset.sha256" -Encoding ascii
Write-Output $asset
Write-Output "$asset.sha256"
