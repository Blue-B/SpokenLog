$ErrorActionPreference = 'Stop'
try {
    $exe = Join-Path $PSScriptRoot 'SpokenLog.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'SpokenLog.exe not found.' }
    $running = Get-Process -Name SpokenLog -ErrorAction SilentlyContinue
    if ($running) { throw 'Close all SpokenLog windows before continuing.' }
    # The app resolves its own platform-specific paths and asks before deletion.
    # No PowerShell Remove-Item or registry cleanup of user data is performed.
    $env:SPOKENLOG_UNINSTALL = '1'
    $process = Start-Process -FilePath $exe -WorkingDirectory $PSScriptRoot -Wait -PassThru
    exit $process.ExitCode
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'SpokenLog') | Out-Null
    exit 1
}
