# Third-party software and asset notices

First-party game code, schemas, and created assets are licensed under MIT. This file records external dependencies and assets separately; their licenses remain their own and must be reviewed before redistribution.

## First-party assets

| Asset | Creator and provenance | License |
|---|---|---|
| `icon.svg` | Frontier Systems project; original geometric artwork created for this repository | MIT |

## Planned dependencies

| Dependency | Planned use | License and provenance | Integration state |
|---|---|---|---|
| Godot Engine 4.7 | Game runtime and editor | MIT; https://godotengine.org/license/ | Project configured for 4.7. |
| GodotSteam GDExtension | Steamworks API and Steam multiplayer adapter | MIT project; https://codeberg.org/godotsteam/godotsteam | `addons/godotsteam/`, Asset Library release 4.23.1, source commit `87e9456ed0922d861d352cda823ee1bde682c987`, Steamworks SDK 1.65. The release targets Godot 4.4+ and includes platform binaries. Valve's Steamworks SDK terms remain separate. |
| ReactPHP components | PHP event loop, promises, HTTP, sockets, and cache | MIT components; https://reactphp.org/ | Installed in `services/control-plane/composer.lock`. |
| DiscordPHP | Discord Social SDK integration and application-side Discord services | MIT; https://github.com/discord-php/DiscordPHP | Existing project maintained by the project owner; integration is a separate adapter package. |
| PHP-CS-Fixer | PHP formatting | MIT | Composer dev dependency; not shipped as a runtime dependency. |
| PHPUnit | Unit-test runner | BSD-3-Clause | Composer dev dependency; not shipped as a runtime dependency. |
| PHPDocumentor shim | API documentation | MIT | Composer dev dependency; not shipped as a runtime dependency. |
| PHPacker | Optional standalone binary packaging | MIT | Composer dev dependency; not shipped as a runtime dependency. |
| GitHub Actions checkout, setup-php, and setup-godot actions | CI runner setup | MIT | Used by `.github/workflows/ci.yml`; action versions are updated by Dependabot. |

## Asset intake requirements

Before adding an external art, audio, font, model, texture, or code asset, record its title, author, source URL, exact license/version, required attribution, modifications, and redistribution terms here. Prefer first-party material that the project can license under MIT and external creative assets under CC0. External software dependencies require an individually approved permissive license and retained notices. Do not assume that "free" means commercially redistributable, and do not add differently licensed creative assets without an explicit project-policy change.
