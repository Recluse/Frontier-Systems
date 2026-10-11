param(
    [ValidateSet('Host', 'Client')][string]$Mode = 'Client',
    [ValidateRange(1, 2)][int]$Slot = 1,
    [string]$GodotPath = 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [string]$HostUrl = 'ws://127.0.0.1:27840',
    [string]$InviteFile,
    [ValidatePattern('^[A-Za-z0-9_-]{1,64}$')][string]$WorldName = 'main',
    [switch]$BackupHistory,
    [ValidateScript({ $_ -cmatch '^[1-9][0-9]{0,7}$' -and [long]$_ -le 8 })][string]$BackupEntries = '3',
    [ValidateScript({ $_ -cmatch '^[1-9][0-9]{0,7}$' -and [long]$_ -le 67108864 })][string]$BackupBytes = '33554432',
    [switch]$Initialize,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
if (($BackupHistory -or $PSBoundParameters.ContainsKey('BackupEntries') -or $PSBoundParameters.ContainsKey('BackupBytes')) -and $Mode -ne 'Host') {
    throw 'Backup history options require -Mode Host.'
}
if (-not $BackupHistory -and ($PSBoundParameters.ContainsKey('BackupEntries') -or $PSBoundParameters.ContainsKey('BackupBytes'))) {
    throw 'Explicit history bounds require -BackupHistory.'
}
$playableProjectPath = Split-Path -Parent $PSScriptRoot
$playableLocalPath = Join-Path $playableProjectPath 'config/local/first-playable'
$playableKeysPath = Join-Path $playableLocalPath 'invites.json'
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Supply the full path to an installed Godot executable.'
}
if ($Initialize -and -not $CheckOnly) {
    New-Item -ItemType Directory -Path $playableLocalPath -Force | Out-Null
    if (-not (Test-Path -LiteralPath $playableKeysPath)) {
        $playableRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $playableBytesOne = New-Object byte[] 32
            $playableBytesTwo = New-Object byte[] 32
            $playableRng.GetBytes($playableBytesOne)
            $playableRng.GetBytes($playableBytesTwo)
            $playableKeys = @{ player_one = [Convert]::ToBase64String($playableBytesOne); player_two = [Convert]::ToBase64String($playableBytesTwo) }
            [System.IO.File]::WriteAllText($playableKeysPath, ($playableKeys | ConvertTo-Json))
        } finally {
            $playableRng.Dispose()
        }
    }
}
$playableArguments = @('--path', $playableProjectPath, '--xr-mode', 'off', 'res://scenes/first_playable.tscn')
if ($Mode -eq 'Host') {
    $playableArguments = @('--headless') + $playableArguments + @('--', '--host')
}
if ($CheckOnly) {
    [pscustomobject]@{ Executable = $GodotPath; Arguments = $playableArguments; Mode = $Mode; Slot = $Slot; HostUrl = $HostUrl; BackupHistory = [bool]$BackupHistory; BackupEntries = $(if ($BackupHistory) { $BackupEntries } else { $null }); BackupBytes = $(if ($BackupHistory) { $BackupBytes } else { $null }); SaveDirectory = (Join-Path $playableLocalPath "worlds/$WorldName") }
    return
}
if ($Mode -eq 'Client' -and -not [string]::IsNullOrEmpty($InviteFile)) {
    $env:FRONTIER_INVITE_KEY = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $InviteFile)).Trim()
} else {
    if (-not (Test-Path -LiteralPath $playableKeysPath -PathType Leaf)) {
        throw 'Initialize operator keys once with -Mode Host -Initialize, or provide a client-only -InviteFile.'
    }
    $playableKeys = Get-Content -LiteralPath $playableKeysPath -Raw | ConvertFrom-Json
    if ($Mode -eq 'Host') {
        $env:FRONTIER_PLAYER_ONE_KEY = $playableKeys.player_one
        $env:FRONTIER_PLAYER_TWO_KEY = $playableKeys.player_two
        $env:FRONTIER_SAVE_DIRECTORY = Join-Path $playableLocalPath "worlds/$WorldName"
    } else {
        $env:FRONTIER_INVITE_KEY = if ($Slot -eq 1) { $playableKeys.player_one } else { $playableKeys.player_two }
    }
}
$env:FRONTIER_HOST_URL = $HostUrl
# Scope backup settings to this child launch, including explicit opt-out when inherited.
$playablePreviousEntries = [Environment]::GetEnvironmentVariable('FRONTIER_BACKUP_ENTRIES', 'Process')
$playablePreviousBytes = [Environment]::GetEnvironmentVariable('FRONTIER_BACKUP_BYTES', 'Process')
try {
    $env:FRONTIER_BACKUP_ENTRIES = if ($Mode -eq 'Host' -and $BackupHistory) { $BackupEntries } else { '' }
    $env:FRONTIER_BACKUP_BYTES = if ($Mode -eq 'Host' -and $BackupHistory) { $BackupBytes } else { '' }
    & $GodotPath @playableArguments
    $playableExit = $LASTEXITCODE
} finally {
    [Environment]::SetEnvironmentVariable('FRONTIER_BACKUP_ENTRIES', $playablePreviousEntries, 'Process')
    [Environment]::SetEnvironmentVariable('FRONTIER_BACKUP_BYTES', $playablePreviousBytes, 'Process')
}
exit $playableExit
