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
│   └── explicit-generation-browser-playbook.md
├── references/
│   ├── browser/
│   │   ├── risk-axes.md
│   │   ├── scenarios.md
│   │   ├── ui-fidelity.md
│   │   ├── performance.md
│   │   └── tracking.md
│   └── unit/
│       ├── risk-axes.md
│       ├── scenarios.md
│       └── mocking.md
└── templates/
    └── bug-report.md
```

## 核心设计决策

### D1. `SKILL.md` 固定三层

- Layer 1: Fast Path（模式/类型/等级快速路由）
- Layer 2: Must Rules（不可违背规则）
- Layer 3: Routers（跳转到 playbook 与 reference）

目标：减少首屏信息量，同时保持执行一致性。

### D2. 按模式 × 测试类型拆 playbook

- 模式：`tdd` / `post-change` / `explicit-generation`
- 类型：`unit` / `browser`

目标：让执行流程可直接落地，避免在主文档堆细节。

### D3. 删除统一 test-case-list 模板

不再维护跨路径通用模板，改为在各 reference/playbook 保留本地化样例，减少跨文件耦合。

### D4. harness 自验证采用简化三步

1. 输出测试任务
2. 测试后更新任务
3. 输出修复建议（严重/一般/轻微）

若“严重 + 阻塞主流程”，必须标记“必须修复”。

### D5. unit references 去 stub 化

unit 侧从“方向提示”升级为“可执行任务模板”：

- 风险轴：触发条件、最小必测集、误测与跳过条件
- 场景表：每类场景最小任务集 + 样例
- mock 策略：决策树 + 级别选择 + 误区

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