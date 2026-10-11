param(
    [string]$Godot = 'godot',
    [switch]$Native
)
# Dedicated socket-free pointer gate. Shared CI runner remains unchanged.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$executable = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source
$output = Join-Path $projectRoot 'var/ci/world-pointer-picking'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$temporaryData = Join-Path $output ('user-data-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temporaryData | Out-Null
$previousAppData = $env:APPDATA
$previousXdgData = $env:XDG_DATA_HOME
try {
    # Each child process receives disposable storage for input/theme preferences.
    $env:APPDATA = $temporaryData
    $env:XDG_DATA_HOME = $temporaryData
    & (Join-Path $projectRoot 'tools/ci/run-godot-checks.ps1') -Godot $executable -TestNames world_pointer_picking_test.gd,habitat_target_feedback_test.gd,world_inventory_preview_test.gd -OutputDirectory 'var/ci/world-pointer-picking/headless' -TestTimeoutSeconds 60
    if (-not $Native) { return }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $executable
    $info.WorkingDirectory = $projectRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment['FRONTIER_EVENT_URL'] = ''
    $info.Environment['FRONTIER_EVENT_TOKEN'] = ''
    foreach ($argument in @('--path', '.', '--script', 'tests/godot/world_pointer_picking_test.gd', '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--', '--capture-pointer')) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw 'Native pointer fixture did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'Native pointer fixture exceeded 60 seconds.'
        }
        $log = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $output 'native.log'), $log)
        if ($process.ExitCode -ne 0 -or $log -match '(?m)SCRIPT ERROR|(?:^|\s)ERROR:') { throw 'Native pointer fixture failed; inspect var/ci/world-pointer-picking/native.log.' }
        Write-Host 'PASS native world pointer picking (injected automation; human usability unverified)'
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
    }
} finally {
    $env:APPDATA = $previousAppData
    $env:XDG_DATA_HOME = $previousXdgData
    # Retained ignored fixture storage/logs for internal diagnosis; no live saves.
}
