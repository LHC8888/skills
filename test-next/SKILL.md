---
name: test-next
description: Use when code changes need unit or browser test tasks, or when the user requests TDD or test cases.
metadata:
  author: Summer
---

# test-next

## 1. Fast Path

### 1.1 前置检查（环境 + 现有测试）

#### 1.1.1 测试环境（先决条件）

走任一路径前必须验证依赖 + 配置就位。**任一项缺失 → 提示用户配置；用户拒绝 / 暂不配置 → fallback `explicit-generation` 模式**（只生成 spec/test 文件，不跑），等环境就位再回来跑。


| 路径      | 必需                                                                                                                | 缺失时提示用户                                                                                                                                                              |
| ------- | ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| browser | `package.json` 含 `@playwright/test`；默认把有效 spec 和项目根 `playwright.config.ts` 保存到项目内，fixtures/auth helper 等 runtime harness 由 skill 在系统临时目录生成 | `pnpm add -D @playwright/test && pnpm exec playwright install chromium` |
| unit    | `package.json` 含 `vitest`                                                                                          | `pnpm add -D vitest`                                                                                                                                                 |

账号态 browser 测试额外要求：

- 若用例需要登录态，先读 `playbooks/browser-auth-profile-playbook.md`。
- 登录入口默认**从代码推断**：路由、登录按钮链接、auth middleware、README、已有测试、环境变量示例。只有推断不出或存在多个合理入口时才询问用户。
- 本地测试 profile 必须是 headed Playwright 登录生成的专用 automation profile，默认放 `~/.test-next-profile/<project-slug>/auth-source`，可用 `TEST_NEXT_SOURCE_PROFILE_DIR` 覆盖；不要复制日常 Chrome 主 profile，真实 profile 内容不提交。
- 生成/更新 browser spec 时，若稳定 selector 不足，应优先给被测元素补持久化 id（如 `data-testid`），再写 Playwright 断言。

> 不要静默生成跑不起来的测试。先确认环境，再生成。

环境就位后，扫被测模块 / 页面根目录是否已有测试文件：

- 单测：`<file>.test.ts(x)` 与被测文件同目录
- 浏览器：`<file>.spec.ts`（Playwright spec）与被测文件同目录

按结果分流：

#### 1.1.2 spec-zero 探针（browser 必做）

写第一条 browser spec 前，先用轻量探针确认环境，而不是把假设写进 spec 后再调试。探针结果必须能回填到 §1.5 起步四问。

1. baseURL 探活：目标服务返回 2xx / 3xx，不能是 5xx 或 connection refused。
2. 访问被测路径：确认无登录态下是正常渲染、重定向、空态，还是命中 auth gate。
3. 关键 DOM：确认被测组件根或触发入口在合理等待时间内出现。

任一项无法确认时，先询问用户补齐 baseURL、是否需要登录、被测组件实际入口路径；不要在 spec 里写一堆假设再跑挂。

#### 1.1.3 全新模式（无现有测试）

按 §1.2-1.5 + §2.1 / §2.4 完整流程生成新文件。

#### 1.1.4 增量模式（有现有测试）

**默认禁止重写已覆盖的稳定用例**（除非用户明确说"重生成全部"）。按 4 步处理：

**Step 1 — 读已有用例**

- Read 现有 `<file>.test.ts(x)` / `<file>.spec.ts`
- 提取所有 `test('...')` / `it('...')` block 的**标题 + 关键断言** → 列出「已覆盖维度清单」（如 "登录主流程"、"密码错误提示"、"配额超限态"）

**Step 2 — 对齐本次变更，分类处理**

列出本次代码变更引入的新行为 / 新风险（§1.5 起步四问第 3 问），与「已覆盖维度清单」对照分四类：

| 分类     | 触发条件                              | 动作                                |
| ------ | --------------------------------- | --------------------------------- |
| **新增** | 变更引入的行为，已有用例未覆盖                   | 新增 `test('...')` block            |
| **修改** | 变更触及已有 test 的断言（接口变 / 文案变 / 行为变） | 改对应断言，**保留 test 名**便于跟踪           |
| **删除** | 变更删除了某功能                          | 删除对应 test                         |
| **保留** | 变更未触及的稳定用例                        | **不动**——不重写、不格式化、不改风格     |

**必须显式输出分类清单**（不可心算跳过 —— 心算准确率断崖，特别是「重命名 / 契约语义变化 / 一变更触发多类」时）：

```text
[变更分类]
- 新增:
  - test('[P0] 新增字段 maxLength 校验') ← schema 加了 maxLength=100
- 修改:
  - test('[P0] 创建订单返回值') 改断言 status 200 → 201 ← 接口契约调整
- 删除:
  - test('legacy validateOldFormat') ← 函数已删除
- 保留（不动）:
  - test('[P0] 登录主流程')
  - test('[P0] 密码错误提示')
  - test('[P1] 配额超限态')
  ... (列全部稳定 test 名)
```

> 写出清单 + 理由后再进 Step 3。这是变更准确率的关键卡点，不可省。

**Step 3 — 用例去重（§2.3 去重 pass）**

新增 / 修改的 test 之间、与已覆盖清单之间做去重，合并 `precondition` / `steps` / `expectation` 相同的项。

**Step 4 — Edit 增量改动 + 跑全套验证**

- 用 Edit 工具最小化改动（保留 `import` / `test.describe` / 公共 setup / 稳定 test block）—— **禁止 Write 整文件**
- 跑全套（含稳定 test），确认无回归
- 稳定 test 失败 → 视为本次变更引发的回归，按 §2.4.3 现场分级

> 关键：测试代码跟着源文件**渐进式变更**，每次只动 diff 涉及的部分。

### 1.2 先判工作模式与交付模式


| 模式                    | 触发条件                     | 约束                            |
| --------------------- | ------------------------ | ----------------------------- |
| `tdd`                 | 用户明确提到 TDD / 先写测试 / 红绿重构 | `unit only`，必须 vertical slice |
| `post-change`         | 代码已改完，且可执行测试             | 按改动落点决定 unit/browser/双路径      |
| `explicit-generation` | 用户只要用例清单或工具不可用           | 只输出任务，不宣称已验证                  |


交付模式是独立维度，默认先判：

| 交付模式 | 触发条件 | 约束 |
| --- | --- | --- |
| `persist-spec` | 默认 | 把有效测试用例代码和项目根 `playwright.config.ts` 沉淀到项目目录；browser spec 与被测模块同级；fixtures / auth helper / trace / report 仍在系统临时目录；不创建 `tests/` / `tests/browser-harness/`，不改 `.gitignore` |
| `report-only` | 用户显式要求“一次性验证”“不要留下文件”“只出报告” | playwright config、harness、spec 全部生成在系统临时目录（如 `$TMPDIR/test-next/<repo-slug>/<run-id>/`）；运行时 cwd 仍是项目根；`outputDir` / HTML reporter / trace / video 都指向 tmp；跑完直接输出问题清单 + 修复建议，不在项目内留文件，也不询问是否保留 |

唯一允许跨 report-only / persist 复用的本地工件是认证 source profile：`~/.test-next-profile/<project-slug>/auth-source`。它位于 home 目录，不污染项目工作区。

### 1.3 再判测试类型（按改动落点，不按项目类型）


| 改动落点                                  | 路径      | 读取                     |
| ------------------------------------- | ------- | ---------------------- |
| UI / 路由 / DOM 可观察                     | browser | `references/browser/*` |
| 纯函数 / hook / service / router 非 UI 逻辑 | unit    | `references/unit/*`    |
| 同时涉及 UI 与逻辑                           | dual    | 两边都读                   |


**金字塔决策原则（强制）**：本 skill 只用两个工具栈——**Vitest**（纯函数 / hook / service / React 组件渲染 / pure logic）和 **Playwright**（真实浏览器 / 真实 DOM 事件 / SSR / 路由 / 视觉 / 跨页流程 / 探索性测试）。

- 能用 Vitest 测就 Vitest（更快 / 更便宜 / 更稳）
- Vitest 测不动才上 Playwright（Vitest 模拟 DOM 不够真实——真实事件 / 跨页路由 / SSR 一致性 / 视觉对比 / 真实网络）
- dual 仅当两边都有不可替代的覆盖维度
- **禁止引入第三方测试工具**（Cypress / WebdriverIO / Selenium 等）

### 1.4 再判覆盖等级（L0-L4，影响面）

覆盖等级表达**影响面 / 改动复杂度**——决定测试粒度（生成多深、是否邻居 smoke、是否触发 §3.2.1 横切维度）。**与 §2.2 优先级（P0-P2，修复 / 测试优先级）是两个独立维度**：高 level 改动下面可以有 P0/P1/P2 任意优先级的任务；同一个 priority 下，任务的 level 也可能跨 L1（纯函数）到 L4（mutation）。


| 等级  | 典型改动                   |
| --- | ---------------------- |
| L0  | 文案/样式微调、工具函数一行修正       |
| L1  | 纯展示组件、纯函数              |
| L2  | 表单/交互/hook             |
| L3  | 数据流、接口、service         |
| L4  | mutation、状态机、流程编排、高风险域 |


估档规则：只能上调不能下调；`fix` 默认 +1；写操作至少 L4；支付/登录/权限/计费/迁移默认 L4。

### 1.4.5 被测对象代码摸排（写 spec 前必做）

执行 agent 必须在 3 分钟内摸清被测对象的入口与触发链，再进入 §1.5。输出五项内容：

1. 被测对象在哪些 UI 路径下被实例化（grep 消费方）。
2. 输入边界：props、hook 参数、订阅的 store selector。
3. 输出契约：发出的请求形态、渲染产物、对外部 store 的副作用。
4. 触发链：用户操作 → prop / state 变化 → effect → query → DOM。
5. 会影响触发但不属于被测对象的因素：兄弟组件、lazy-mount、hydration gate、idle 调度、modal portal。

### 1.5 起步四问（开始生成前必须回答）

先完成 §1.4.5 被测对象代码摸排；browser 路径还必须完成 §1.1.2 spec-zero 探针。下面四问的回答要引用摸排 / 探针结论。

1. 测试目标是什么（1-3 行成功标准）
2. 本次等级是什么（L0-L4 + 一句话原因）
3. 本次边界是什么（只列新行为/新风险；重构与缺陷走特殊策略）
4. 当前走哪条路径（browser/unit/dual）

> 缺陷修复：必须有「复现 / 修复验证 / 回归」三类任务。  
> 重构：反转差量逻辑，验证改前=改后等价，不跳过模板层与邻居 smoke。  
> 改动若涉及账号态（登录/付费/配额）或环境差异（视口、locale、网络、浏览器内核、SSR），按 `references/{browser,unit}/risk-axes.md` 选正交组合。

## 2. Must Rules

### 2.1 任务字段（统一定义，所有 playbook 共用）

每条测试任务必填：

- `id`
- `name` / 名称（一句话概括）
- `level`（L0-L4，**影响面 / 改动复杂度**，按 §1.4 标准判定）
- `priority`（P0/P1/P2，**修复 / 测试优先级**，按 §2.2 标准判定）
- `expectation` / 期望（必须可观察行为，不测实现细节）
- `executor` / 执行手段（vitest / playwright / manual）

> `level` 与 `priority` 是两个独立维度：影响面（L）回答"这条用例覆盖多深"，优先级（P）回答"这条先跑 / 失败先修"。同一个 L 下可有 P0/P1/P2 任务；同一个 P 下任务的 L 也可能跨度很大。

L2+ 必须额外包含：

- `precondition` / 前置条件（账号态 / 视口 / mock 状态等）
- `steps` / 步骤

L0 / L1 可用一行式：`name｜expectation｜level｜priority`。

执行后回填：

- `status`（pass / fail / skip）
- `evidence`（按路径：browser = console / network / log；unit = vitest 输出）
- `notes`（失败原因 / 跳过原因）

> `severity` 与 `blocker` **不作为预填字段**——`priority` 已隐含失败严重性 × 触发概率；失败后的严重性由 §2.4.3 基于 `evidence` 现场分级。

### 2.2 优先级判断标准

`priority` 表达**修复 / 测试优先级**（哪条先跑、失败先修），与 §1.4 覆盖等级（影响面）独立 —— 两者各回答各自的问题，不要混着打。

按 **(失败严重性 × 触发概率)** 二维矩阵判定：


| 严重性 \ 概率                  | 高频（必跑路径） | 中频（常见路径） | 低频（边角/探索） |
| ------------------------- | -------- | -------- | --------- |
| **严重**（阻塞主流程 / 数据丢失 / 安全 / 涉及钱） | P0       | P0       | P1        |
| **中**（影响体验但可恢复）           | P0       | P1       | P2        |
| **轻**（视觉 / 微动效 / 极端边界）    | P1       | P2       | P2        |


快速规则（命中任一即对应等级）：

- **P0**：业务核心路径 / 涉及钱-数据-安全 / 改动直接命中 / 失败阻塞主流程
- **P1**：边界条件 / 错误处理 / 相邻路径 / 失败影响体验但不阻塞
- **P2**：罕见极端 / 探索发现 / 视觉细节 / 失败影响小且可恢复

### 2.3 执行规则

- 一律 vertical slice：先跑 1-2 条 P0，再迭代扩展。
- 不得先列完全部任务再统一执行。
- 模板复用默认不重测模板稳定项，只测实例特异点；重构场景例外。
- **生成清单后必须做去重 pass**：风险轴 + 场景库 + 邻居 smoke 多源展开会重复，合并 `precondition` / `steps` / `expectation` 相同的任务，保留覆盖维度更广的版本。

### 2.4 简化 harness 循环（必须执行）

#### 2.4.1 输出任务清单

按 §2.1 字段生成结构化任务，先 1-2 条 P0（vertical slice）。生成完先做 §2.3 去重 pass，再开跑。persist-spec 模式下，把有效测试代码和项目根 `playwright.config.ts` 沉淀到项目；runtime fixtures / auth helper 写到系统临时目录，运行 cwd 保持项目根。

persist-spec 的 Playwright 配置落盘规则：

- 若项目根已有 `playwright.config.ts` / `playwright.config.mts` / `playwright.config.js`，优先增量修改现有配置。
- 若项目根没有 Playwright config，必须从 `templates/playwright-config.template.ts` 创建 `playwright.config.ts`。
- 配置里必须让 `testMatch` 覆盖同目录 `*.spec.ts`，因为 browser spec 默认不放 `tests/`。
- 配置里的 `outputDir`、HTML report、trace/video 产物默认指向系统临时目录或 env 覆盖路径，避免项目根出现 `test-results/` / `playwright-report/`。
- 不创建 `tests/` / `tests/browser-harness/`，不为了运行产物补 `.gitignore`。

#### 2.4.2 测后回填

按 §2.1 回填字段（`status` / `evidence` / `notes`）。

persist-spec 模式需要把有效用例和项目根 `playwright.config.ts` 沉淀到项目文件后再结束；report-only 模式的报告就是终点，不追加“要保留 spec 吗”这类对话回合。

#### 2.4.3 修复建议（基于 evidence 现场分级，**不预填**）

- **必须修复**：P0 失败 + 阻塞主流程（数据丢失 / 安全 / 钱 / 阻断核心路径）—— 不可作为“部分通过可交付”
- **严重**：P0 失败但不阻塞 —— 建议尽快修
- **一般**：P1 失败
- **轻微**：P2 失败 / 视觉细节

> 是否阻塞主流程由 evidence 决定（接口失败 + 跳转中断 + 报错 toast 全屏…），生成任务时不预测；事前打 `priority`，事后基于 evidence 分严重性。

### 2.5 禁用语

以下表述出现即视为不合格：

- “应该没问题 / 看着差不多 / 正常情况下”
- 无明确期望的任务
- 无证据的“已通过”断言
- 实现细节断言（如内部函数调用次数、私有状态命中）
- 自称 TDD 但先实现再补测试
- RED 状态下进行 refactor
- 未列出被测对象消费方与触发链就编写 spec
- browser 路径没做 §1.1.2 spec-zero 探针就开始写 spec

**Vitest / unit 特有禁用**（断言**行为**不断言**实现**）：

- `spy.toHaveBeenCalledTimes(N)` 当主断言 → 主断言用可观察返回 / 副作用，调用次数仅辅证
- `expect(obj).toEqual({...})` 写死整对象 → 用 `toMatchObject({key: value})` 断关键不变量（接口加字段不会假 fail）
- 文案 / 枚举值硬编码（`expect(msg).toBe('提交成功')`）→ import 常量或用正则 `/成功/`
- 断私有字段 / 内部 state（如 `component.state._cache`）→ 断公开 API / 可观察输出
- `as any` 绕开类型错误塞 mock → mock 必须类型正确（schema / 类型推导，详见 `references/unit/mocking.md`）
- 一个 `it()` 塞多个无关 expect → 拆成多 test，一 test 一主断言

**Playwright 特有禁用**：

- 位置 selector（`:nth-child` / `:nth-of-type` / `> div > div`）→ 用 `getByTestId` / `getByRole` / `getByText`
- `page.waitForTimeout(N)` 硬等 → 用 `expect(locator).toBeVisible()` 等隐式等待
- 默认用 `networkidle` 等 SaaS 页面稳定 → 用 `page.goto(url, { waitUntil: 'domcontentloaded' })` + 业务 locator 的 visibility / text / URL 断言
- 漏 `await`（如 `expect(...)` / `page.click(...)` 未 await）→ 全 `await`
- `console.log(...)` 当断言 → 用 `expect(...).toXxx(...)` 内置断言
- spec 里写业务逻辑 / fixture 数据 → 测试只验断言，业务在 source
- 账号态用例写死本机 profile 绝对路径 → profile 由运行期 auth helper / auth config 注入；项目内持久 spec 只依赖公共 Playwright config，不引用 tmp harness
- 无稳定 selector 时强行写脆弱 selector → 优先给源码元素添加持久化 id（如 `data-testid`），并把它纳入本次 diff
- 跨容器直接按同 role+name 查元素（如多个 `All` tab）→ 先 scope 到 dialog/menu/region，再 `getByRole(...)`

### 2.6 用户覆盖

---

- 用户指定“只测 X / 跳过 Y / 按 L3 / 不截图”等，立即覆盖默认策略。
- 不在 browser 可观察、也不在 unit 范畴的改动，明确声明“无测试任务”。

## 3. Routers

### 3.1 Mode x Type Playbooks


| 模式    | 类型      | playbook                                            |
| ----- | ------- | --------------------------------------------------- |
| TDD   | unit    | `playbooks/tdd-unit-playbook.md`                    |
| 改后自验收 | unit    | `playbooks/post-change-unit-playbook.md`            |
| 改后自验收 | browser | `playbooks/post-change-browser-playbook.md`         |
| 显式生成  | unit    | `playbooks/explicit-generation-unit-playbook.md`    |
| 显式生成  | browser | `playbooks/explicit-generation-browser-playbook.md` |
| 账号态 browser | browser | `playbooks/browser-auth-profile-playbook.md`        |


### 3.2 References

#### 3.2.1 Browser

- 风险轴：`references/browser/risk-axes.md`
- 场景库：`references/browser/scenarios.md`
- UI 还原：`references/browser/ui-fidelity.md`
- 性能：`references/browser/performance.md`
- 埋点：`references/browser/tracking.md`
- API mock：`references/browser/api-mock.md`
- 账号态 profile：`playbooks/browser-auth-profile-playbook.md`

#### 3.2.2 Unit

- 风险轴：`references/unit/risk-axes.md`
- 场景库：`references/unit/scenarios.md`
- Mock 策略：`references/unit/mocking.md`

### 3.3 Templates

- Bug 报告：`templates/bug-report.md`
- Browser auth 配置：`templates/browser-auth-config.template.ts`
- Browser auth 登录脚本：`templates/browser-auth-login.template.ts`
- Browser auth 校验 spec：`templates/browser-auth-check.spec.template.ts`
- Playwright 配置：`templates/playwright-config.template.ts`
- Playwright fixtures：`templates/playwright-fixtures.template.ts`

模板适用模式：

| 模板 | 模式 |
| --- | --- |
| `templates/playwright-config.template.ts` | `[persist-spec]` 必须写入/合并到项目根 `playwright.config.ts`；`[report-only]` 写入 tmp |
| `templates/playwright-fixtures.template.ts` | `[runtime-only]` 写入 tmp，不写入项目；项目内持久 spec 不引用它 |
| `templates/browser-auth-config.template.ts` | `[runtime-only]` 写入 tmp；不写入项目 |
| `templates/browser-auth-login.template.ts` | `[runtime-only]` 写入 tmp；不写入项目 |
| `templates/browser-auth-check.spec.template.ts` | `[runtime-only]` 写入 tmp；不写入项目 |
| `templates/bug-report.md` | `[runtime-only]` |

> 不再使用统一的 test-case-list 模板。每条路径在对应 reference/playbook 内使用专属样例格式。
