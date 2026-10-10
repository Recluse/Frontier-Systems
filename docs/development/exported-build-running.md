# Run an exported development build

These unsigned Windows/Linux x86-64 archives are cooperative development prototypes. They are not Steam store releases. The executable starts the cooperative scene; a Godot editor is not needed.

1. Extract the archive. Verify its `.sha256` checksum and retain `LICENSE`, `THIRD_PARTY_NOTICES.md` and `build-manifest.json`.
2. Generate two distinct private random invite keys of at least 32 characters. Set them only on the host as `FRONTIER_PLAYER_ONE_KEY` and `FRONTIER_PLAYER_TWO_KEY`. Choose a writable persistent directory with `FRONTIER_SAVE_DIRECTORY`.
3. Start the host with `FrontierSystems.exe --headless --xr-mode off -- --host` on Windows, or `./FrontierSystems.x86_64 --headless --xr-mode off -- --host` on Linux. Linux users may need `chmod +x FrontierSystems.x86_64` after extracting a ZIP.
4. In each client environment set `FRONTIER_HOST_URL=ws://127.0.0.1:27840` and `FRONTIER_INVITE_KEY` to that client's private invite. Start the executable without `--host`. Use separate processes for the host and each client.

The current transport is loopback by default. Public TLS hosting, account identity, Steam distribution, signing, broader movement authority and VR hardware acceptance remain separate release requirements. Keep world saves and invites outside the extracted build; never commit or upload them. First-party material is MIT; third-party engine/Steamworks dependencies retain their separate notices and terms.

CI checks the exported headless host startup and bundled runtime data, in addition to source multiplayer/restart acceptance. It does not replace graphical, Steam-client, Linux GPU or Quest 3 testing.
