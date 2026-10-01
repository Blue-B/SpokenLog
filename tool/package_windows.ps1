param(
    [Parameter(Mandatory=$true)][string]$ReleaseDir,
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [string]$Compiler = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
)
$ErrorActionPreference = 'Stop'
$ReleaseDir = (Resolve-Path -LiteralPath $ReleaseDir).Path
$versionText = Get-Content (Join-Path $PSScriptRoot '../pubspec.yaml') -Raw
if ($versionText -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'Expected major.minor.patch+build.' }
$appVersion = $Matches[1]
$buildNumber = $Matches[2]
$exe = Join-Path $ReleaseDir 'SpokenLog.exe'
if ((Get-Item $exe).VersionInfo.ProductVersion -ne "$appVersion+$buildNumber") { throw 'Executable/source version mismatch.' }
foreach ($file in @('flutter_windows.dll', 'sherpa-onnx-c-api.dll', 'onnxruntime.dll', 'url_launcher_windows_plugin.dll', 'vcruntime140.dll', 'msvcp140.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDir $file))) { throw "Missing runtime: $file" }
}
if (-not (Test-Path -LiteralPath $Compiler)) { throw 'Inno Setup compiler missing. Install it or pass -Compiler.' }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
foreach ($name in @('SpokenLog-Windows-x64.zip', 'SpokenLog-Windows-x64-Setup.exe')) {
    if (Test-Path -LiteralPath (Join-Path $OutputDir $name)) { throw "Output already exists: $name" }
}
# Preserve the source release tree and stage only files owned by this build.
$stage = Join-Path $OutputDir ('stage-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -Path (Join-Path $ReleaseDir '*') -Destination $stage -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows/ManageData.ps1') -Destination $stage
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open(
    (Join-Path $OutputDir 'SpokenLog-Windows-x64.zip'), [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $stage -File -Recurse | ForEach-Object {
        $name = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $_.FullName, $name, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $zip.Dispose() }
& $Compiler "/DReleaseDir=$stage" "/DOutputDir=$OutputDir" "/DAppVersion=$appVersion" "/DBuildNumber=$buildNumber" (Join-Path $PSScriptRoot 'windows/SpokenLog.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Get-FileHash -Algorithm SHA256 (Join-Path $OutputDir 'SpokenLog-Windows-x64.zip'), (Join-Path $OutputDir 'SpokenLog-Windows-x64-Setup.exe')
