#requires -Version 7.5
param(
    [Parameter(Mandatory)][string]$StatePath,
    [string]$LedgerPath = (Join-Path $PSScriptRoot '../../docs/development/milestone-coordination.md'),
    [string]$PreviousPath,
    [string]$PullRequestsPath,
    [DateTimeOffset]$NowUtc = [DateTimeOffset]::UtcNow,
    [ValidateRange(1, 60)][int]$EvidenceMaxAgeMinutes = 15,
    [ValidateRange(256, 8192)][int]$LedgerExcerptCharacters = 4096
)
$ErrorActionPreference = 'Stop'
$taskRefresh = [Collections.Generic.List[string]]::new()
$taskNow = $NowUtc.ToUniversalTime()

function Read-SnapshotJson([string]$Path, [string]$Label) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $taskRefresh.Add("${Label}: missing; refresh required")
        return $null
    }
    try {
        if ((Get-Item -LiteralPath $Path).Length -gt 1048576) { throw 'exceeds 1 MiB' }
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -DateKind String -ErrorAction Stop
    } catch {
        $taskRefresh.Add("${Label}: invalid JSON or oversized input; refresh required")
        return $null
    }
}

function Read-SnapshotTime($Value, [string]$Label, [switch]$Past) {
    $taskTime = [DateTimeOffset]::MinValue
    if ($Value -isnot [string] -or $Value -cnotmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})\z' -or
        -not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$taskTime)) {
        $taskRefresh.Add("${Label}: missing/invalid timestamp; refresh required")
        return $null
    }
    if ($Past -and $taskTime -gt $taskNow) {
        $taskRefresh.Add("${Label}: future observation; refresh required")
        return $null
    }
    return $taskTime.ToUniversalTime()
}

function Get-SnapshotHash([string]$Value) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Get-CanonicalJson($Value) {
    # A fixed serializer shape for state; object-key order must not cause wakes.
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [Collections.IDictionary]) {
        $taskFields = foreach ($taskKey in @($Value.Keys | Sort-Object -CaseSensitive)) {
            ($taskKey | ConvertTo-Json -Compress) + ':' + (Get-CanonicalJson $Value[$taskKey])
        }
        return '{' + ($taskFields -join ',') + '}'
    }
    if ($Value -is [array]) {
        return '[' + ((@($Value | ForEach-Object { Get-CanonicalJson $_ })) -join ',') + ']'
    }
    return ConvertTo-Json -InputObject $Value -Compress -Depth 20
}

$taskState = Read-SnapshotJson $StatePath 'active state'
if ($taskState -isnot [Collections.IDictionary]) { $taskState = @{} }
if ($taskState.schema_version -ne 1 -or $taskState.repository -ne 'Valgorithms/Frontier-Systems') {
    $taskRefresh.Add('active state: unsupported schema/repository; refresh required')
}
foreach ($taskKey in @('active_tasks', 'website', 'fundraising', 'pending_approvals', 'tutorial_gate', 'ledger_sha256')) {
    if (-not $taskState.Contains($taskKey)) { $taskRefresh.Add("active state: missing $taskKey; refresh required") }
}
if ($taskState.active_tasks -isnot [array] -or $taskState.pending_approvals -isnot [array] -or
    $taskState.website -isnot [Collections.IDictionary] -or $taskState.fundraising -isnot [Collections.IDictionary] -or
    $taskState.tutorial_gate -notin @('open', 'awaiting_human', 'accepted')) {
    $taskRefresh.Add('active state: invalid task/obligation shape; refresh required')
}
$taskWebsite = if ($taskState.website -is [Collections.IDictionary]) { $taskState.website } else { @{} }
$taskFundraising = if ($taskState.fundraising -is [Collections.IDictionary]) { $taskState.fundraising } else { @{} }
if ($taskWebsite.status -cnotin @('new', 'pending', 'blocked', 'complete', 'refresh_required') -or
    -not $taskWebsite.Contains('next_check_at') -or $taskFundraising.unreported_progress -isnot [bool]) {
    $taskRefresh.Add('active state: unsupported website status, missing next_check_at or explicit unreported_progress; refresh required')
}
$taskWebsiteChecked = Read-SnapshotTime $taskWebsite.checked_at 'website.checked_at' -Past
$taskWebsiteComplete = $taskWebsite.status -ceq 'complete'
$taskWebsiteNext = $null
if ($taskWebsiteComplete) {
    if ($null -ne $taskWebsite.next_check_at) { $taskRefresh.Add('completed website follow-up must have null next_check_at; refresh required') }
} else {
    $taskWebsiteNext = Read-SnapshotTime $taskWebsite.next_check_at 'website.next_check_at'
    if ($taskWebsite.status -ceq 'refresh_required') { $taskRefresh.Add('website status requires a fresh observation') }
}
if ($null -ne $taskWebsiteChecked -and $null -ne $taskWebsiteNext -and $taskWebsiteNext -lt $taskWebsiteChecked) {
    $taskRefresh.Add('website: next check precedes observation; refresh required')
}
$taskLastPost = Read-SnapshotTime $taskFundraising.last_confirmed_public_post_at 'fundraising.last_confirmed_public_post_at' -Past
$taskMonthly = Read-SnapshotTime $taskFundraising.next_monthly_due_at 'fundraising.next_monthly_due_at'
$taskDeadlines = @()
$taskDeadlineCandidates = @()
if (-not $taskWebsiteComplete) { $taskDeadlineCandidates += @{ Name = 'website_check'; At = $taskWebsiteNext } }
$taskDeadlineCandidates += @(
    @{ Name = 'public_post_prepare'; At = $(if ($null -ne $taskLastPost) { $taskLastPost.AddHours(23) } else { $null }) },
    @{ Name = 'public_post_deadline'; At = $(if ($null -ne $taskLastPost) { $taskLastPost.AddHours(24) } else { $null }) },
    @{ Name = 'monthly_benefits'; At = $taskMonthly }
)
foreach ($taskDeadline in $taskDeadlineCandidates) {
    $taskDeadlines += [ordered]@{
        name = $taskDeadline.Name
        at = $(if ($null -ne $taskDeadline.At) { $taskDeadline.At.ToString('o') } else { $null })
        due = $(if ($null -ne $taskDeadline.At) { $taskDeadline.At -le $taskNow } else { $null })
    }
}

$taskLedgerHash = $null
$taskLedgerSection = $null
if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) {
    # Read bytes once: evidence hash and excerpt refer to the same snapshot.
    $taskLedgerBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $LedgerPath))
    $taskLedgerHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskLedgerBytes)).ToLowerInvariant()
    $taskLedgerText = [Text.Encoding]::UTF8.GetString($taskLedgerBytes)
    $taskSection = [regex]::Match($taskLedgerText, '(?ms)^## .+?(?=^## |\z)').Value
    $taskLedgerSection = $taskSection.Substring(0, [Math]::Min($taskSection.Length, $LedgerExcerptCharacters))
    if ($taskLedgerHash -cne $taskState.ledger_sha256) { $taskRefresh.Add('ledger hash differs from active state; reconcile newest evidence') }
} else { $taskRefresh.Add('ledger missing; refresh required') }

$taskTasks = @()
foreach ($taskActive in @($taskState.active_tasks)) {
    if ($null -eq $taskActive) { continue }
    if ($taskActive -isnot [Collections.IDictionary] -or $taskActive.thread_id -cnotmatch '\A[0-9a-f-]{36}\z' -or
        [string]::IsNullOrWhiteSpace($taskActive.scope) -or [string]::IsNullOrWhiteSpace($taskActive.status) -or
        ($null -ne $taskActive.pr_number -and ($taskActive.pr_number -isnot [long] -and $taskActive.pr_number -isnot [int] -or $taskActive.pr_number -le 0)) -or
        ($null -ne $taskActive.pr_number -and $taskActive.head_sha -cnotmatch '\A[0-9a-f]{40}\z')) {
        $taskRefresh.Add('active task has missing/invalid identity, scope, status or PR head; refresh required')
        continue
    }
    $taskTasks += [ordered]@{ thread_id = $taskActive.thread_id; pr_number = $taskActive.pr_number; head_sha = $taskActive.head_sha; scope = $taskActive.scope; status = $taskActive.status }
}
$taskPrEvidence = @()
if (@($taskTasks | Where-Object { $null -ne $_.pr_number }).Count -gt 0 -or $PullRequestsPath) {
    $taskCaptured = Read-SnapshotJson $PullRequestsPath 'PR/check evidence'
    if ($taskCaptured -isnot [Collections.IDictionary]) { $taskCaptured = @{} }
    $taskCapturedAt = Read-SnapshotTime $taskCaptured.captured_at 'PR/check evidence.captured_at' -Past
    if ($null -ne $taskCapturedAt -and $taskCapturedAt.AddMinutes($EvidenceMaxAgeMinutes) -lt $taskNow) {
        $taskRefresh.Add('PR/check evidence expired; refresh required')
    }
    if ($taskCaptured.pull_requests -isnot [array]) { $taskRefresh.Add('PR/check evidence missing pull_requests array; refresh required') }
    foreach ($taskActive in @($taskTasks | Where-Object { $null -ne $_.pr_number })) {
        $taskMatches = @($taskCaptured.pull_requests | Where-Object { $_.number -eq $taskActive.pr_number })
        if ($taskMatches.Count -ne 1) { $taskRefresh.Add("PR #$($taskActive.pr_number): missing/duplicate evidence; refresh required"); continue }
        $taskPr = $taskMatches[0]
        if ($taskPr.head_sha -cne $taskActive.head_sha) { $taskRefresh.Add("PR #$($taskActive.pr_number): head changed; review new immutable head") }
        if ($taskPr.state -notin @('open', 'closed') -or $taskPr.draft -isnot [bool] -or $taskPr.checks -isnot [array]) {
            $taskRefresh.Add("PR #$($taskActive.pr_number): invalid state/check evidence; refresh required")
        }
        $taskChecks = @()
        foreach ($taskCheck in @($taskPr.checks)) {
            if ($null -eq $taskCheck) { continue }
            if ($taskCheck.head_sha -cne $taskPr.head_sha -or [string]::IsNullOrWhiteSpace($taskCheck.name) -or
                $taskCheck.status -notin @('queued', 'in_progress', 'completed') -or
                ($taskCheck.status -eq 'completed' -and $taskCheck.conclusion -notin @('success', 'failure', 'neutral', 'cancelled', 'skipped', 'timed_out', 'action_required', 'stale', 'startup_failure'))) {
                $taskRefresh.Add("PR #$($taskActive.pr_number): invalid or nonmatching check evidence; refresh required")
            }
            $taskChecks += [ordered]@{ name = $taskCheck.name; head_sha = $taskCheck.head_sha; status = $taskCheck.status; conclusion = $taskCheck.conclusion }
        }
        if (@($taskChecks | Where-Object { $_.name -ceq 'CI required' }).Count -eq 0) { $taskRefresh.Add("PR #$($taskActive.pr_number): CI required evidence missing; refresh required") }
        $taskPrEvidence += [ordered]@{ number = $taskPr.number; head_sha = $taskPr.head_sha; state = $taskPr.state; draft = $taskPr.draft; checks = @($taskChecks | Sort-Object { $_.name }, { $_.head_sha }, { $_.status }, { $_.conclusion }) }
    }
}
$taskFingerprint = Get-SnapshotHash (Get-CanonicalJson ([ordered]@{
    state = $taskState; ledger_sha256 = $taskLedgerHash; pull_requests = @($taskPrEvidence | Sort-Object { $_.number })
}))
$taskPrevious = if ($PreviousPath) { Read-SnapshotJson $PreviousPath 'previous snapshot' } else { $null }
$taskPreviousHash = if ($taskPrevious -is [Collections.IDictionary]) { $taskPrevious.fingerprint } else { $null }
$taskChanged = $taskPreviousHash -cne $taskFingerprint
$taskReasons = @($taskRefresh | Sort-Object -Unique)
$taskDue = @($taskDeadlines | Where-Object { $_.due -eq $true } | ForEach-Object { $_.name })
[ordered]@{
    schema_version = 1
    generated_at = $taskNow.ToString('o')
    status = $(if ($taskReasons.Count -gt 0) { 'refresh_required' } else { 'current' })
    fingerprint = $taskFingerprint
    changed = $taskChanged
    attention_required = ($taskChanged -or $taskReasons.Count -gt 0 -or $taskDue.Count -gt 0 -or @($taskState.pending_approvals).Count -gt 0)
    refresh_reasons = $taskReasons
    due = $taskDue
    deadlines = $taskDeadlines
    active_tasks = $taskTasks
    pull_requests = $taskPrEvidence
    pending_approvals = @($taskState.pending_approvals)
    tutorial_gate = $taskState.tutorial_gate
    unreported_progress = $taskFundraising.unreported_progress
    ledger = [ordered]@{ sha256 = $taskLedgerHash; newest_section = $taskLedgerSection; excerpt_limit = $LedgerExcerptCharacters }
} | ConvertTo-Json -Depth 20
