## name: test-next

description: Use when代码改动后需要生成或执行测试任务（浏览器或单元），或用户要求TDD/测试用例。

# test-next

为改动生成测试任务，并在可运行时完成自验证与修复建议输出。

优先级：用户指示 > 项目级 `AGENTS.md` / `CLAUDE.md` > 本 skill。

## Layer 1: Fast Path

### 1) 先判工作模式


| 模式                    | 触发条件                     | 约束                            |
| --------------------- | ------------------------ | ----------------------------- |
| `tdd`                 | 用户明确提到 TDD / 先写测试 / 红绿重构 | `unit only`，必须 vertical slice |
| `post-change`         | 代码已改完，且可执行测试             | 按改动落点决定 unit/browser/双路径      |
| `explicit-generation` | 用户只要用例清单或工具不可用           | 只输出任务，不宣称已验证                  |


### 2) 再判测试类型（按改动落点，不按项目类型）


| 改动落点                                  | 路径      | 读取                     |
| ------------------------------------- | ------- | ---------------------- |
| UI / 路由 / DOM 可观察                     | browser | `references/browser/*` |
| 纯函数 / hook / service / router 非 UI 逻辑 | unit    | `references/unit/*`    |
| 同时涉及 UI 与逻辑                           | dual    | 两边都读                   |


### 3) 再判覆盖等级（L0-L4）


| 等级  | 典型改动                   |
| --- | ---------------------- |
| L0  | 文案/样式微调、工具函数一行修正       |
| L1  | 纯展示组件、纯函数              |
| L2  | 表单/交互/hook             |
| L3  | 数据流、接口、service         |
| L4  | mutation、状态机、流程编排、高风险域 |


估档规则：只能上调不能下调；`fix` 默认 +1；写操作至少 L4；支付/登录/权限/计费/迁移默认 L4。

### 4) 起步四问（开始生成前必须回答）

1. 测试目标是什么（1-3 行成功标准）
2. 本次等级是什么（L0-L4 + 一句话原因）
3. 本次边界是什么（只列新行为/新风险；重构与缺陷走特殊策略）
4. 当前走哪条路径（browser/unit/dual）

> 缺陷修复：必须有「复现 / 修复验证 / 回归」三类任务。  
> 重构：反转差量逻辑，验证改前=改后等价，不跳过模板层与邻居 smoke。

## Layer 2: Must Rules

### A. 任务字段（最小必填）

每条测试任务至少包含：

- 名称
- 前置条件
- 步骤
- 期望（必须是可观察行为，不测实现细节）
- 优先级（P0/P1/P2）
- 执行手段

L0/L1 可用一行式，L2+ 必须完整字段。

### B. 执行规则

- 一律 vertical slice：先跑 1-2 条 P0，再迭代扩展。
- 不得先列完全部任务再统一执行。
- 模板复用默认不重测模板稳定项，只测实例特异点；重构场景例外。

### C. 简化 harness 循环（必须执行）

#### Step 1: 输出测试任务

先给结构化任务清单，包含：

- `id`
- `priority`（P0/P1/P2）
- `severity_if_fail`（严重/一般/轻微）
- `blocker_if_fail`（是否阻塞主流程）
- `expectation`
- `executor`

#### Step 2: 测试后更新任务

逐条回填：

- `status`（pass/fail/skip）
- `evidence`（browser: console/network/log；unit: vitest 输出）
- `notes`（失败原因或跳过原因）

#### Step 3: 输出修复建议（按严重性排序）

统一输出三档：

1. 严重（阻塞主流程）
2. 一般
3. 轻微

规则：若为「严重 + 阻塞主流程」，必须显式标记 **必须修复**，不可作为“部分通过可交付”处理。

### D. 禁用语

以下表述出现即视为不合格：

- “应该没问题 / 看着差不多 / 正常情况下”
- 无明确期望的任务
- 无证据的“已通过”断言
- 实现细节断言（如内部函数调用次数、私有状态命中）
- 自称 TDD 但先实现再补测试
- RED 状态下进行 refactor

### E. 用户覆盖

---

- 用户指定“只测 X / 跳过 Y / 按 L3 / 不截图”等，立即覆盖默认策略。
- 不在 browser 可观察、也不在 unit 范畴的改动，明确声明“无测试任务”。

## Layer 3: Routers

### 1) Mode x Type Playbooks


| 模式    | 类型      | playbook                                            |
| ----- | ------- | --------------------------------------------------- |
| TDD   | unit    | `playbooks/tdd-unit-playbook.md`                    |
| 改后自验收 | unit    | `playbooks/post-change-unit-playbook.md`            |
| 改后自验收 | browser | `playbooks/post-change-browser-playbook.md`         |
| 显式生成  | unit    | `playbooks/explicit-generation-unit-playbook.md`    |
| 显式生成  | browser | `playbooks/explicit-generation-browser-playbook.md` |


### 2) References

#### Browser

- 风险轴：`references/browser/risk-axes.md`
- 场景库：`references/browser/scenarios.md`
- UI 还原：`references/browser/ui-fidelity.md`
- 性能：`references/browser/performance.md`
- 埋点：`references/browser/tracking.md`

#### Unit

- 风险轴：`references/unit/risk-axes.md`
- 场景库：`references/unit/scenarios.md`
- Mock 策略：`references/unit/mocking.md`

### 3) Templates

- Bug 报告：`templates/bug-report.md`

> 不再使用统一的 test-case-list 模板。每条路径在对应 reference/playbook 内使用专属样例格式。

