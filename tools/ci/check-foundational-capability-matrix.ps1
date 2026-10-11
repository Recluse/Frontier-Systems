[CmdletBinding()]
param()

# Read-only documentation validation; does not run gameplay or certify parity.
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$matrixPath = Join-Path $repositoryRoot 'docs/research/foundational-capability-matrix.v1.csv'
$milestonePath = Join-Path $repositoryRoot 'docs/development/foundational-capability-matrix-milestone.md'
$manifestPath = Join-Path $repositoryRoot 'docs/research/reference-manifest.csv'
$rows = @(Import-Csv -LiteralPath $matrixPath)
$manifest = @(Import-Csv -LiteralPath $manifestPath)
$milestone = Get-Content -LiteralPath $milestonePath -Raw
$expectedColumns = @('matrix_version', 'capability_id', 'reference_keys', 'player_action_outcome',
    'frontier_owner', 'dependencies', 'status', 'frontier_evidence', 'acceptance_requirement',
    'gap', 'decision_state')
$statuses = @('unresearched', 'planned', 'implementing', 'verified',
    'exclusion proposed', 'exclusion owner-approved')
$decisions = @('pending', 'owner-approved')
if ($rows.Count -eq 0) { throw 'The matrix must contain capability rows.' }
if (($rows[0].PSObject.Properties.Name -join ',') -cne ($expectedColumns -join ',')) {
    throw 'Matrix v1 columns differ from the documented contract.'
}
$ids = @{}
foreach ($row in $rows) {
    foreach ($column in $expectedColumns) {
        if ([string]::IsNullOrWhiteSpace($row.$column)) {
            throw "Empty field $column for $($row.capability_id)."
        }
    }
    if ($row.matrix_version -cne '1' -or $row.capability_id -cnotmatch '^foundation\.[a-z]+(?:-[a-z]+)*$') {
        throw "Invalid version or stable ID: $($row.capability_id)."
    }
    if ($ids.ContainsKey($row.capability_id)) { throw "Duplicate ID: $($row.capability_id)." }
    $ids[$row.capability_id] = $true
    if ($row.status -cnotin $statuses -or $row.decision_state -cnotin $decisions) {
        throw "Unknown status or decision state: $($row.capability_id)."
    }
    # This baseline contains static pointers only; promotion requires a new evidence contract.
    if ($row.status -ceq 'verified') { throw 'Baseline v1 has no executable acceptance evidence for verified status.' }
    if ($row.status -ceq 'exclusion owner-approved' -and $row.decision_state -cne 'owner-approved') {
        throw 'An approved exclusion needs an approved decision.'
    }
    foreach ($key in $row.reference_keys.Split(';')) {
        if ($key -cnotmatch '^(C[1-4]|T[1-3]|H1)$' -or -not $milestone.Contains("| $key |")) {
            throw "Missing source-key declaration: $key."
        }
    }
}
foreach ($row in $rows) {
    foreach ($entry in (($row.dependencies + ';' + $row.frontier_evidence).Split(';'))) {
        if ($entry.StartsWith('foundation.', [StringComparison]::Ordinal)) {
            if (-not $ids.ContainsKey($entry) -or $entry -ceq $row.capability_id) {
                throw "Unresolved or self dependency: $entry."
            }
        } else {
            $resolved = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $entry))
            if (-not $resolved.StartsWith($repositoryRoot + [IO.Path]::DirectorySeparatorChar,
                    [StringComparison]::OrdinalIgnoreCase) -or
                    -not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                throw "Missing or out-of-repository evidence path: $entry."
            }
        }
    }
}
$sources = @(
    @('Civ13', 'code/game/mob/inventory.dm', '0d38999d5f9f987a944493f11c456537f39ac2f6'),
    @('Civ13', 'code/game/mob/living/carbon/human/inventory.dm', '0d38999d5f9f987a944493f11c456537f39ac2f6'),
    @('Civ13', 'code/game/objects/items/stacks/stack.dm', '0d38999d5f9f987a944493f11c456537f39ac2f6'),
    @('Civ13', 'code/game/objects/structures/repairing.dm', '0d38999d5f9f987a944493f11c456537f39ac2f6'),
    @('tgstation', 'code/modules/mob/inventory.dm', 'ab176e0dfd1ee1a1a97e9546bad0b9c4e3ff78b1'),
    @('tgstation', 'code/_onclick/item_attack.dm', 'ab176e0dfd1ee1a1a97e9546bad0b9c4e3ff78b1'),
    @('tgstation', 'code/game/objects/items/stacks/stack.dm', 'ab176e0dfd1ee1a1a97e9546bad0b9c4e3ff78b1')
)
foreach ($source in $sources) {
    $matches = @($manifest | Where-Object {
        $_.project -ceq $source[0] -and
        $_.exact_reference_path.StartsWith($source[1] + ' (', [StringComparison]::Ordinal) -and
        $_.revision_or_commit -ceq $source[2]
    })
    if ($matches.Count -ne 1 -or [string]::IsNullOrWhiteSpace($matches[0].allowed_use_and_restrictions)) {
        throw "Missing unique pinned manifest entry or rights limits: $($source[1])."
    }
    $sourceUrl = "$($matches[0].repository_or_page)/blob/$($source[2])/$($source[1])"
    if (-not $milestone.Contains($sourceUrl)) { throw "Missing pinned source link: $sourceUrl." }
}
Write-Output "Documentation baseline validated: $($rows.Count) unique capabilities, 7 pinned source excerpts, local evidence and dependency paths. Runtime verification not performed."
