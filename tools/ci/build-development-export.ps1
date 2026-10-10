param(
    [ValidateSet('windows', 'linux')][string]$Platform,
    [string]$Godot = 'godot',
    [string]$OutputDirectory = 'var/ci/exports',
    [string]$Revision = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (($Platform -eq 'windows') -ne $IsWindows) { throw 'Build and smoke-test on the target operating system.' }
$executable = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source
if (-not $Revision) { $Revision = (& git -C $projectRoot rev-parse HEAD).Trim() }
if ($Revision -notmatch '^[0-9a-f]{40}$') { throw 'An exact Git commit SHA is required.' }
$output = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
$bundle = Join-Path $output $Platform
if ((Test-Path -LiteralPath $bundle) -and @(Get-ChildItem -Force -LiteralPath $bundle).Count -gt 0) { throw 'Choose an empty export directory; stale build files must not be packaged.' }
New-Item -ItemType Directory -Force -Path $bundle | Out-Null
$preset = if ($IsWindows) { 'Windows Development' } else { 'Linux Development' }
$filename = if ($IsWindows) { 'FrontierSystems.exe' } else { 'FrontierSystems.x86_64' }
$binary = Join-Path $bundle $filename

function Invoke-BuildProcess([string]$Program, [string[]]$Arguments, [string]$Name, [int]$Deadline, [bool]$Smoke = $false) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Program
    $info.WorkingDirectory = $projectRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment['FRONTIER_EVENT_URL'] = ''
    $info.Environment['FRONTIER_EVENT_TOKEN'] = ''
    if ($Smoke) {
        $info.Environment['FRONTIER_PLAYER_ONE_KEY'] = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
        $info.Environment['FRONTIER_PLAYER_TWO_KEY'] = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
        $info.Environment['FRONTIER_SAVE_DIRECTORY'] = Join-Path $projectRoot "var/ci/export-smoke/$([Guid]::NewGuid().ToString('N'))"
    }
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw 'Process did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($Deadline * 1000)
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        $log = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $output "$Platform-$Name.log"), $log)
        if ($timedOut) { throw "$Name exceeded its deadline; see $Platform-$Name.log." }
        if ($process.ExitCode -ne 0 -or $log -match '(?m)SCRIPT ERROR|(?:^|\s)ERROR:') { throw "$Name failed; see $Platform-$Name.log." }
        if ($Smoke -and -not $log.Contains('First playable host listening on loopback port')) { throw 'Export did not start the cooperative host entrypoint.' }
        Write-Host "PASS $Name"
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true) }
        $process.Dispose()
    }
}

Invoke-BuildProcess $executable @('--headless', '--editor', '--path', '.', '--import', '--quit') 'import' 240
Invoke-BuildProcess $executable @('--headless', '--xr-mode', 'off', '--path', '.', '--script', 'res://tools/ci/write-engine-notices.gd') 'notices' 30
Invoke-BuildProcess $executable @('--headless', '--path', '.', '--export-release', $preset, $binary) 'export' 240
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw 'Export did not create the executable.' }
$smokeBinary = $binary
if ($IsWindows -and (Test-Path -LiteralPath (Join-Path $bundle 'FrontierSystems.console.exe'))) { $smokeBinary = Join-Path $bundle 'FrontierSystems.console.exe' }
Invoke-BuildProcess $smokeBinary @('--headless', '--xr-mode', 'off', '--quit-after', '120', '--', '--host') 'smoke' 30 $true
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $bundle
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD_PARTY_NOTICES.md') -Destination $bundle
Copy-Item -LiteralPath (Join-Path $projectRoot 'var/ci/engine-notices.txt') -Destination (Join-Path $bundle 'GODOT-NOTICES.txt')
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/development/exported-build-running.md') -Destination (Join-Path $bundle 'QUICKSTART.md')
$files = @(Get-ChildItem -Recurse -File -LiteralPath $bundle | Sort-Object FullName | ForEach-Object {
    [ordered]@{ path=[IO.Path]::GetRelativePath($bundle, $_.FullName).Replace('\', '/'); bytes=$_.Length; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant() }
})
$manifest = [ordered]@{ schema_version=1; product='Frontier Systems development prototype'; platform=$Platform; revision=$Revision; godot='4.7.2'; signed=$false; smoke_test='cooperative host startup'; files=$files }
[IO.File]::WriteAllText((Join-Path $bundle 'build-manifest.json'), ($manifest | ConvertTo-Json -Depth 6))
$zip = Join-Path $output "frontier-systems-$Platform-$Revision.zip"
if (Test-Path -LiteralPath $zip) { throw 'The revision archive already exists.' }
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip
$digest = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$zip.sha256", "$digest  $([IO.Path]::GetFileName($zip))`n")
Write-Host "Built and smoke-tested $zip"
