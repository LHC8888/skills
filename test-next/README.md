# test-next 设计记录

## 用途

`test-next` 用于在代码改动后生成测试任务，并在可执行时完成自验证与修复建议分级。

覆盖：

- browser 路径（UI/交互/路由/性能/埋点/视觉）
- unit 路径（函数/hook/service/tRPC/状态机）
- TDD 路径（unit only）

## 当前结构

```text
test-next/
├── SKILL.md
├── README.md
├── playbooks/
│   ├── tdd-unit-playbook.md
│   ├── post-change-unit-playbook.md
│   ├── post-change-browser-playbook.md
│   ├── explicit-generation-unit-playbook.md
│   ├── explicit-generation-browser-playbook.md
│   └── browser-auth-profile-playbook.md
├── references/
│   ├── browser/
│   │   ├── risk-axes.md
│   │   ├── scenarios.md
│   │   ├── api-mock.md
│   │   ├── ui-fidelity.md
│   │   ├── performance.md
│   │   └── tracking.md
│   └── unit/
│       ├── risk-axes.md
│       ├── scenarios.md
│       └── mocking.md
└── templates/
    ├── bug-report.md
    ├── browser-auth-config.template.ts
    ├── browser-auth-login.template.ts
    ├── browser-auth-check.spec.template.ts
    ├── playwright-config.template.ts
    └── playwright-fixtures.template.ts
```

## 核心设计决策

### 1. `SKILL.md` 固定三层

- §1 Fast Path（模式/类型/等级快速路由）
- §2 Must Rules（不可违背规则）
- §3 Routers（跳转到 playbook 与 reference）

目标：减少首屏信息量，同时保持执行一致性。

### 2. 按模式 × 测试类型拆 playbook

- 模式：`tdd` / `post-change` / `explicit-generation`
- 类型：`unit` / `browser`

目标：让执行流程可直接落地，避免在主文档堆细节。

### 3. 删除统一 test-case-list 模板

不再维护跨路径通用模板，改为在各 reference/playbook 保留本地化样例，减少跨文件耦合。

### 4. harness 自验证采用简化三步

1. 输出测试任务
2. 测试后更新任务
3. 输出修复建议（严重/一般/轻微）

若“严重 + 阻塞主流程”，必须标记“必须修复”。

### 5. unit references 去 stub 化

unit 侧从“方向提示”升级为“可执行任务模板”：

- 风险轴：触发条件、最小必测集、误测与跳过条件
- 场景表：每类场景最小任务集 + 样例
- mock 策略：决策树 + 级别选择 + 误区

### 6. 字段单一来源 + priority 单点判定

- 任务字段定义统一在 `SKILL.md §2.1`，所有 playbook 引用而不重复定义
- `priority`（P0/P1/P2）= **事前判断**，按二维矩阵（失败严重性 × 触发概率）打
- `severity`（严重/一般/轻微）= **事后判断**，基于 evidence 现场分级
- 不预填 `severity_if_fail` / `blocker_if_fail`——避免与 priority 冲突 / 占字段
- 生成清单后必须做**去重 pass**（多源展开会重复，需合并 `precondition` / `steps` / `expectation` 相同的任务）

### 7. 用例展开方法论自动应用

`unit/risk-axes.md` 加「输入类型 → 应用方法 → 自动展开」速查表：

- 数值字段 → BVA → 9 种边界
- 字符串 → 等价类 + BVA
- 多布尔条件 → 决策表
- 状态机 → 状态转换覆盖

避免 agent 看到样例只复制 1-2 条边界，强制系统性展开。`browser` playbook 加 timeboxed 2 分钟探索性测试，发现 → 沉淀 `[探索发现]` 用例。

### 8. 默认沉淀 spec + playwright.config.ts，harness 保持临时

- **persist-spec（默认）**：把有效测试用例代码和项目根 `playwright.config.ts` 沉淀到项目，后续增量维护以减少重复生成；browser spec 与被测模块同级。
- **runtime harness 默认临时化**：fixtures、auth helper、trace、video、HTML report 写入系统临时目录，不创建 `tests/` / `tests/browser-harness/`，不改 `.gitignore`。
- `playwright.config.ts` 是关键公共配置，默认必须保留；但其中的 `outputDir` / HTML report 目录默认指向系统临时目录，避免项目根生成 `test-results/` / `playwright-report/`。
- 即使用户要求后续回归 / 重跑，也必须保留 `playwright.config.ts` 这类关键公共配置；fixtures/auth helper 不写回项目。
- **report-only（显式）**：用户明确要求“一次性验证 / 不留下文件 / 只出报告”时，连 spec 和 Playwright config 也只写入系统临时目录。
- 账号态 source profile 例外：默认放 `~/.test-next-profile/<project-slug>/auth-source`，它不污染项目目录。

### 9. 测试代码渐进式变更（增量优先 + 4 步骨架）

- **路径约定**：所有测试文件与被测文件同目录（不放 `docs/` 或 `tests/` 独立目录）
  - 单测：`<file>.test.ts(x)`
  - 浏览器：`<file>.spec.ts`（Playwright spec）
- **生成前必查**（SKILL.md §1.1）：被测目录是否已有测试文件
- **增量模式 4 步骨架**（SKILL.md §1.1.4）：
  1. **Step 1 读** 已有 `test('...')` block 的标题 + 关键断言 → 形成「已覆盖维度清单」
  2. **Step 2 对齐变更分类**：
     - **新增**（变更引入未覆盖行为）→ 新增 test block
     - **修改**（变更触及已有断言）→ 改断言，**保留 test 名**便于跟踪
     - **删除**（变更删了功能）→ 删 test
     - **保留**（变更未触及）→ **不动**（不重写、不格式化、不改风格）
  3. **Step 3 去重**：新增 / 修改的 test 与已覆盖清单做去重 pass
  4. **Step 4 Edit 增量改 + 跑全套**：
     - 用 Edit 工具最小化改动（保留 `import` / `describe` / 稳定 test block）—— **禁止 Write 整文件**
     - 跑全套（含稳定 test）确认无回归；稳定 test 失败 = 本次变更引发的回归
- **关键原则**：测试代码跟着源文件渐进式变更——避免重复消耗 token + 保持一致性 + 历史 test 轨迹可追踪

### 10. 前置摸排与 spec-zero

写 browser spec 前必须先完成两类低成本确认：

- `SKILL.md §1.1.2 spec-zero 探针`：baseURL 探活、无登录态路径行为、关键 DOM / 触发入口是否出现。
- `SKILL.md §1.4.5 被测对象代码摸排`：消费方、输入边界、输出契约、触发链、外部影响因素。

这样能避免嵌套组件、modal portal、lazy mount、hydration gate 等场景下直接写错入口和 selector。

### 11. 单一工具栈：Vitest + Playwright（默认 headless + 专用 automation profile）

**只用两个测试工具**，明确禁止 Cypress / WebdriverIO / Selenium 等第三方栈：

- **Vitest**：纯函数 / hook / service / React 组件渲染 / pure logic
- **Playwright**：真实浏览器 / 真实 DOM 事件 / SSR / 路由 / 视觉对比 / 跨页流程 / **探索性测试**

**为什么选 Playwright**：

- **类型安全**：TypeScript + 官方类型，agent 改测试不容易写错
- **内置断言**：`expect(locator).toHaveURL/toBeVisible/toHaveText/toHaveCount/toHaveScreenshot`
- **自动等待**：locator 隐式等元素，无需手写 `wait`，flaky 低
- **失败可回放**：trace + video 自动生成
- **视觉对比内建**：`toHaveScreenshot` 自动管理基线 + diff
- **统一栈**：探索 / 沉淀 / 回归 / 视觉都用同一工具，降低 agent 切换成本

**探索性测试也用 Playwright**：

- 写 `<file>._explore.spec.ts` 临时文件，跑 `playwright test --headed --reporter=line`
- 用 `expect.soft(...)` 写试探断言（异常输入 / 罕见路径 / 反直觉操作）
- 失败 trace + screenshot 提供反馈，2 分钟内迭代调整
- 发现的有效用例 → 提取为正式 `*.spec.ts` 的 `test('[探索发现] ...', ...)` block，**删 explore 文件**

**项目级配置：默认 headless + workers=1 + launchPersistentContext**

- `playwright.config.ts` 模板：`templates/playwright-config.template.ts`
- 临时 runtime fixtures 模板：`templates/playwright-fixtures.template.ts`
- 默认行为：fixture 用 `launchPersistentContext(sourceProfileDir)` 启动并关闭 Chrome；require-auth 校验和并发 profile copy 都在 worker fixture 中完成。
- 默认 `workers: 1`，避免同一个 persistent profile 被多个 worker 同时打开。
- 并发/CI 才开启 `TEST_NEXT_COPY_PROFILE_PER_WORKER=true`，从 source profile 复制到每个 worker 的临时目录。
- `PLAYWRIGHT_CDP_URL` 仅作为交互调试 escape hatch，不是默认路径。
- 模板默认 `timeout: 60_000` / `expect.timeout: 30_000`，适配大 SSR / 慢 dev server；CI 更慢时可上调到 90s。

**CLI 临时调整**（不改 config）：

- `--headed` —— 探索时切 headed 看实际行为
- `--trace=on` —— 强制录全 trace（默认仅失败时）
- `playwright test src/pages/Foo/Foo.spec.ts` —— 跑单文件
- `--grep "登录"` —— 按 test 名筛选

### 12. 测试环境前置检查（缺失即 fallback）

走任何路径前必须验证环境就位（SKILL.md §1.1.1）：

- **browser**：`@playwright/test` 依赖；默认保留项目根 `playwright.config.ts`，fixtures/auth helper 在 tmp 中生成，不检查项目内 harness
- **unit**：`vitest` 依赖

任一缺失：
- 提示用户配置（具体命令 + `templates/` 模板路径）
- 用户拒绝 / 暂不配置 → **fallback `explicit-generation` 模式**（只生成 spec/test 文件不跑）
- 等环境就位再回来跑

**为什么必须前置**：避免 agent 静默生成跑不起来的测试——白消耗 token + 输出无效结果。前置检查 → 要么环境齐 → 跑通有结果；要么提示 + 退到生成模式 → 用户清楚下一步。

### 12.1 browser 账号态 profile 流程

账号态 browser 用例走 `playbooks/browser-auth-profile-playbook.md`，只使用 Playwright 沉淀和执行。

- 登录入口优先从代码推断：现有测试、路由、登录按钮链接、auth middleware、README、环境变量示例；推断不出或多入口冲突时才问用户。
- 本地 source profile 默认放 `~/.test-next-profile/<project-slug>/auth-source`，可用 `TEST_NEXT_SOURCE_PROFILE_DIR` 覆盖；真实 profile 不提交。
- source profile 必须由 headed Playwright 登录生成，不复制日常 Chrome 主 profile。
- 默认无头 `auth-check.spec.ts` 与业务 spec 直接复用 source profile；并发/CI 时才按 worker 复制临时 profile。
- 账号态 spec 不写死本机 profile 绝对路径；profile 由运行期 auth helper / auth config 注入，项目内沉淀业务 spec 和项目根 `playwright.config.ts`。
- 若页面缺少稳定 selector，优先给被测元素补 `data-testid` / 稳定 id，再生成 Playwright spec。

模板：

- `templates/browser-auth-config.template.ts`
- `templates/browser-auth-login.template.ts`
- `templates/browser-auth-check.spec.template.ts`
- `templates/playwright-fixtures.template.ts`

### 13. unit 断言行为优先（禁用实现细节）

频繁变更下，断言贴实现层就是短命；贴行为层才长寿。`SKILL.md §2.5` 加 Vitest / unit 特有禁用：

- `spy.toHaveBeenCalledTimes(N)` 当主断言 → 改用可观察返回 / 副作用
- `toEqual({...})` 写死整对象 → 改用 `toMatchObject` 断关键不变量
- 文案 / 枚举值硬编码 → import 常量或用正则
- 断私有字段 / 内部 state → 断公开 API
- `as any` 绕开类型 → mock 必须类型正确
- 一 `it()` 塞多个无关 expect → 拆成多 test

**为什么是禁用语而不是建议**：agent 看"建议"会两种都写让你选；看"禁用"会直接绕开，强制走行为层。

### 14. mock 腐烂防护（频繁变更最危险的失败模式）

**最危险的失败模式不是 fail，是假 pass**——mock 没跟上接口契约，测试通过但实际接口已经返回不同结构。silent，难发现。

`references/unit/mocking.md` 加三条防护：

- **type-driven mock**（禁手写 literal）：从 zod schema 或 TS 类型推导，schema 改了 mock 立刻报错
- **MSW handler 复用真实 schema**：handler 内部 `schema.parse(...)` 校验，后端改 schema → handler 报错
- **mock 同步检查清单**：每次改 API / schema / DB 必跑，搜 `vi.mock` + MSW handler 文件 + 全套 test

附腐烂症状速查（出现立刻查 mock）：手测对不上 / runtime 缺字段 / 共享 mock 改一处全套挂 / mock 是字面量不跟随 schema 演化。

### 15. 变更分类强制输出（Step 2 卡点）

`§1.1.4 Step 2` 的四象限分类（新增 / 修改 / 删除 / 保留）必须**显式输出清单 + 理由**，不可心算跳过。

**为什么强制**：agent 心算分类的准确率不高，特别是：

- 一变更同时触发多类（schema 改：删字段 + 改校验 + 加字段）
- 重命名变更（API 变行为不变）—— 旧 test 该改断言不该删
- 接口契约语义变化（`status 200 → 201`）边界模糊

写出清单 = 强制 agent 把每条决策落到字面，准确率涨明显，token 涨约 5%。

## 模式与路由边界


| 模式                  | 测试类型              | 说明              |
| ------------------- | ----------------- | --------------- |
| tdd                 | unit only         | 红绿重构，禁止 browser |
| post-change         | unit/browser/dual | 改后自验收           |
| explicit-generation | unit/browser/dual | 只生成任务，不执行       |


## 维护规则

以下改动必须回写本 README：

- 文件结构变化（新增/删除 playbook 或 reference）
- 模式边界变化（例如 TDD 放开 browser）
- harness 循环变更
- 核心规则源迁移

仅措辞润色、错字修复可不回写。
