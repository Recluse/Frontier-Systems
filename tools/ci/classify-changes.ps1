param(
    [string]$EventName = $env:GITHUB_EVENT_NAME,
    [string]$BaseSha = $env:PR_BASE_SHA,
    [string]$HeadSha = $env:PR_HEAD_SHA
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ci-policy.ps1')
$taskPaths = @()
if ($EventName -eq 'pull_request') {
    if ($BaseSha -cnotmatch '\A[0-9a-f]{40}\z' -or $HeadSha -cnotmatch '\A[0-9a-f]{40}\z') {
        throw 'Pull request comparison requires immutable base and head SHAs.'
    }
    # Full checkout history makes the actual PR merge base available. --no-renames
    # includes both sides of a rename so moving runtime code into docs stays full.
    $taskDiff = @(git -c core.quotepath=false diff --name-only --no-renames -z "$BaseSha...$HeadSha" --)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot classify the pull request diff.' }
    $taskPaths = @(($taskDiff -join "`n").Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))
}
$taskScope = Get-CiScope -EventName $EventName -Paths $taskPaths
if ($env:GITHUB_OUTPUT) { "scope=$taskScope" >> $env:GITHUB_OUTPUT }
if ($env:GITHUB_STEP_SUMMARY) {
    "CI scope: **$taskScope** ($($taskPaths.Count) changed paths; event $EventName)." >> $env:GITHUB_STEP_SUMMARY
}
$taskScope
