param(
    [string]$Godot = 'godot',
    [Parameter(Mandatory)][switch]$PortsReserved,
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 120
)
# Local verification only. PortsReserved asserts the Coordinator lease; it does not acquire one.
$ErrorActionPreference = 'Stop'
if (-not $PortsReserved) { throw 'Reserve loopback ports 27849 and 27850 through Coordinator first.' }
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$overridePath = Join-Path $projectRoot 'override.cfg'
if (Test-Path -LiteralPath $overridePath) { throw 'Existing override.cfg must be preserved; use a clean isolated worktree.' }
$revision = (& git -C $projectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot pin the source revision.' }
$runId = [Guid]::NewGuid().ToString('N')
$output = Join-Path $projectRoot "var/ci/tutorial-readiness/$runId"
New-Item -ItemType Directory -Force -Path $output | Out-Null
$profileName = "FrontierSystems-tutorial-$runId"
$previousCapture = [Environment]::GetEnvironmentVariable('FRONTIER_VERIFICATION_CAPTURE_DIRECTORY', 'Process')
$manifest = [ordered]@{
    revision = $revision
    started_utc = [DateTime]::UtcNow.ToString('o')
    profile_name = $profileName
    ports = @(27849, 27850)
    engine = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source
    runtime = 'not run'
    graphical = 'not run'
    human_acceptance = 'not performed; scripted motion and guide calls'
    media = 'internal ordinary Godot capture only; no publication clearance'
}
function Assert-PortAvailable([int]$Port) {
    # Bind a short-lived probe without replacing or stopping an existing listener.
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
    try { $probe.Start() } finally { $probe.Stop() }
}
try {
    # Godot's custom user directory keeps controls, journals and checkpoints away
    # from the operator's regular profile. The unique temporary profile is retained
    # as evidence; remove that exact directory after review, never the parent.
    $configuration = "[application]`nconfig/use_custom_user_dir=true`nconfig/custom_user_dir_name=`"$profileName`"`n"
    [IO.File]::WriteAllText($overridePath, $configuration)
    $env:FRONTIER_VERIFICATION_CAPTURE_DIRECTORY = (Join-Path $output 'capture').Replace('\', '/')
    Assert-PortAvailable 27849
    & (Join-Path $PSScriptRoot 'run-godot-checks.ps1') -Godot $Godot -TestNames @(
        'local_character_navigation_test.gd', 'desktop_controls_help_test.gd',
        'first_playable_task_guide_test.gd', 'first_playable_acceptance.gd'
    ) -TestTimeoutSeconds $TimeoutSeconds -OutputDirectory "var/ci/tutorial-readiness/$runId/runtime"
    $manifest.runtime = 'passed: existing bounded headless runner'
    Assert-PortAvailable 27850
    & (Join-Path $PSScriptRoot 'run-first-playable-render-check.ps1') -Godot $Godot -Route basic -TimeoutSeconds $TimeoutSeconds
    Copy-Item -LiteralPath (Join-Path $projectRoot 'var/ci/render-basic/stdout.log') -Destination (Join-Path $output 'graphical-stdout.log')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'var/ci/render-basic/stderr.log') -Destination (Join-Path $output 'graphical-stderr.log')
    $manifest.graphical = 'passed: native renderer, real client, scripted character motion and guide calls'
} catch {
    $manifest.failure = $_.Exception.Message
    throw
} finally {
    if (Test-Path -LiteralPath $overridePath) { Remove-Item -LiteralPath $overridePath }
    [Environment]::SetEnvironmentVariable('FRONTIER_VERIFICATION_CAPTURE_DIRECTORY', $previousCapture, 'Process')
    $manifest.finished_utc = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $output 'manifest.json'), ($manifest | ConvertTo-Json -Depth 4))
    Write-Host "Tutorial evidence: $output. Human acceptance remains required."
}