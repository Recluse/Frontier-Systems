param(
    [string]$Godot = 'godot',
    [switch]$Native
)
# Dedicated socket-free selected-target guidance gate. Shared CI runner remains unchanged.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$executable = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source
$output = Join-Path $projectRoot 'var/ci/selected-target-controls'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$temporaryData = Join-Path $output ('user-data-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $temporaryData | Out-Null
$manifest = [ordered]@{
    revision = (& git -C $projectRoot rev-parse HEAD).Trim()
    working_tree = @(& git -C $projectRoot status --short --untracked-files=all)
    started_utc = [DateTime]::UtcNow.ToString('o')
    engine = $executable
    headless = 'not_run'
    native = 'not_run'
    physical_input = 'not_run'
    controller_vr = 'not_run'
    focus_loss = 'headless held-look regression uses injected notifications; no OS focus switch'
    ports = @()
    media = 'ignored/internal ordinary engine rendering'
}
$previousAppData = $env:APPDATA
$previousXdgData = $env:XDG_DATA_HOME
try {
    # Each child process receives disposable storage for input/theme preferences.
    $env:APPDATA = $temporaryData
    $env:XDG_DATA_HOME = $temporaryData
    & (Join-Path $projectRoot 'tools/ci/run-godot-checks.ps1') -Godot $executable -TestNames selected_target_controls_test.gd,habitat_target_feedback_test.gd,held_look_ui_activation_test.gd -OutputDirectory 'var/ci/selected-target-controls/headless' -TestTimeoutSeconds 60
    $manifest.headless = 'passed'
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
    foreach ($argument in @('--xr-mode', 'off', '--path', '.', '--script', 'tests/godot/selected_target_controls_test.gd', '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--', '--capture-selected')) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw 'Native selected-target guidance fixture did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'Native selected-target guidance fixture exceeded 60 seconds.'
        }
        $log = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $output 'native.log'), $log)
        if ($process.ExitCode -ne 0 -or $log -match '(?m)SCRIPT ERROR|(?:^|\s)ERROR:') { throw 'Native selected-target guidance fixture failed; inspect var/ci/selected-target-controls/native.log.' }
        $manifest.native = 'passed'
        Write-Host 'PASS native selected-target guidance (injected automation; human usability unverified)'
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
    }
} catch {
    $manifest.failure = $_.Exception.Message
    throw
} finally {
    $manifest.finished_utc = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $output 'manifest.json'), ($manifest | ConvertTo-Json -Depth 4))
    $env:APPDATA = $previousAppData
    $env:XDG_DATA_HOME = $previousXdgData
    # Retained ignored fixture storage/logs for internal diagnosis; no live saves.
}
