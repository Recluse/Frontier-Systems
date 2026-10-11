$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ci-policy.ps1')
$taskCases = @(
    @{ Event = 'pull_request'; Paths = @('README.md', 'docs/development/milestone-coordination.md'); Scope = 'docs' },
    @{ Event = 'pull_request'; Paths = @('docs/design/nested/design-notes.md'); Scope = 'docs' },
    @{ Event = 'push'; Paths = @('README.md'); Scope = 'full' },
    @{ Event = 'merge_group'; Paths = @('README.md'); Scope = 'full' },
    @{ Event = 'workflow_dispatch'; Paths = @('README.md'); Scope = 'full' },
    @{ Event = 'pull_request'; Paths = @(); Scope = 'full' }
)
foreach ($taskPath in @(
    'docs/schema/README.md', 'docs/schema/world.json', 'src/world.gd', 'packages/world/README.md',
    'services/control-plane/composer.lock', '.github/workflows/ci.yml', 'tools/ci/ci-policy.ps1',
    'AGENTS.md', 'LICENSE', 'QUICKSTART.md', 'docs/gallery/capture.png', 'docs/new-area/notes.md',
    'docs/development/../schema/README.md', 'docs/development/note.md.gd', "docs/development/bad`nname.md",
    'docs/development/CODE.MD', 'docs/development/status.json', 'project.godot'
)) {
    $taskCases += @{ Event = 'pull_request'; Paths = @('README.md', $taskPath); Scope = 'full' }
}
foreach ($taskCase in $taskCases) {
    if ((Get-CiScope -EventName $taskCase.Event -Paths $taskCase.Paths) -ne $taskCase.Scope) {
        throw "Incorrect CI scope: $($taskCase | ConvertTo-Json -Compress)"
    }
}
$taskJobs = @('changes', 'php-quality', 'php-packages', 'godot-import', 'game-export')
foreach ($taskScope in @('full', 'docs')) {
    $taskResults = @{}
    foreach ($taskJob in $taskJobs) {
        $taskResults[$taskJob] = @{ result = $(if ($taskJob -eq 'changes' -or $taskScope -eq 'full') { 'success' } else { 'skipped' }) }
    }
    Assert-CiResults -Scope $taskScope -Results $taskResults
    foreach ($taskJob in $taskJobs) {
        $taskGood = $taskResults[$taskJob].result
        foreach ($taskBad in @('failure', 'cancelled', 'pending', $(if ($taskGood -eq 'success') { 'skipped' } else { 'success' }))) {
            $taskResults[$taskJob].result = $taskBad
            $taskRejected = $false
            try { Assert-CiResults -Scope $taskScope -Results $taskResults } catch { $taskRejected = $true }
            if (-not $taskRejected) { throw "Gate accepted $taskScope/$taskJob/$taskBad" }
        }
        $taskResults[$taskJob].result = $taskGood
    }
}
foreach ($taskScope in @('', 'unknown')) {
    $taskRejected = $false
    try { Assert-CiResults -Scope $taskScope -Results @{} } catch { $taskRejected = $true }
    if (-not $taskRejected) { throw 'Gate accepted an absent classification.' }
}
$taskWorkflow = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../.github/workflows/ci.yml') -Raw
if ($taskWorkflow -notmatch '(?m)^  push:\r?\n    branches:\r?\n      - dev-master\r?$' -or
    $taskWorkflow -notmatch '(?m)^  merge_group:\r?$' -or
    $taskWorkflow -notmatch '(?m)^    name: CI required\r?$' -or
    $taskWorkflow -match '(?m)^    paths(?:-ignore)?:') { throw 'CI trigger/gate contract changed.' }
$taskClassifier = Join-Path $PSScriptRoot 'classify-changes.ps1'
$taskTemp = Join-Path ([IO.Path]::GetTempPath()) ('frontier-ci-policy-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskTemp | Out-Null
$taskOldOutput = $env:GITHUB_OUTPUT
$taskOldSummary = $env:GITHUB_STEP_SUMMARY
Push-Location -LiteralPath $taskTemp
try {
    $env:GITHUB_OUTPUT = ''
    $env:GITHUB_STEP_SUMMARY = ''
    function Invoke-TestGit {
        $taskResult = & git -c user.name='CI policy fixture' -c user.email='fixture@example.invalid' @args
        if ($LASTEXITCODE -ne 0) { throw 'Git fixture command failed.' }
        return $taskResult
    }
    Invoke-TestGit init --quiet | Out-Null
    New-Item -ItemType Directory -Path 'src', 'docs/development' -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $taskTemp 'README.md'), 'Before')
    [IO.File]::WriteAllText((Join-Path $taskTemp 'src/runtime.gd'), 'runtime')
    Invoke-TestGit add . | Out-Null
    Invoke-TestGit commit --quiet -m 'Initial fixture' | Out-Null
    $taskBase = Invoke-TestGit rev-parse HEAD
    [IO.File]::WriteAllText((Join-Path $taskTemp 'README.md'), 'After')
    Invoke-TestGit add . | Out-Null
    Invoke-TestGit commit --quiet -m 'Prose change' | Out-Null
    $taskHead = Invoke-TestGit rev-parse HEAD
    if ((& $taskClassifier -EventName pull_request -BaseSha $taskBase -HeadSha $taskHead) -ne 'docs') { throw 'Actual prose diff did not classify as docs.' }
    Invoke-TestGit mv src/runtime.gd docs/development/moved.md | Out-Null
    Invoke-TestGit commit --quiet -am 'Move runtime into prose path' | Out-Null
    $taskHead = Invoke-TestGit rev-parse HEAD
    if ((& $taskClassifier -EventName pull_request -BaseSha $taskBase -HeadSha $taskHead) -ne 'full') { throw 'Runtime rename escaped full validation.' }
    $taskRejected = $false
    try { & $taskClassifier -EventName pull_request -BaseSha 'missing' -HeadSha $taskHead | Out-Null } catch { $taskRejected = $true }
    if (-not $taskRejected) { throw 'Absent immutable comparison was accepted.' }
} finally {
    Pop-Location
    $env:GITHUB_OUTPUT = $taskOldOutput
    $env:GITHUB_STEP_SUMMARY = $taskOldSummary
    $taskResolvedTemp = [IO.Path]::GetFullPath($taskTemp)
    if (-not $taskResolvedTemp.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($taskResolvedTemp) -notmatch '^frontier-ci-policy-[0-9a-f]{32}$') { throw 'Unexpected fixture cleanup path.' }
    Remove-Item -LiteralPath $taskResolvedTemp -Recurse -Force
}
"CI policy contracts passed: $($taskCases.Count) classification cases, actual Git prose/rename diffs, and every required-job failure/cancellation/skip permutation."
