## Summary

<!-- What changed, and why? -->

## Verification

- [ ] PHP checks pass (`composer cs-check`, `composer unit`, Composer validation/audit) when PHP changes are included.
- [ ] Godot headless project import passes on Ubuntu and Windows when Godot assets or scripts are included.
- [ ] Runtime PHP changes avoid child-process and POSIX-only APIs and pass the Windows runtime policy check.
- [ ] Public PHP APIs and Godot asset/system contracts are documented.
- [ ] Any new third-party code or asset has provenance and license details in `THIRD_PARTY_NOTICES.md`.
- [ ] First-party code and assets remain MIT-compatible; no secrets or generated runtime data are included.
- [ ] Changes preserve server authority and keep external service waits out of simulation ticks.

## Requirement or design reference

<!-- Link the issue, design section, or project requirement this PR addresses. -->
