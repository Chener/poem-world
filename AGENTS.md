# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.

## poem-world

Each sub-directory is one poem made walkable. They share `shared/` and nothing else;
a change inside one world must not touch another. Structure, tooling and the polish
loop are documented in `README.md`; each world's frozen loop prompt is its `POLISH.md`.

**Zero build, and it has to stay that way.** No npm, no bundler. three.js comes from a
CDN as a classic UMD script, not an ES module: module scripts are blocked under `file://`,
and these pages must open by double-clicking as well as over Pages.

**Custom ShaderMaterials must end with `#include <tonemapping_fragment>` and
`#include <colorspace_fragment>`.** three.js only injects those into its own materials.
Without them a shader writes raw linear values to an sRGB target and every authored
colour renders far too dark. This is the single easiest way to make a world look broken.

**`instanceColor` multiplies `material.color`.** Tint one or the other, never both, or
instanced colours come out squared and nearly black.

**Anything floated on the water must use the same wave field the shader draws.** In
`gitanjali-60` the GLSL is generated from one `WAVES` table that the JS mirror also reads;
keep it that way. A JS mirror that drifts from the shader puts boats under the surface.

**Screenshots are one-shot and niced.** `shared/shoot.sh` launches a headless Chrome for
Testing per frame that exits when the file is written, behind a shared `mkdir` lock at
`/tmp/poem-world-shot.lock`, after checking `uptime` load and `memory_pressure`. Never
leave a browser running: several workers share this machine. Shot mode stops the render
loop after a few frames (`SHOT_FRAMES`), because software GL will otherwise faithfully
render every frame of Chrome's virtual-time budget and take minutes per image.

**Shots must stay byte-reproducible.** Every world freezes its clock (`FROZEN_T`) and
places its contents from hashes of stable indices, never from runtime randomness, so the
same camera in round 3 and round 9 frames the same scene. Verify with `md5` after changes
to placement code.

**The timeline reads `log.jsonl`; `log.js` is a generated mirror** for `file://`, where
`fetch` of a sibling file is blocked. Append rounds with `shared/logrow.py`, which
regenerates the mirror; never hand-edit `log.js`.

**Rendered content avoids violent or morbid imagery**, whatever the source poem contains.
Public-domain originals live in `POEM.md`; the world, the screenshots and the prose around
them stay clear of it.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
