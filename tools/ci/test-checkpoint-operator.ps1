param(
    [string]$Godot = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$taskProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$taskLauncher = Join-Path $taskProject 'tools/launch-first-playable.ps1'
$taskCommon = @{ GodotPath = $Godot; CheckOnly = $true; Initialize = $true }
$taskDefault = & $taskLauncher @taskCommon -Mode Host
if ($taskDefault.BackupHistory -or $null -ne $taskDefault.BackupEntries -or $null -ne $taskDefault.BackupBytes) {
    throw 'Default launcher must disable history.'
}
$taskEnabled = & $taskLauncher @taskCommon -Mode Host -BackupHistory
if (-not $taskEnabled.BackupHistory -or $taskEnabled.BackupEntries -ne '3' -or $taskEnabled.BackupBytes -ne '33554432') {
    throw 'Enabled launcher must report default retention.'
}
$taskBounds = & $taskLauncher @taskCommon -Mode Host -BackupHistory -BackupEntries '8' -BackupBytes '67108864'
if ($taskBounds.BackupEntries -ne '8' -or $taskBounds.BackupBytes -ne '67108864') { throw 'Explicit limits lost.' }
$taskInvalid = @(
    @{ Mode = 'Client'; BackupHistory = $true },
    @{ Mode = 'Host'; BackupEntries = '1' },
    @{ Mode = 'Host'; BackupBytes = '1' },
    @{ Mode = 'Host'; BackupHistory = $true; BackupEntries = '0' },
    @{ Mode = 'Host'; BackupHistory = $true; BackupEntries = '9' },
    @{ Mode = 'Host'; BackupHistory = $true; BackupEntries = '1.5' },
    @{ Mode = 'Host'; BackupHistory = $true; BackupEntries = '01' },
    @{ Mode = 'Host'; BackupHistory = $true; BackupBytes = '0' },
    @{ Mode = 'Host'; BackupHistory = $true; BackupBytes = '67108865' },
    @{ Mode = 'Host'; BackupHistory = $true; BackupBytes = '+1' }
)
foreach ($taskCase in $taskInvalid) {
    $taskRejected = $false
    try { & $taskLauncher @taskCommon @taskCase | Out-Null } catch { $taskRejected = $true }
    if (-not $taskRejected) { throw 'Invalid launch configuration accepted.' }
}
# Invoke the native CLI with redirected output and a fixed process deadline.
# Empty disposable source cannot recover and requires no player keys/storage.
$taskTemporary = Join-Path ([IO.Path]::GetTempPath()) ('frontier-operator-cli-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskTemporary | Out-Null
try {
    $taskDescriptor = Join-Path $taskTemporary 'selected.json'
    [IO.File]::WriteAllText($taskDescriptor, '{}')
    foreach ($taskCase in @(
        @{ Args = @('list', '--source', $taskTemporary); Exit = 0; Code = '' },
        @{ Args = @('bad', '--secret', 'PRIVATE-SENTINEL'); Exit = 2; Code = 'operator_options' },
        @{ Args = @('recover', '--source', $taskTemporary, '--descriptor', (Join-Path $taskTemporary 'missing.json'), '--destination', (Join-Path $taskTemporary 'new')); Exit = 3; Code = 'save_read' },
        @{ Args = @('recover', '--source', $taskTemporary, '--descriptor', $taskDescriptor, '--destination', ($taskTemporary + '-destination')); Exit = 4; Code = 'backup_selection' }
    )) {
        $taskInfo = [Diagnostics.ProcessStartInfo]::new()
        $taskInfo.FileName = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source
        $taskInfo.WorkingDirectory = $taskProject
        $taskInfo.UseShellExecute = $false
        $taskInfo.CreateNoWindow = $true
        $taskInfo.RedirectStandardOutput = $true
        $taskInfo.RedirectStandardError = $true
        $taskInfo.Environment['FRONTIER_EVENT_URL'] = ''
        $taskInfo.Environment['FRONTIER_EVENT_TOKEN'] = ''
        foreach ($taskArgument in (@('--headless', '--xr-mode', 'off', '--audio-driver', 'Dummy', '--path', '.', '--script', 'res://tools/godot/checkpoint_operator.gd', '--') + $taskCase.Args)) {
            $taskInfo.ArgumentList.Add($taskArgument)
        }
        $taskProcess = [Diagnostics.Process]::new()
        $taskProcess.StartInfo = $taskInfo
        try {
            if (-not $taskProcess.Start()) { throw 'CLI did not start.' }
            $taskStdout = $taskProcess.StandardOutput.ReadToEndAsync()
            $taskStderr = $taskProcess.StandardError.ReadToEndAsync()
            if (-not $taskProcess.WaitForExit(30000)) { $taskProcess.Kill($true); throw 'CLI exceeded 30 second deadline.' }
            $taskOutput = $taskStdout.GetAwaiter().GetResult()
            $taskError = $taskStderr.GetAwaiter().GetResult()
            if ($taskProcess.ExitCode -ne $taskCase.Exit -or $taskError -match 'SCRIPT ERROR|ERROR:' -or $taskOutput.Contains('PRIVATE-SENTINEL')) {
                throw "Unexpected CLI exit/diagnostics: $($taskProcess.ExitCode) $taskError"
            }
            $taskJson = @($taskOutput -split '\r?\n' | Where-Object { $_.StartsWith('{') })
            if ($taskJson.Count -ne 1) { throw 'CLI must print one JSON report.' }
            $taskReport = $taskJson[0] | ConvertFrom-Json
            if ($taskReport.exit_status -ne $taskCase.Exit -or ($taskCase.Code -and $taskReport.error_code -ne $taskCase.Code)) {
                throw 'CLI report does not match process exit.'
            }
        } finally {
            if ($taskProcess.Id -and -not $taskProcess.HasExited) { $taskProcess.Kill($true) }
            $taskProcess.Dispose()
        }
    }
} finally {
    # Only known disposable paths are removed; no recursive delete or real saves.
    Remove-Item -LiteralPath (Join-Path $taskTemporary 'selected.json') -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $taskTemporary
}
Write-Host 'PASS checkpoint launcher: default opt-out, strict options, metadata-only check configuration; bounded native CLI JSON and exits 0/2/3/4.'