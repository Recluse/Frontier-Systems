# CI and development delivery

## Required checks

`.github/workflows/ci.yml` runs for pushes to `dev-master`, pull requests to `dev-master`, merge queue groups and manual dispatch. Feature branches validate through their pull request, avoiding duplicate push and PR matrices. Configure repository branch/ruleset protection to require **CI required**. Workflow files alone do not configure repository branch protection; inspection on 2026-10-11 found no protection or effective rules on `dev-master`.

The always-reporting **Classify CI scope** job compares immutable PR base/head commits using the actual merge base. Only `README.md` and Markdown prose under the explicitly listed architecture, community, design, development, fundraising and research documentation directories can take the cheap PR route. Every other path, including schema documents, JSON, workflows, policies, tools, media and unknown paths, runs the full matrix. Renames include both paths; empty/unknown event diffs default to full validation. A missing or failed comparison fails the required gate. There are no workflow-level path filters that leave a required check pending.

For prose-only PRs, **CI required** requires a successful classifier and verifies that all runtime/export jobs were intentionally skipped. That result establishes documentation classification only, with no runtime or build acceptance. All other runs require every quality, integration and export job to succeed; failure, cancellation or an unexpected skip fails the aggregate. Pushes to `dev-master`, merge groups and manual dispatch always run the full matrix, preserving release artifacts and merge-queue evidence. Existing focused schema/terrain workflows retain their path filters and contracts.

- PHP quality covers 8.3 on Windows/Linux and 8.5 on Linux: locked installation, PSR-4, Windows runtime policy, formatting, unit suites, audit, Linux API docs and production PHAR builds on both operating systems.
- Package validation discovers every `packages/*/composer.json`, including foundation/world contracts. Two platform jobs replace the earlier ten package jobs. Package libraries without lock files intentionally resolve their declared production dependency constraints; the control-plane application remains locked.
- Godot checks run on Windows/Linux. `tools/ci/run-godot-checks.ps1` discovers test scripts, imports the editor, starts the client-independent runtime, and runs each headless test with a deadline. It detects both nonzero exits and Godot `ERROR:`/`SCRIPT ERROR` output, since parse failures can otherwise hang or exit successfully. Tests continue after individual failures for complete diagnostics.
- Local profiling and event HTTP receiver integrations run separately. Their special Godot scripts and the graphical client render script are explicitly excluded from direct discovery. New standalone scripts are picked up automatically. Unknown selected names fail.
- Native Windows/Linux development exports depend on all previous gates. Godot 4.7.2 templates are installed only for export jobs. Each packaged executable must start the cooperative headless host using temporary invites/saves; missing runtime catalogs, entrypoint or native dependencies fail the build.

Existing graphical and Quest 3 checks still require suitable hardware. Packaged-host startup does not establish graphical, Steam or VR release readiness.

## Artifacts, caching and deadlines

All action implementations are pinned to reviewed commit SHAs; Dependabot proposes updates. Composer caches contain download archives, not installed vendors, compiled Godot state, world saves or credentials. Each run still resolves/installs and validates its dependencies. Cancellation supersedes older runs for the same branch/PR. Job deadlines prevent a broken tool from occupying a runner indefinitely.

Three-day artifact retention limits storage cost. Download useful builds/evidence before they expire:

| Artifact | Contents |
| --- | --- |
| `godot-tests-{os}` | Per-process logs, JUnit XML, summary, explicit exclusions |
| `php-tests-{os}-{version}` | Control-plane, event logging and Twitch JUnit results |
| `php-api-docs` | Generated PHPDocumentor API docs |
| `control-plane-{os}` | Production-only PHAR |
| `export-diagnostics-{platform}` | Import, export and packaged-host logs |
| `game-{platform}-{sha}` | ZIP and SHA-256 checksum; package contains licenses, quickstart and file/revision manifest |

The Godot runner disables inherited Discord event delivery. Artifact uploads are restricted to declared report/build paths; `config/local`, private invites, saved worlds, arbitrary `var` logs and Composer vendors are not uploaded. Source tests use mock/local services. No deployment credentials are required by PR checks.

## Local reproduction

Use PowerShell 7 on Windows/Linux:

```powershell
./tools/ci/test-ci-policy.ps1
./tools/coordination/test-snapshot.ps1 # PowerShell 7.5+; temporary offline fixtures
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
./tools/ci/run-godot-checks.ps1 -Godot godot -TestNames machinery_runtime_test.gd
./tools/ci/build-development-export.ps1 -Platform windows -Godot godot
```

Export on the target OS, with matching Godot 4.7.2 export templates installed. Choose a new empty `-OutputDirectory` for repeat exports; the builder refuses stale files. The first-playable feature override selects the cooperative scene only in these exports. The source/editor default laboratory scene remains unchanged.

## Prepare a draft release

The **Prepare development release** workflow is manually dispatched with a successful CI run ID and a new version tag. Set reviewers on the `development-release` environment in GitHub settings if approval is desired; the workflow does not install reviewer rules itself.

The workflow checks that the run belongs to this repository's CI workflow, completed successfully, and came from a `dev-master` push/manual run. It downloads the exact tested commit's Windows/Linux artifacts, verifies archive checksums and manifests, and creates a **draft prerelease** targeting that commit. It never rebuilds newer HEAD, overwrites an existing release, publishes the draft, uploads to Steam or deploys a production server. Public publishing is a separate operator decision after graphical/Steam/VR/rights review. Expired or absent artifacts must be rebuilt through CI rather than accepted without verification.

Development binaries are unsigned. First-party material is MIT; engine/GodotSteam/Steamworks components keep their own terms and notices. Code signing, Steam depot delivery, package attestations and production rollout/rollback should be separate later delivery milestones.

References: [GitHub artifact retention and sharing](https://docs.github.com/en/actions/tutorials/store-and-share-data), [Godot command-line export](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html), and [export feature overrides](https://docs.godotengine.org/en/stable/tutorials/export/feature_tags.html).
