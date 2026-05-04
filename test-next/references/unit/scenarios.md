# 单元测试场景表

本表给“最小可执行任务模板”，用于直接产出任务而不是只给方向。

## 1) 纯函数 / utility

最小任务集：

- happy path 1 条
- 边界值 1-2 条
- 非法输入 1 条（throw 或 error return，按约定）

样例：

```text
[单测] formatDuration-边界值
前置条件：输入 0、59、60
步骤：调用 formatDuration
期望：分别输出 "0s"、"59s"、"1m"
优先级：P1
执行：Vitest
```

## 2) React 组件（Testing Library）

最小任务集：

- render 正常
- 关键交互 1 条
- 可访问性 query 1 条（优先 role/label）

样例：

```text
[单测] SubmitButton-disable到enable
前置条件：必填项未填 -> 填齐
步骤：render 后触发输入变化
期望：按钮从 disabled 变为可点击
优先级：P0
执行：Vitest + @testing-library/react
```

## 3) React hook（renderHook）

最小任务集：

- 初始状态
- 状态迁移
- effect 清理

样例：

```text
[单测] usePolling-卸载清理
前置条件：interval=1000
步骤：mount -> unmount
期望：轮询定时器被清理，不再触发回调
优先级：P0
执行：Vitest + renderHook + fakeTimers
```

## 4) Service / tRPC procedure

最小任务集：

- 入参合法/非法各 1 条
- 核心业务分支 1 条
- 错误传播 1 条

样例：

```text
[单测] createOrder-非法入参拒绝
前置条件：amount=-1
步骤：调用 procedure
期望：返回/抛出可识别的业务错误
优先级：P0
执行：Vitest + mock ctx
```

## 5) 异步函数

最小任务集：

- resolve
- reject
- timeout 或 cancel（至少其一）

## 6) 状态机 / 复杂逻辑

最小任务集：

- 所有合法转移
- 至少 1 条非法转移拒绝
- 1 条中断恢复或并发协调

## 7) 输出口径（与 harness 对齐）

生成任务时必须含：

- `id`
- `priority`
- `severity_if_fail`
- `blocker_if_fail`
- `expectation`
- `executor`

执行后回填：

- `status`
- `evidence`（Vitest summary + stack）
- `notes`

