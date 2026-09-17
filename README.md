# poem-world

把三首公有领域的诗，各自做成一个可以走进去的世界；每个世界旁边挂着它被打磨出来的完整过程。

**线上：** https://chener.github.io/poem-world/

| 子项目 | 诗 | loop 机制 | harness | 模型 | 推理强度 |
|---|---|---|---|---|---|
| [`gitanjali-60/`](gitanjali-60/) | 泰戈尔《吉檀迦利》60（英文原作） | 纯 Gauntlet（一条总 prompt · 盲评 critic） | Claude Code | Claude Opus 5（非 fast） | high |
| [`xiangfuren/`](xiangfuren/) | 屈原《九歌·湘夫人》 | Gauntlet 独立 critic + Ralph 一轮一事 | Claude Code | Claude Opus 5（非 fast） | medium |
| [`chunjiang/`](chunjiang/) | 张若虚《春江花月夜》 | Gauntlet 独立 critic + Ralph 一轮一事 | Claude Code | Claude Opus 5（非 fast） | low |

## 怎么跑

零依赖，零构建。`index.html` 直接双击就能开；three.js 走 CDN。
想让右栏的时间线也能读到 `log.jsonl`，起一个本地服务：

```sh
python3 -m http.server 8731     # 然后开 http://127.0.0.1:8731/
```

## 每个子项目的结构

```
<world>/
  index.html          左边世界，右边打磨时间线
  POEM.md             公有领域原文 + Opus 5 自译 + 意象对照表（critic 的评分依据）
  POLISH.md           固定打磨 prompt，循环中不改
  log.jsonl           每轮一行：改了什么 / critic 原话与评分 / 最大缺口 / 截图 / 快照
  log.js              由 log.jsonl 生成，只为 file:// 下也能看见时间线
  versions/N/         每轮的 index.html 快照
  shots/N/            每轮六个固定机位的截图
  scene/N.json        每轮三个机位的场景数据（硬门读它，见下）
```

共用件在 [`shared/`](shared/)：`site.css`（色板）、`timeline.css` + `timeline.js`（时间线）、
`mklog.sh`（由 `log.jsonl` 生成 `log.js`）、`shoot.sh` + `cdp_shot.py`（一轮三张固定机位图）、
`worldprobe.js` + `world.sh` + `cdp_world.py`（一轮三个机位的场景数据）。三个机位在
`cams.sh` 里写一次，拍图和取数据都读它。

## 上行流量：循环工人不读图

截图拍三机位、照常落盘；**循环工人自己一张都不 `Read`**。审美判定走
[`shared/critic.sh`](shared/critic.sh)：它先用 [`shared/shrink.sh`](shared/shrink.sh)
把这一轮的图缩到最长边 ≤1024、JPEG 质量 70（单张 250–530KB → 55–100KB），
取其中最多 2 张（按轮号轮换机位，其余当场删掉），交给一个 `claude -p`
一次性进程，打印一行 JSON 就死；工人只读那行字。

```sh
sh shots.sh 44                      # 3 机位 PNG 落盘（站点与逐字节复现用）
sh ../shared/critic.sh chunjiang 44 # → {"score":7,"verdict":"还不像","critic":"…","gap":"…"}
```

为什么非这么写不可：Claude 每一次 API 请求都会把会话上下文里还在的每一张图
重新上传一遍，prompt cache 只省计费、不省上传字节。一张图读进来之后，这个会话
剩下的每一个回合都要再传一次它。2026-09-17 实测：xiangfuren 工人会话 212MB / 410 张，
chunjiang 97MB / 262 张，本机上行被打满到全屋丢包。

critic 仍然是盲评：子进程 cwd 在 `/tmp`、只开 `Read` 工具，看不到 `index.html`、
diff 或 `log.jsonl`，只拿到诗、评分口径和图。Ralph 的每轮自检用 `POEM_CRITIC_ASK`
多问一句，答案回在 JSON 的 `ask` 里。

## 硬门看场景数据，审美门才看图

源码说的是「应该出现什么」，像素说的是「实际渲染成什么样」，中间还有一层：
**场景运行时数据**。凡是能用数字断言的判断，就不该让模型看图去猜——数字几 KB、
确定、可复现，还能进仓库当长期测试。

每个世界的页面都暴露一个调试口 `window.__world()`，返回这一帧到底有什么：

```sh
sh shared/world.sh chunjiang 44        # → chunjiang/scene/44.json，三机位，约 10 KB
python3 -c "import json;d=json.load(open('chunjiang/scene/44.json'))
print([o for o in d['cameras'][2]['objects'] if o['name']=='boat'])"
```

一个对象一行，字段只有硬门现在用得到的那些：

| 字段 | 回答的问题 |
|---|---|
| `present` / `count` | 这东西建出来没有，有几个 |
| `bbox` | 它在世界里的什么位置、多大（世界坐标） |
| `screen` / `cover` | 投到这个机位的画面上是哪一块、占几成画面 |
| `inView` / `inViewCount` / `behind` | 在不在画面里；一片实例里有几个在画面里 |
| `color` / `alpha` / `drawn` | 材质颜色；这个距离上还画不画 |
| `render.triangles` / `render.calls` / `render.frameMs` | 有没有超性能预算 |
| `camera.ground` / `camera.eyeAboveGround` | 机位的 y 是世界绝对高度，这两个才是眼睛离地多高 |

三个世界三种渲染器（three.js / 手写 WebGL / 手写 Canvas 2D），所以三份 `__world()`
各写各的，只共用 [`shared/worldprobe.js`](shared/worldprobe.js) 里的投影—包围盒—出屏
那点算术和 schema。**探针一律读画面自己那张表**：three.js 读场景图与 `instanceMatrix`，
xiangfuren 读建网格时标记的顶点区段和更新时写回的位置，chunjiang 用 `project()`——
画面用哪个公式，探针就用哪个。一份会漂的镜像报的是没人在渲染的那个世界。

`frameMs` 是 CPU 画/提交这一帧的时间：Canvas 2D 世界里它就是画一帧的钱；两个 GL
世界里 GPU 是异步的，它只是提交时间，真正的预算看 `triangles` 和 `calls`。

`shared/world.sh` 跟 `shared/shoot.sh` 是同一套浏览器管线：同一把
`/tmp/poem-world-shot.lock`、同样的后台 QoS、同样的 Metal → headed → SwiftShader 回退，
所以同一时刻本机仍然只有一个渲染进程。

## 截图与资源

循环工人和这台电脑共用一台机器，截图必须又轻又短：同样 3 张机位，单张墙钟 ≤ 60 秒，
单进程 CPU 峰值不超过一核。调度本身也要轻——不常驻浏览器，不引入 puppeteer。

入口是各世界的 `shots.sh`（`xiangfuren/shoot.sh` 是同内容的别名），全部 `exec` 到
[`shared/shoot.sh`](shared/shoot.sh)。一次进程拍完三机位后退出。共用
`/tmp/poem-world-shot.lock`，QoS 是 `taskpolicy -c background nice -n 20`。

`?shot=1` 只降开销、不改交互：DPR 固定为 1、关 blob 阴影、粒子大约减半、同步画 1 帧后
打上 `data-shot-ready`，机位切换走 `window.__poemShot` 而不重建场景。不要在截图路径里
等 `requestAnimationFrame`——离屏 / headless 窗口常常根本不打 rAF。

2026-09-17 在本机（Apple M5）对 `gitanjali-60` 三机位测过（含上述 `?shot=1`）：

| 方案 | 一轮 | 单张 | 单进程 CPU 峰值 | 进程树 CPU | 是否可用 |
|---|---|---|---|---|---|
| 1. headed 离屏 Chrome for Testing + Metal + CDP | 5.3s | 0.20–0.31s | （未分列） | 205% | 是，ANGLE Metal |
| 2. `headless=new` + `--enable-gpu --use-angle=metal --use-gl=angle --enable-gpu-rasterization` | 4.1s | 0.38–0.57s | 56–70% | 166–226% | 是，ANGLE Metal，有 GPU 进程 |
| 3. Playwright WebKit 无头 | — | — | — | — | 未试：1 和 2 已可用，不引入新依赖 |
| 4. 仅场景侧 `?shot=1`（叠加在捕获通道上） | 见上 | 见上 | 见上 | 见上 | 是。同一 CDP 换 SwiftShader 一轮 8.2s，单张仍 < 1s |

选定 **2 + 4**：headless 不抢焦点、不占一块屏；Metal 起来了就把绘制交给 GPU；CPU 峰值按单进程算低于一核。只加 `--use-angle=metal`、不加另外三条 GPU 标志时 headless 曾 90 秒不出图，所以标志要齐。GPU 起不来时 `shared/shoot.sh` 依次退到 headed-metal、SwiftShader。旧路径（`chrome-headless-shell --screenshot --virtual-time-budget=5000 --disable-gpu`）会让软件 GL 把虚拟时间里的每一帧都画完，一张图可以到分钟级，单进程 CPU 350–390%。

截图进程再加拉开标志：`--num-raster-threads=1 --renderer-process-limit=1 --js-flags=--single-threaded`（SwiftShader 另加 `--disable-gpu-compositing`）。本机前后（`gitanjali-60` 三机位）：

| | 一轮 | 单张 | 单进程 CPU 峰值 | 进程树 CPU |
|---|---|---|---|---|
| 拉开前（方案 2，无上述标志） | 4.2s | 0.38–0.57s | 56% | 176% |
| 拉开后 | 3.5s | 0.25–0.43s | 92%（≤ 一核） | 303%（多进程启动瞬间加总；无一进程超一核） |

页面本身也有预算，交互语义不变：DPR 上限 1.5、帧率上限 30、首帧之后相机不动就不重绘、标签不可见时暂停、无 shadow map、粒子有常数上限、`?lite=1` 或 `prefers-reduced-motion` 关抗锯齿并去掉 ACES。本机 Chrome for Testing 读进程 `%cpu`（接近任务管理器那一栏）：

| 世界 | 静止峰值 / 均值 | 漫游峰值 / 均值 |
|---|---|---|
| gitanjali-60 | 2.8% / 0.7% | 16.4% / 12.4% |
| chunjiang | 4.7% / 1.2% | 15.8% / 13.9% |
| xiangfuren | 12.4% / 1.8% | 15.8% / 11.9% |

静止 ≤ 15%、漫游 ≤ 60%。

```sh
sh gitanjali-60/shots.sh <round> [port]
sh xiangfuren/shots.sh <round> [port]    # 或 ./xiangfuren/shoot.sh
sh chunjiang/shots.sh <round> [port]
```

## 循环

- **Ralph 式一轮一事**：一轮只修一个缺口，其余记进 `noticed` 留给后面。
- **Gauntlet 式独立 critic**：每轮另开一个没看过任何代码、diff、解释的子代理，
  只给它诗、意象对照表和六张截图，让它回答「像不像 / 最大缺口」。
- 六个机位和动画时钟在第一轮就定死，所以 `shots/3/` 和 `shots/7/` 的同名图可以直接叠着比。

停止条件：10 轮 / critic 连续两轮「我们赢」/ `log.jsonl` 出现 `stop` / 周限额度快到。
