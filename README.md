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
```

共用件在 [`shared/`](shared/)：`site.css`（色板）、`timeline.css` + `timeline.js`（时间线）、
`mklog.sh`（由 `log.jsonl` 生成 `log.js`）、`shoot.sh` + `cdp_shot.py`（一轮三张固定机位图）。

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
