param(
    [string]$Godot = 'godot',
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$executable = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source
$output = Join-Path $projectRoot 'var/ci/repair-usability'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$launch = @{
    FilePath = $executable
    ArgumentList = @('--xr-mode', 'off', '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility', '--path', '.', '--script', 'res://tests/godot/repair_usability_test.gd', '--', '--capture-maintenance')
    WorkingDirectory = $projectRoot
    RedirectStandardOutput = (Join-Path $output 'stdout.log')
    RedirectStandardError = (Join-Path $output 'stderr.log')
    PassThru = $true
}
if ($IsWindows) { $launch.WindowStyle = 'Hidden' }
$env:FRONTIER_EVENT_URL = ''
$env:FRONTIER_EVENT_TOKEN = ''
$process = Start-Process @launch
try {
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw 'Repair capture exceeded its deadline.'
    }
    $log = [IO.File]::ReadAllText($launch.RedirectStandardOutput) + [IO.File]::ReadAllText($launch.RedirectStandardError)
    if ($process.ExitCode -ne 0 -or $log -match '(?m)SCRIPT ERROR|(?:^|\s)ERROR:') {
        Write-Host $log.Substring(0, [Math]::Min(3000, $log.Length))
        throw "Repair capture failed; see $output."
    }
    Write-Host "PASS graphical repair usability (native renderer; ignored captures at $output)"
} finally {
    if (-not $process.HasExited) { $process.Kill($true) }
    $process.Dispose()
}
