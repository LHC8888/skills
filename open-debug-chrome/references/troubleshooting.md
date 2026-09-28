# 排障（仅开 Chrome）

## 为什么调试 Chrome 没有日常插件？

独立 `--user-data-dir` 不会继承日常 profile。扩展启用状态在日常 Chrome 的 `Secure Preferences` 里（带校验），**不能**靠整盘拷贝可靠复用。

本 skill 默认在启动时用 `--load-extension` 挂载日常
`~/Library/Application Support/Google/Chrome/Default/Extensions` 下各扩展的最新版本目录。

```bash
scripts/chrome-debug.sh list-extensions
scripts/chrome-debug.sh stop && scripts/chrome-debug.sh start   # 已运行的实例要重启
```

注意：

- 可能出现「停用开发者模式扩展」提示（`--load-extension` 的正常现象）
- 日常里更新扩展后，下次 start/clone-start 会跟到新版本目录
- `CHROME_DEBUG_LOAD_EXTENSIONS=0` 可关闭

## 会不会抢走当前应用焦点？

默认**不会**。macOS 上用 `open -g -n` 起新实例，焦点留在 IDE/终端。

- 仍可能在后台出现窗口 / Dock 跳一下，但不抢键盘焦点
- 若要前台激活：`CHROME_DEBUG_STEAL_FOCUS=1 scripts/chrome-debug.sh start`

## 复制 profile 再开第二个实例？

可以，用 `clone-start`（不必先停源 debug Chrome）：

```bash
scripts/chrome-debug.sh clone-start          # → ~/.chrome-debug-profile-1
scripts/chrome-debug.sh clone-start          # → ~/.chrome-debug-profile-2
scripts/chrome-debug.sh list-clones
scripts/chrome-debug.sh stop --id 1
scripts/chrome-debug.sh cleanup-clones       # 删掉所有 -N，只留源 profile
```

- 源：`~/.chrome-debug-profile`（无数字后缀）
- clone：同目录下 `~/.chrome-debug-profile-<N>`
- 拷贝跳过锁文件，保留登录态；自动选空闲端口
- **两个实例绝不能共用同一个 user-data-dir**

## 必须先关日常 Chrome 吗？

**不必。** 独立 `user-data-dir` 可与日常 Chrome 并行。

只有这些情况才要处理已有进程：

- 两个进程抢**同一个** profile 目录
- 目标端口被无关进程占用，且你坚持用该端口

## 端口被占

```bash
scripts/chrome-debug.sh status
```

- 本 profile 已占用且 `cdp: ok` → 直接复用，不必再 start  
- 其他进程占用 → `start --pick-port` 或换 `CHROME_DEBUG_PORT`  
- **不要**假设 `localhost:9222` 一定是你的 debug Chrome  

## start 后 CDP 不通

等 1–2 秒再 `status`；仍失败则 `stop` 后重 `start`。  
确认 `CHROME_PATH` 指向真实可执行文件。

## 误连到 Playwright / Codex 的 Chrome

`status` 里 `port_owner: OTHER process` 时不要继续用该端口。换端口或停掉占用方后再 start。

## clone 实例怎么连 CDP？

```bash
scripts/chrome-debug.sh list-clones   # 看 port_hint / path
# 或读 ~/.chrome-debug-profile-<N>/DevToolsActivePort 第一行
node scripts/cdp.mjs --port <N> targets
```

源实例默认 `9222`；不要把 clone 的请求打到源端口。
