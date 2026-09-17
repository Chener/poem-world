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

**Screenshots are one-shot and must yield to the operator.** `shared/shoot.sh` launches
one `chrome-headless-shell` per frame that exits when the file is written, under
`taskpolicy -c background nice -n 20`, behind a shared `mkdir` lock at
`/tmp/poem-world-shot.lock`, after checking `uptime` load and `memory_pressure`. It
renders through SwiftShader by default; `POEM_WORLD_ANGLE=metal` switches to the GPU
path, which costs a tenth of the CPU but takes the GPU the operator is drawing their
screen with (measurements and the `--disable-gpu` trap are in the script's comments). Never
leave a browser running and never open a visible window: several workers share this
machine and somebody is using it. Shot mode stops the render loop after a few frames
(`SHOT_FRAMES`).

**Shots must stay reproducible.** Every world freezes its clock (`FROZEN_T`) and places
its contents from hashes of stable indices, never from runtime randomness, so the same
camera in round 3 and round 9 frames the same scene. `md5` on two rounds' same-named
shots is the check — but only within one rasteriser: changing the ANGLE backend changes
every byte while changing nothing in the world.

**The timeline reads `log.jsonl`; `log.js` is a generated mirror** for `file://`, where
`fetch` of a sibling file is blocked. Append rounds with `shared/logrow.py`, which
regenerates the mirror; never hand-edit `log.js`.

**Spend mesh resolution where the eye is, and check the winding.** Two bugs cost
gitanjali-60 six rounds of critics writing "the sea is a pastel plane": a uniform grid
over four kilometres put one vertex every 6.8m under wave trains 6.2m long, so the surf
could not exist; and a hand-built `BufferGeometry` whose quads were wound the wrong way
was silently back-face culled, showing the sky dome through the water — which looks
enough like a flat sea to waste an afternoon on. Non-uniform rows fixed the first. For
the second, a mesh that vanishes but leaves the scene looking plausible is almost always
winding or `side`.

**A camera's `y` in `CAMS` is world-absolute, not height above ground.** gitanjali-60's
`children` camera reads as 0.95m but sits 8cm above the sand there, so anything flat and
close to it smears across the frame. Check a camera against the terrain height at its
own x/z before believing its eye height.

**Rendered content avoids violent or morbid imagery**, whatever the source poem contains.
Public-domain originals live in `POEM.md`; the world, the screenshots and the prose around
them stay clear of it.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
