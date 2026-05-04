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

1. 先跑 1-2 条 P0 主流程任务。
2. 收集三通道证据并更新任务状态。
3. 根据证据增删后续任务（而非先列完再跑）。
4. 覆盖触发的横切维度与邻居 smoke。

## Harness 对接（三步）

### Step 1 输出测试任务

```text
- id
- priority
- severity_if_fail
- blocker_if_fail
- expectation
- executor=browser/manual/playwright
```

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

## 回退策略

- 无法复现：补环境前置（账号态、视口、网络、locale）。
- 断言模糊：改为可量化期望（px/hex/ms/fps/status code）。

