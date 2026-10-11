# Shared by CI classification, its aggregate gate, and offline contract checks.
function Get-CiScope {
    param([string]$EventName, [string[]]$Paths = @())
    # Integration/manual builds must continue producing release artifacts.
    if ($EventName -ne 'pull_request' -or $Paths.Count -eq 0) { return 'full' }
    foreach ($taskPath in $Paths) {
        # Deliberately narrow: schemas, media, policies, workflows, tooling and
        # unrecognized paths always run the complete matrix. Do not normalize
        # unusual Git path names into an allowed path.
        if ($taskPath -cmatch '\A(?:README\.md|docs/(?:architecture|community|design|development|fundraising|research)/[A-Za-z0-9_./ -]+\.md)\z' -and
            $taskPath -cnotmatch '(?:\A|/)\.{1,2}(?:/|\z)') { continue }
        return 'full'
    }
    return 'docs'
}

function Assert-CiResults {
    param([string]$Scope, [System.Collections.IDictionary]$Results)
    $taskExpected = @('changes', 'php-quality', 'php-packages', 'godot-import', 'game-export')
    if ($Scope -notin @('full', 'docs')) { throw 'Missing or invalid CI scope.' }
    if ($Results.Count -ne $taskExpected.Count) { throw 'Unexpected required-job set.' }
    foreach ($taskJob in $taskExpected) {
        if (-not $Results.Contains($taskJob)) { throw "Missing required job: $taskJob" }
        $taskWanted = if ($taskJob -eq 'changes' -or $Scope -eq 'full') { 'success' } else { 'skipped' }
        if ($Results[$taskJob].result -ne $taskWanted) {
            throw "Required gate $taskJob ended as $($Results[$taskJob].result), expected $taskWanted for $Scope."
        }
    }
}
