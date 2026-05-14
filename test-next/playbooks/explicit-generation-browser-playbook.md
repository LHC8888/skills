# Explicit-generation Browser Playbook

## 适用条件

- 用户只要求“生成测试任务”，不要求执行
- 或当前环境不可运行 browser 测试

## 输入

- 改动边界
- 覆盖等级
- 触发维度（UI 还原度/性能/埋点）

## 输出

- 可执行的 browser 任务清单（标注“未验证可跑性”）
- 预估风险与建议优先级

## 执行步骤

1. 若任务依赖账号态，先输出登录入口推断结果；推断不出时标注“需用户提供登录 URL”，不要编造。
2. 先产出主流程 P0 任务，再补 P1/P2。
3. 对触发维度输出量化断言（视觉/性能/埋点）。
4. L2+ 增加邻居 smoke 任务。
5. 需要登录态的用例必须引用 `browser-auth-profile-playbook.md` 的 profile 方案：默认 `~/.test-next-profile/<project-slug>/auth-source`，由 headed `auth-login.ts` 初始化，headless spec 复用；不要建议复制日常 Chrome 主 profile。
6. 若页面缺少稳定 selector，在任务中写明需要给对应元素补持久化 id（如 `data-testid`），再生成 Playwright spec。

## Harness 对接（三步，仅文档态）

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

当前不执行，统一填：

```text
- status: skip
- notes: 未执行，待本地/CI验证
```

### Step 3 风险建议

当前没有执行证据，不输出“必须修复”或交付阻断结论。只按设计风险标注验证优先级：

- 高风险候选：优先本地 / CI 执行验证
- 一般风险候选：随主路径后验证
- 低风险候选：可延后或合并到回归验证

如果设计风险看起来可能阻塞主流程，写成“建议优先验证该用例”，等有 `evidence` 后再按 SKILL.md §2.4.3 分级。
