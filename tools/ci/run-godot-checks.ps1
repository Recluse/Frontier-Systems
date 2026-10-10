param(
    [string]$Godot = 'godot',
    [string[]]$TestNames = @(),
    [int]$TestTimeoutSeconds = 120,
    [string]$OutputDirectory = 'var/ci/godot'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$executable = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source
$output = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
New-Item -ItemType Directory -Force -Path $output | Out-Null
$excluded = @{
    'event_logging_integration_test.gd' = 'Requires tools/test-event-logging.ps1 local receiver.'
    'local_profiling_upload_test.gd' = 'Requires tools/test-local-profiling.ps1 local receiver.'
    'first_playable_client_render_check.gd' = 'Requires a graphical runner; never silently substitute headless rendering.'
}
$tests = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests/godot') -Filter '*.gd' |
    Where-Object { -not $excluded.ContainsKey($_.Name) } | Sort-Object Name)
if ($TestNames.Count -gt 0) {
    foreach ($name in $TestNames) {
        if ($name -notin $tests.Name) { throw "Unknown or non-headless test: $name" }
    }
    $tests = @($tests | Where-Object { $_.Name -in $TestNames })
}
if ($tests.Count -eq 0 -or $TestTimeoutSeconds -lt 1 -or $TestTimeoutSeconds -gt 300) { throw 'Select tests and a deadline between 1 and 300 seconds.' }
$results = [Collections.Generic.List[object]]::new()

function Invoke-GodotCheck([string]$Name, [string[]]$Arguments, [int]$Deadline) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $executable
    $info.WorkingDirectory = $projectRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment['FRONTIER_EVENT_URL'] = ''
    $info.Environment['FRONTIER_EVENT_TOKEN'] = ''
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $failure = ''
    $log = ''
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw 'Process did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Deadline * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            $failure = "Deadline exceeded after $Deadline seconds."
        }
        $log = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        if ($failure -eq '' -and ($process.ExitCode -ne 0 -or $log -match '(?m)SCRIPT ERROR|(?:^|\s)ERROR:')) {
            $failure = "Exit $($process.ExitCode) or Godot error diagnostics."
        }
    } catch {
        $failure = $_.Exception.Message
    } finally {
        $watch.Stop()
        if ($started -and -not $process.HasExited) { $process.Kill($true) }
        $process.Dispose()
    }
    $log = [regex]::Replace($log, '\x1b\[[0-9;]*m', '')
    [IO.File]::WriteAllText((Join-Path $output "$Name.log"), $log)
    $results.Add([pscustomobject]@{name=$Name;seconds=$watch.Elapsed.TotalSeconds;failure=$failure;log=$log})
    if ($failure) { Write-Host "FAIL $Name - $failure"; Write-Host $log.Substring(0, [Math]::Min(4000, $log.Length)) }
    else { Write-Host "PASS $Name ($([Math]::Round($watch.Elapsed.TotalSeconds, 2))s)" }
}

try {
    Invoke-GodotCheck 'import' @('--headless', '--editor', '--path', '.', '--import', '--quit') 240
    if (-not $results[0].failure) {
        Invoke-GodotCheck 'runtime' @('--headless', '--xr-mode', 'off', '--audio-driver', 'Dummy', '--path', '.', '--quit-after', '2') 30
        foreach ($test in $tests) {
            Invoke-GodotCheck $test.BaseName @('--headless', '--xr-mode', 'off', '--audio-driver', 'Dummy', '--path', '.', '--script', "res://tests/godot/$($test.Name)") $TestTimeoutSeconds
        }
    }
} finally {
    $failures = @($results | Where-Object failure).Count
    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $writer = [Xml.XmlWriter]::Create((Join-Path $output 'junit.xml'), $settings)
    try {
        $writer.WriteStartElement('testsuite')
        $writer.WriteAttributeString('name', 'Godot')
        $writer.WriteAttributeString('tests', [string]$results.Count)
        $writer.WriteAttributeString('failures', [string]$failures)
        foreach ($result in $results) {
            $writer.WriteStartElement('testcase')
            $writer.WriteAttributeString('name', $result.name)
            $writer.WriteAttributeString('time', $result.seconds.ToString('F3', [Globalization.CultureInfo]::InvariantCulture))
            if ($result.failure) {
                $writer.WriteStartElement('failure')
                $writer.WriteAttributeString('message', $result.failure)
                $excerpt = $result.log.Substring(0, [Math]::Min(8000, $result.log.Length))
                $writer.WriteString([regex]::Replace($excerpt, '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''))
                $writer.WriteEndElement()
            }
            $writer.WriteEndElement()
        }
        $writer.WriteEndElement()
    } finally { $writer.Dispose() }
    $summary = "## Godot checks`n`n$($results.Count) checks, $failures failures. Each test has a $TestTimeoutSeconds second deadline.`n`n"
    foreach ($result in $results) { $summary += "- $(if ($result.failure) {'FAIL'} else {'PASS'}) $($result.name)`n" }
    $summary += "`nExcluded scripts:`n"
    foreach ($name in ($excluded.Keys | Sort-Object)) { $summary += "- ${name}: $($excluded[$name])`n" }
    [IO.File]::WriteAllText((Join-Path $output 'summary.md'), $summary)
    if ($env:GITHUB_STEP_SUMMARY) { [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $summary) }
}
if ($failures -gt 0) { throw "$failures Godot checks failed; see $output." }
