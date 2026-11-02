---
name: open-debug-chrome
description: >
  Use when opening, inspecting, stopping, cloning, or cleaning dedicated Chrome
  debug profiles — e.g. “开调试 Chrome”、“看 9222 状态”、“复制调试 profile 再开一个”、
  “清理 clone profile”、“只保留源 profile”、“reset 调试 profile”、“9222 被占用”、
  “init 调试 Chrome”、“sync-app / 同步 Debug Chrome”、“超链接打开了调试浏览器”,
  and for driving a page inside that Chrome over raw CDP without stealing focus —
  “用 cdp 连 9222 打开页面 / 取 innerText / 截图 / 抓网络请求”. Does not configure
  MCP; page automation here is the scripted `cdp.mjs`, not agent-browser.
  Debug Chrome is ~/Applications/Google Chrome Debug.app, never daily Google Chrome.app.
---

# 开独立 Profile 的 Chrome

**三件事：①** 先 `init` 保证本机有隔离的 Debug.app；**②** `chrome-debug.sh` 起 / 停 / 编号复制调试 profile；**③** `cdp.mjs` 直连 CDP 操作标签页，不抢焦点。

`cdp.mjs` 需要带全局 `WebSocket` 的 Node（建议 ≥ 22）。不管 MCP；页面操作只用 `cdp.mjs`，不混用 agent-browser。

## 调用时先 init

每次用这个 skill（开调试 Chrome、连 9222、超链接被抢走、本机没 Debug.app）**第一步**：

```bash
$SCRIPT init
```

`init` 会：

1. 看 `~/Applications/Google Chrome Debug.app` 在不在、bundle 是不是 `com.google.chrome.debug`
2. 没有 / bundle 不对 / 版本落后于日常 Chrome → 从 `/Applications/Google Chrome.app` **拷一份 .app**（不是装安装包），改 bundle id、关这份拷贝的自动更新、签名
3. 已经隔离且版本一致 → 跳过拷贝，打印 `init: skip copy`
4. 需要覆盖但 Debug Chrome 正在跑 → 失败，提示先 `stop` 再 `init`

然后才 `status` / `start`。`start` 在 Debug.app 缺失或 bundle 不对时会自己跑一遍 `init`。日常 Chrome 升级后：`$SCRIPT stop && $SCRIPT init`。强制重拷：`$SCRIPT init --force`（须先停调试实例）。

## 约定

| 项 | 默认 |
|----|------|
| 源 Profile | `~/.chrome-debug-profile`（无数字后缀） |
| Clone | `~/.chrome-debug-profile-1`、`-2`、…（末尾数字） |
| 端口 | 源默认 `9222`；clone 自动找空闲口 |
| 桌面焦点 | 默认不抢（`open -g -n`） |
| 扩展 | profile 自身不继承日常插件；`start` / `clone-start` 默认用 `--load-extension` **引用**日常 `Default/Extensions` |
| Chrome 应用 | `~/Applications/Google Chrome Debug.app`（bundle `com.google.chrome.debug`） |
| 日常 Chrome | `/Applications/Google Chrome.app`（**只作 sync-app 源，禁止用来 start**） |

路径：`SCRIPT=<this-skill>/scripts/chrome-debug.sh`，`CDP=<this-skill>/scripts/cdp.mjs`。

## 硬规则

1. **禁止** `open` / 启动 `/Applications/Google Chrome.app` 做调试。日常 Chrome 的 bundle id `com.google.Chrome` 拥有 `http`/`https`，再开实例会把飞书/IDE 超链接抢走。调试只走 `Google Chrome Debug.app`（`com.google.chrome.debug`）。没有这份应用就先 `$SCRIPT init`。
2. 每个实例独立 `user-data-dir`；禁止两进程共用同一目录
3. clone 目录必须是源名 + `-` + 数字
4. 不必关日常 Chrome；不必先停源实例才能 clone
5. 起停只到 Chrome 起来/停掉；页面操作只走 `cdp.mjs`
6. 不要给日常 Chrome 或 Debug.app 加 `--headless`；无头走 Chrome for Testing / Playwright

## 用法

先查再起；已是本 profile 且 `cdp: ok` 则复用：

```bash
$SCRIPT init
$SCRIPT status
$SCRIPT start                    # 端口忙：start --pick-port
```

起 → 操作页 → 停：

```bash
$SCRIPT start
tid=$(node "$CDP" new about:blank)
node "$CDP" nav "$tid" https://example.com/
node "$CDP" text "$tid"
node "$CDP" close "$tid"
$SCRIPT stop
```

并行 clone（源可继续跑；拷贝保留源 profile 登录态，跳过锁文件）：

```bash
$SCRIPT clone-start              # → ...-1 / ...-2
$SCRIPT list-clones              # 看 port_hint
node "$CDP" --port <clone端口> targets
$SCRIPT stop --id 1
$SCRIPT cleanup-clones           # 只留源；不删 ~/.chrome-debug-profile
```

扩展（独立 profile 无启用状态；默认挂载日常 Extensions）：

```bash
$SCRIPT list-extensions
$SCRIPT stop && $SCRIPT start    # 已运行实例需重启才吃到新 --load-extension
# CHROME_DEBUG_LOAD_EXTENSIONS=0 关闭；CHROME_DEBUG_EXTENSIONS_FROM=... 换源
# $SCRIPT sync-extensions        # 可选：拷扩展文件进调试 profile（启用仍靠 --load-extension）
```

删源 / 自检：

```bash
$SCRIPT doctor                   # isolated_app + init_state
$SCRIPT reset-profile            # 需确认 YES；不管 clones
```

`start` 若 `CHROME_APP` 指向日常 Chrome 会直接拒绝。

## 操作页面：`cdp.mjs`

相对 agent-browser：按 targetId 直连该页 WebSocket，不调激活类方法，避免抢焦点与 target 漂移。

端口优先级：`--port N` > `CDP_PORT` > `9222`。

```bash
node "$CDP" targets
tid=$(node "$CDP" new about:blank)
node "$CDP" nav "$tid" https://example.com/      # → {url, ready, title}
node "$CDP" eval "$tid" "location.href"
node "$CDP" wait "$tid" "!!document.querySelector('main')" 30000
node "$CDP" text "$tid"
node "$CDP" click "$tid" 'button[type=submit]'
node "$CDP" setfiles "$tid" 'input[type=file]' ./sample.txt
node "$CDP" shot "$tid" /tmp/page.png [--full]
node "$CDP" console "$tid" 8000                  # 窗口期内 console.error / pageerror
node "$CDP" net "$tid" 10000                     # 窗口期内请求；可选第 3 参 URL 子串
node "$CDP" close "$tid"
```

- **先自证页面身份**：`nav` / `wait` 回 `url`，确认后再看内容；换过本地服务就换新标签页。
- **否定性结论要有对照组**：说「坏了 / 未就绪」前，用已知正常页跑同一条命令。
- **clone 换端口**：`list-clones` 或 `DevToolsActivePort` 后 `--port`。

## 脚本速查

```bash
$SCRIPT init | init --force
$SCRIPT status
$SCRIPT start | start --pick-port
$SCRIPT clone-start | clone-start --id <N> | clone-start --from <dir>
$SCRIPT list-clones | cleanup-clones
$SCRIPT list-extensions | sync-extensions
$SCRIPT sync-app
$SCRIPT stop | stop --id <N>
$SCRIPT reset-profile | doctor

node "$CDP" [--port N] targets | new | nav | eval | wait | text | click | setfiles | shot | console | net | close
```

| 环境变量 | 默认 / 作用 |
|----------|-------------|
| `CHROME_DEBUG_PROFILE` | `~/.chrome-debug-profile` |
| `CHROME_DEBUG_PORT` | `9222` |
| `CHROME_PATH` / `CHROME_APP` | 默认 `~/Applications/Google Chrome Debug.app`；禁止设成日常 Chrome |
| `CHROME_DEBUG_DAILY_APP` | `init` / `sync-app` 的拷贝源，默认 `/Applications/Google Chrome.app` |
| `CHROME_DEBUG_STEAL_FOCUS` | `0` 不抢焦点；`1` 前台激活 |
| `CHROME_DEBUG_LOAD_EXTENSIONS` | `1`；`0` 关闭 `--load-extension` |
| `CHROME_DEBUG_EXTENSIONS_FROM` | 日常 `…/Default/Extensions` |
| `CDP_PORT` | `cdp.mjs` 默认端口（可被 `--port` 覆盖） |

## 参考

- [references/profile-data.md](references/profile-data.md)
- [references/troubleshooting.md](references/troubleshooting.md)
