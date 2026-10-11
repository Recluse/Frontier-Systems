param(
    [string]$Godot = 'godot',
    [switch]$PortsReserved,
    [ValidateSet('basic', 'terrain', 'walls', 'machinery', 'equipment-fabrication', 'tool-parts', 'input-acceptance', 'client-acceptance', 'production-navigation')]
    [string]$Route = 'terrain',
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
if ($Route -eq 'client-acceptance' -and -not $PortsReserved) { throw 'Reserve loopback port 27850 through Coordinator before client-acceptance.' }
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$executable = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source
$output = Join-Path $projectRoot "var/ci/render-$Route"
New-Item -ItemType Directory -Force -Path $output | Out-Null
$stdout = Join-Path $output 'stdout.log'
$stderr = Join-Path $output 'stderr.log'
$script = if ($Route -eq 'input-acceptance') { 'res://tests/godot/client_input_render_check.gd' } elseif ($Route -eq 'client-acceptance') { 'res://tests/godot/client_ui_acceptance_render_check.gd' } else { 'res://tests/godot/first_playable_client_render_check.gd' }
$arguments = @('--xr-mode', 'off', '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility', '--path', '.', '--script', $script, '--', "--$Route")
if ($Route -eq 'client-acceptance') { $arguments += '--ports-reserved' }
if ($Route -eq 'production-navigation') {
    # Detached panel fixture: no client connection or listening ports.
    $arguments = @('--xr-mode', 'off', '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility', '--path', '.', '--script', 'res://tests/godot/production_panel_navigation_test.gd', '--', '--capture-production-navigation')
}
$launch = @{
    FilePath = $executable
    ArgumentList = $arguments
    WorkingDirectory = $projectRoot
    RedirectStandardOutput = $stdout
    RedirectStandardError = $stderr
    PassThru = $true
}
if ($IsWindows) { $launch.WindowStyle = 'Hidden' }
$previousEventUrl = [Environment]::GetEnvironmentVariable('FRONTIER_EVENT_URL', 'Process')
$previousEventToken = [Environment]::GetEnvironmentVariable('FRONTIER_EVENT_TOKEN', 'Process')
$env:FRONTIER_EVENT_URL = ''
$env:FRONTIER_EVENT_TOKEN = ''
$process = $null
try {
    $process = Start-Process @launch
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
    if ($null -ne $process) {
        if (-not $process.HasExited) { $process.Kill($true) }
        $process.Dispose()
    }
    [Environment]::SetEnvironmentVariable('FRONTIER_EVENT_URL', $previousEventUrl, 'Process')
    [Environment]::SetEnvironmentVariable('FRONTIER_EVENT_TOKEN', $previousEventToken, 'Process')
}
