$ErrorActionPreference = 'Stop'
$taskSnapshot = Join-Path $PSScriptRoot 'snapshot.ps1'
$taskTemp = Join-Path ([IO.Path]::GetTempPath()) ('frontier-snapshot-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskTemp | Out-Null
try {
    $taskLedger = Join-Path $taskTemp 'ledger.md'
    $taskStateFile = Join-Path $taskTemp 'state.json'
    $taskPreviousFile = Join-Path $taskTemp 'previous.json'
    $taskEvidenceFile = Join-Path $taskTemp 'prs.json'
    $taskLedgerBytes = [Text.Encoding]::UTF8.GetBytes("# Ledger`r`n`r`n## Current`r`nNew evidence.`r`n`r`n## Historical`r`nHISTORICAL-SENTINEL`r`n")
    [IO.File]::WriteAllBytes($taskLedger, $taskLedgerBytes)
    $taskHash = (Get-FileHash -LiteralPath $taskLedger -Algorithm SHA256).Hash.ToLowerInvariant()
    $taskState = @{
        schema_version = 1; repository = 'Valgorithms/Frontier-Systems'; active_tasks = @()
        website = @{ status = 'new'; checked_at = '2026-10-10T22:00:00Z'; next_check_at = '2026-10-12T00:00:00Z' }
        fundraising = @{ last_confirmed_public_post_at = '2026-10-10T00:00:00Z'; next_monthly_due_at = '2026-11-09T00:00:00Z'; unreported_progress = $true }
        pending_approvals = @(); tutorial_gate = 'awaiting_human'; ledger_sha256 = $taskHash
    }
    function Save-TestState { $taskState | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $taskStateFile -Encoding utf8 }
    function Get-TestSnapshot([string]$Time, [string]$Previous, [string]$Evidence) {
        $taskJson = & $taskSnapshot -StatePath $taskStateFile -LedgerPath $taskLedger -NowUtc $Time -PreviousPath $Previous -PullRequestsPath $Evidence -LedgerExcerptCharacters 256
        return $taskJson | ConvertFrom-Json -AsHashtable
    }
    Save-TestState
    $taskFirst = Get-TestSnapshot '2026-10-10T22:59:00Z' '' ''
    if ($taskFirst.status -ne 'current' -or -not $taskFirst.changed -or $taskFirst.due.Count -ne 0) { throw "Fresh valid snapshot failed: $($taskFirst | ConvertTo-Json -Depth 10 -Compress)" }
    $taskFirst | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $taskPreviousFile -Encoding utf8
    $taskSame = Get-TestSnapshot '2026-10-10T22:59:30Z' $taskPreviousFile ''
    if ($taskSame.changed -or $taskSame.attention_required) { throw 'Unchanged pre-deadline state woke the coordinator.' }
    $taskPrepare = Get-TestSnapshot '2026-10-10T23:00:00Z' $taskPreviousFile ''
    if ($taskPrepare.changed -or -not $taskPrepare.attention_required -or $taskPrepare.due -notcontains 'public_post_prepare') { throw '23h deadline must wake unchanged state.' }
    $taskDaily = Get-TestSnapshot '2026-10-11T00:00:00Z' $taskPreviousFile ''
    if ($taskDaily.due -notcontains 'public_post_deadline') { throw '24h daily deadline missing.' }
    $taskMonthly = Get-TestSnapshot '2026-11-09T00:00:00Z' $taskPreviousFile ''
    if ($taskMonthly.due -notcontains 'monthly_benefits' -or $taskMonthly.due -notcontains 'website_check') { throw 'Monthly/website obligation was hidden.' }
    $taskState.website.status = 'complete'
    $taskState.website.next_check_at = $null
    Save-TestState
    $taskCompletedSite = Get-TestSnapshot '2026-11-09T00:00:00Z' '' ''
    if ($taskCompletedSite.status -ne 'current' -or $taskCompletedSite.due -contains 'website_check' -or
        @($taskCompletedSite.deadlines | Where-Object { $_.name -eq 'website_check' }).Count -ne 0 -or
        $taskCompletedSite.due -notcontains 'monthly_benefits' -or $taskCompletedSite.due -notcontains 'public_post_deadline') {
        throw 'Completed website follow-up must retire only its own deadline.'
    }
    $taskState.website.checked_at = $null
    Save-TestState
    if ((Get-TestSnapshot '2026-11-09T00:00:00Z' '' '').status -ne 'refresh_required') { throw 'Completed website still needs a verified observation timestamp.' }
    $taskState.website.checked_at = '2026-10-10T22:00:00Z'
    $taskState.website.status = 'unknown-status'
    Save-TestState
    if ((Get-TestSnapshot '2026-11-09T00:00:00Z' '' '').status -ne 'refresh_required') { throw 'Unsupported website status silently passed.' }
    $taskState.website.status = 'new'
    $taskState.website.next_check_at = '2026-10-12T00:00:00Z'
    $taskState.fundraising.last_confirmed_public_post_at = $null
    Save-TestState
    if ((Get-TestSnapshot '2026-10-10T23:00:00Z' '' '').status -ne 'refresh_required') { throw 'Unknown publication time silently passed.' }
    $taskState.fundraising.last_confirmed_public_post_at = '2026-10-12T00:00:00Z'
    Save-TestState
    if ((Get-TestSnapshot '2026-10-10T23:00:00Z' '' '').status -ne 'refresh_required') { throw 'Future publication observation silently passed.' }
    $taskState.fundraising.last_confirmed_public_post_at = '2026-10-10T00:00:00Z'
    $taskState.active_tasks = @(@{ thread_id = '00000000-0000-0000-0000-000000000001'; pr_number = 40; head_sha = ('a' * 40); scope = 'CI'; status = 'awaiting_review' })
    Save-TestState
    if ((Get-TestSnapshot '2026-10-10T23:00:00Z' '' '').status -ne 'refresh_required') { throw 'Missing PR evidence silently passed.' }
    $taskEvidence = @{
        captured_at = '2026-10-10T22:59:00Z'
        pull_requests = @(@{ number = 40; state = 'open'; draft = $true; head_sha = ('a' * 40); checks = @(@{ name = 'CI required'; head_sha = ('a' * 40); status = 'completed'; conclusion = 'success' }) })
    }
    $taskEvidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $taskEvidenceFile -Encoding utf8
    $taskWithPr = Get-TestSnapshot '2026-10-10T23:00:00Z' '' $taskEvidenceFile
    if ($taskWithPr.status -ne 'current') { throw "Valid exact-head PR evidence failed: $($taskWithPr.refresh_reasons)" }
    $taskWithPr | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $taskPreviousFile -Encoding utf8
    $taskEvidence.pull_requests[0].checks[0].conclusion = 'failure'
    $taskEvidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $taskEvidenceFile -Encoding utf8
    if (-not (Get-TestSnapshot '2026-10-10T23:00:00Z' $taskPreviousFile $taskEvidenceFile).changed) { throw 'Changed checks did not wake the coordinator.' }
    if ((Get-TestSnapshot '2026-10-10T23:15:00Z' '' $taskEvidenceFile).status -ne 'refresh_required') { throw 'Expired check evidence silently passed.' }
    $taskEvidence.pull_requests[0].head_sha = 'b' * 40
    $taskEvidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $taskEvidenceFile -Encoding utf8
    if ((Get-TestSnapshot '2026-10-10T23:00:00Z' '' $taskEvidenceFile).status -ne 'refresh_required') { throw 'Changed PR/check head silently passed.' }
    if ($taskFirst.ledger.newest_section.Contains('HISTORICAL-SENTINEL') -or $taskFirst.ledger.newest_section.Length -gt 256) { throw 'Unbounded historical output.' }
    if ((Get-FileHash -LiteralPath $taskLedger -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskHash) { throw 'Snapshot changed original ledger bytes.' }
    [IO.File]::WriteAllText($taskLedger, "# Concurrent update`n## Newest`nMore evidence.")
    if ((Get-TestSnapshot '2026-10-10T23:00:00Z' '' $taskEvidenceFile).refresh_reasons -notcontains 'ledger hash differs from active state; reconcile newest evidence') { throw 'Concurrent ledger update was missed.' }
    [IO.File]::WriteAllText($taskStateFile, '{broken')
    if ((Get-TestSnapshot '2026-10-10T23:00:00Z' '' '').status -ne 'refresh_required') { throw 'Malformed state silently passed.' }
    'Snapshot contracts passed: deadline boundaries, unchanged state, missing/future evidence, exact PR heads, stale/changed checks, bounded output, and byte-preserved ledger.'
} finally {
    $taskResolvedTemp = [IO.Path]::GetFullPath($taskTemp)
    $taskTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $taskResolvedTemp.StartsWith($taskTempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($taskResolvedTemp) -notmatch '^frontier-snapshot-[0-9a-f]{32}$') { throw 'Unexpected test cleanup path.' }
    Remove-Item -LiteralPath $taskResolvedTemp -Recurse -Force
}
