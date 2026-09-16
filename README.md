# poem-world

把三首公有领域的诗，各自做成一个可以走进去的世界；每个世界旁边挂着它被打磨出来的完整过程。

**线上：** https://chener.github.io/poem-world/

| 子项目 | 诗 | loop 机制 | harness | 模型 | 推理强度 |
|---|---|---|---|---|---|
| [`gitanjali-60/`](gitanjali-60/) | 泰戈尔《吉檀迦利》60（英文原作） | Gauntlet 独立 critic + Ralph 一轮一事 | Claude Code | Claude Opus 5（非 fast） | high |
| [`xiangfuren/`](xiangfuren/) | 屈原《九歌·湘夫人》 | Gauntlet 独立 critic + Ralph 一轮一事 | Claude Code | Claude Opus 5（非 fast） | medium |
| [`duino-1/`](duino-1/) | 里尔克《杜伊诺哀歌》第一首（德文原作） | Gauntlet 独立 critic + Ralph 一轮一事 | Claude Code | Claude Opus 5（非 fast） | low |

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
`mklog.sh`（由 `log.jsonl` 生成 `log.js`）、`shoot.sh`（一轮六张固定机位图）。

## 循环

- **Ralph 式一轮一事**：一轮只修一个缺口，其余记进 `noticed` 留给后面。
- **Gauntlet 式独立 critic**：每轮另开一个没看过任何代码、diff、解释的子代理，
  只给它诗、意象对照表和六张截图，让它回答「像不像 / 最大缺口」。
- 六个机位和动画时钟在第一轮就定死，所以 `shots/3/` 和 `shots/7/` 的同名图可以直接叠着比。

停止条件：10 轮 / critic 连续两轮「我们赢」/ `log.jsonl` 出现 `stop` / 周限额度快到。
