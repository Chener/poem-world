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

**Screenshots are one Chrome process per round, niced.** `shared/shoot.sh` launches
Chrome for Testing with `--headless=new`, Metal GPU flags, and single-core spread
(`--num-raster-threads=1 --renderer-process-limit=1 --js-flags=--single-threaded`),
captures all three cameras over CDP (`shared/cdp_shot.py`), then exits. Cameras switch
through `window.__poemShot` so the scene is not rebuilt. Shared `mkdir` lock at
`/tmp/poem-world-shot.lock`; `taskpolicy -c background nice -n 20`. `?shot=1` is
DPR=1 and one synchronous frame (`data-shot-ready`) — do not wait on rAF, offscreen
and headless often never fire it. If Metal does not come up, the script falls back to
headed-offscreen Metal, then SwiftShader. Numbers live in README「截图与资源」.

**Interactive pages pause when still.** DPR cap 1.5, 30 fps, no shadow maps, freeze the
loop after the first frame until input, and pause when `document.hidden`. `?lite=1` (or
`prefers-reduced-motion`) is the degrade switch. Do not keep a rAF loop spinning on an
idle tab.

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

**主循环工人不读图。** Claude 的每一次 API 请求都会把会话上下文里还在的每一张图重新上传
一遍；prompt cache 只省计费，不省上传字节。一张 300KB 的截图被 `Read` 进来之后，这个会话
剩下的每一个回合都要再传一次它，直到压缩把它挤掉。2026-09-17 实测：xiangfuren 工人会话
212MB / 410 张图，chunjiang 97MB / 262 张，本机上行被打满到全屋丢包。所以：截图照常三机位
落盘（站点要用，逐字节复现也要用），但**循环工人自己不 `Read` 任何 `shots/` 下的图**，也不
从浏览器通道把截图取回会话——审美判断走 `shared/critic.sh`，一个 `claude -p` 一次性进程看
图、打分、打印 JSON，工人只读那行文字。缩放与张数上限写死在
`shared/shrink.sh`（最长边 ≤1024、JPEG 质量 70，单张 250–530KB 掉到 55–100KB）和
`shared/critic.sh`（每轮最多 2 张，按轮号轮换机位，其余当场删掉）。critic 仍然是盲评：
子进程的 cwd 在 `/tmp`、只开 `Read` 工具，看不到 `index.html`、diff 或 `log.jsonl`。
**不要假设 Task 子代理就等于不进主会话**——chunjiang 的 `POLISH.md` 一直写着 critic 子代理，
主会话仍然攒下了 262 张，因为工人为了挑图、比较前后轮、排查黑图，还是自己看了。

**Rendered content avoids violent or morbid imagery**, whatever the source poem contains.
Public-domain originals live in `POEM.md`; the world, the screenshots and the prose around
them stay clear of it.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
