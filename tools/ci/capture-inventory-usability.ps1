param(
    [string]$Godot = 'godot',
    [ValidateSet('gl_compatibility', 'forward_plus')][string]$RenderingMethod = 'gl_compatibility',
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 60
)
# Native ordinary-render verification of the actual panel; no network listeners.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$executable = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source
$output = Join-Path $projectRoot 'var/ci/inventory-usability-render'
$overridePath = Join-Path $projectRoot 'override.cfg'
if (Test-Path -LiteralPath $overridePath) { throw 'Preserve existing override.cfg; use a clean isolated worktree.' }
New-Item -ItemType Directory -Force -Path $output | Out-Null
$profileName = 'FrontierSystems-inventory-' + [Guid]::NewGuid().ToString('N')
$process = $null
try {
    [IO.File]::WriteAllText($overridePath, "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"$profileName`"`n")
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $executable
    $info.WorkingDirectory = $projectRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment['FRONTIER_EVENT_URL'] = ''
    $info.Environment['FRONTIER_EVENT_TOKEN'] = ''
    foreach ($argument in @('--xr-mode', 'off', '--audio-driver', 'Dummy', '--rendering-method', $RenderingMethod, '--path', '.', '--script', 'res://tests/godot/player_inventory_usability_test.gd', '--', '--capture-inventory')) {
        $info.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Inventory renderer did not start.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw 'Inventory render verification exceeded its deadline.'
    }
    $log = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $output "$RenderingMethod.log"), $log)
    if ($process.ExitCode -ne 0 -or $log -match '(?m)SCRIPT ERROR|(?:^|\s)ERROR:') {
        Write-Host $log.Substring(0, [Math]::Min(3000, $log.Length))
        throw "Inventory render verification failed; see $output."
    }
    Write-Host "PASS inventory panel native $RenderingMethod rendering; injected keyboard/real domain fixture only; human acceptance unverified. Captures: $output"
} finally {
    if ($null -ne $process) {
        if (-not $process.HasExited) { $process.Kill($true) }
        $process.Dispose()
    }
    Remove-Item -LiteralPath $overridePath -ErrorAction SilentlyContinue
}
