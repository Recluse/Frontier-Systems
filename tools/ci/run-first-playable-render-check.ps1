param(
    [string]$Godot = 'godot',
    [ValidateSet('basic', 'terrain', 'walls', 'machinery', 'equipment-fabrication', 'tool-parts')]
    [string]$Route = 'terrain',
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$executable = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source
$output = Join-Path $projectRoot "var/ci/render-$Route"
New-Item -ItemType Directory -Force -Path $output | Out-Null
$stdout = Join-Path $output 'stdout.log'
$stderr = Join-Path $output 'stderr.log'
$arguments = @('--xr-mode', 'off', '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility', '--path', '.', '--script', 'res://tests/godot/first_playable_client_render_check.gd', '--', "--$Route")
$launch = @{
    FilePath = $executable
    ArgumentList = $arguments
    WorkingDirectory = $projectRoot
    RedirectStandardOutput = $stdout
    RedirectStandardError = $stderr
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
        throw "Graphical $Route route exceeded $TimeoutSeconds seconds."
    }
    $log = [IO.File]::ReadAllText($stdout) + [IO.File]::ReadAllText($stderr)
    if ($process.ExitCode -ne 0 -or $log -match '(?m)SCRIPT ERROR|(?:^|\s)ERROR:') {
        Write-Host $log.Substring(0, [Math]::Min(3000, $log.Length))
        throw "Graphical $Route route failed; see $output."
    }
    Write-Host "PASS graphical $Route route (native renderer; logs at $output)"
} finally {
    if (-not $process.HasExited) { $process.Kill($true) }
    $process.Dispose()
}
