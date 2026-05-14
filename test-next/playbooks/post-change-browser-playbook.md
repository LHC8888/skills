# Post-change Browser Playbook

## 适用条件

- 代码已修改完成
- 需要对 browser 路径做改后自验收

## 输入

- 改动边界（新行为/新风险）
- 覆盖等级（L0-L4）
- 是否触发 UI 还原度/性能/埋点维度

## 输出

- browser 测试任务清单与执行结果
- 三通道证据（console/network/log）
- 修复建议（严重/一般/轻微）

## 执行步骤（vertical slice）

0. 入口推断：写 spec 前 grep 被测组件用法，确认组件是否挂在 Modal/Dialog/Drawer/Popover/条件渲染内，再找 URL param、按钮、菜单项或状态入口；不要假设直接 `goto` 顶层路由就能看到组件。
1. 若用例依赖账号态，先执行 `browser-auth-profile-playbook.md` 的登录入口推断与 `auth-check.spec.ts` 校验。
2. 先跑 1-2 条 P0 主流程任务。
3. 收集三通道证据并更新任务状态。
4. 根据证据增删后续任务（而非先列完再跑）。
5. 覆盖触发的横切维度与邻居 smoke。
6. **探索性测试 timeboxed 2 分钟（Playwright 临时 spec）**：
   - 写 `<file>._explore.spec.ts` 临时文件，跑 `playwright test --headed --reporter=line` 实时看
   - 用 `expect.soft(...)` 写试探断言（异常输入 / 罕见路径 / 反直觉操作），看哪些过哪些挂
   - 可加 DOM dump、screenshot、`page.on('response')` sniff 真响应结构
   - 失败 trace + screenshot 提供反馈，2 分钟内迭代调整
   - 发现意外行为 → 提取为正式 `*.spec.ts` 的 `test('[探索发现] ...', ...)` block，**删 explore 文件**
   - 2 分钟无发现就停

## Harness 对接（三步）

### Step 1 输出测试任务

```text
- id
- level（L0-L4，影响面，按 SKILL.md §1.4 判定）
- priority（P0/P1/P2，修复优先级，按 SKILL.md §2.2 判定）
- expectation
- executor=playwright/manual
```

（其余字段见 SKILL.md §2.1）

### Step 2 测后更新任务

```text
- status: pass/fail/skip
- evidence:
  - console
  - network
  - server_log (L3+)
- notes
```

### Step 3 修复建议分级

按严重性排序输出修复建议：

1. 严重
2. 一般
3. 轻微

若存在“严重 + 阻塞主流程”，必须标注“必须修复”并停止交付结论。

### Step 4 交付物处理

默认是 `persist-spec`：把有效 browser spec 和项目根 `playwright.config.ts` 沉淀到项目，后续增量维护以减少重复生成；fixtures、auth helper、trace、HTML report 仍写到系统临时目录，不创建 `tests/` / `tests/browser-harness/`，不改 `.gitignore`。

即使用户要求后续回归 / 重跑，也要沉淀 `playwright.config.ts` 这类关键公共配置；默认回归环境已经足够，fixtures / auth helper 仍保持临时化。用户显式要求“一次性验证 / 不留文件”时才走 `report-only`，连 spec 和 config 也只放 tmp。

页面是渐进式变更的——测试用例代码也应该**渐进式更新**，而不是每次重新生成。

**spec 保存位置**：与被测页面 / 模块根目录同级，命名 `<file>.spec.ts`（Playwright spec，与单测 `<file>.test.ts(x)` 同策略——靠近被测对象，**不放 `docs/` 或 `tests/` 等独立目录**）。

**config 保存位置**：项目根 `playwright.config.ts`。如果已有 Playwright config，增量补齐 `testMatch`、`timeout`、`expect.timeout`、`workers: 1`、临时 `outputDir` / HTML report 目录；如果没有，必须从 `templates/playwright-config.template.ts` 创建。`test-results/`、`playwright-report/`、trace、video 默认都走系统临时目录，不写项目根。

**形式**：标准 Playwright spec —

- `import { test, expect } from '@playwright/test'`
- 项目内持久 spec 可以依赖项目内 Playwright config，但不引用 tmp harness；需要 auth profile / persistent context 时，由运行期 tmp wrapper / fixture 承接
- 用 `test.describe` / `test` 分组，名字表达优先级与场景（如 `test('[P0] 登录主流程', ...)`）
- 用 `page.locator('[data-testid=...]')` 选稳定 selector，禁用位置 selector（如 `:nth-child`）
- 如果源码缺少稳定 selector，优先给当前用例需要的元素补 `data-testid` / 稳定 id，再写 spec；不要把脆弱 DOM 路径沉淀下来
- 账号态用例不在 spec 中写死 `~/.test-next-profile/...`；profile 由运行期 auth helper / auth config 注入
- 用内置断言 `expect(locator).toHaveURL(...)` / `.toBeVisible()` / `.toHaveText(...)` / `.toHaveCount(...)`
- 视觉用例用 `expect(page).toHaveScreenshot('login.png')` 自动管理基线 + diff
- 失败自动产生 trace + video（在 `playwright.config.ts` 配 `trace: 'on-first-retry'`）

**Playwright 优势**（相对手写脚本）：类型安全、自动等待（无需手动 wait）、内置断言、失败可回放。

**增量场景**：在原 `*.spec.ts` 上 diff 增删 `test(...)` block，**不重写**已覆盖的稳定 test。

**跑**：`pnpm exec playwright test path/to/<file>.spec.ts`。

> Playwright 配置（`playwright.config.ts`）需开启 `testMatch: '**/*.spec.ts'` 或类似模式以匹配同目录 spec 文件，而非默认的 `tests/` 目录。

**`[探索发现]` 用例**：默认沉淀到正式 spec；report-only 模式写入报告。

> 关键原则：默认保留测试用例代码和项目根 `playwright.config.ts`，且测试用例跟着页面渐进式变更，不从零生成；fixtures/auth helper 和运行产物不默认落盘。

## 效率选项（opt-in）

默认每条 test 新开 page，项目级 browser 配置默认 `workers: 1`，避免账号态 persistent profile 并发锁冲突。

当页面初始化极慢、测试只读且能接受串行状态管理时，可用 `test.describe.configure({ mode: 'serial' })` + `beforeAll` 共享 page，并在每条用例前 `reload` / reset 必要状态。慢 `beforeAll` 的第一行写 `test.setTimeout(60_000)`，因为 `beforeAll` 有独立 hook timeout。

并发/CI 需要 `workers > 1` 时，必须启用 per-worker profile copy：`TEST_NEXT_COPY_PROFILE_PER_WORKER=true`。

## Footguns

- SaaS 应用常有 polling / websocket，默认不要用 `networkidle` 判断页面稳定；用 `domcontentloaded` + 业务元素 `expect(...).toBeVisible()`。
- `test.beforeAll` 的 timeout 独立于单个 test；慢初始化要在 hook 第一行 `test.setTimeout(...)`。
- Modal/Dialog 内元素先 scope 容器再查找，避免同 role+name 跨菜单、弹窗、页面主体冲突。

## 回退策略

- 无法复现：补环境前置（账号态、视口、网络、locale）。
- 断言模糊：改为可量化期望（px/hex/ms/fps/status code）。
