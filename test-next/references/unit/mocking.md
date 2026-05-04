# Mock 策略

目标：既避免外部依赖不稳定，又避免“测到的是 mock 不是业务行为”。

## 决策树（先问四个问题）

1. 这个依赖是否稳定且可本地运行？
2. 本次是否在验证业务逻辑，而不是依赖内部实现？
3. 不 mock 是否会引入非确定性（网络、时间、随机）？
4. mock 后是否还能验证可观察行为？

若第 3 条为是，优先 mock/stub；若第 4 条为否，降低 mock 粒度或改成集成路径。

## mock 级别选择


| 级别         | 何时使用               | 工具建议                             |
| ---------- | ------------------ | -------------------------------- |
| 不 mock     | 纯函数、稳定本地依赖         | 直接调用                             |
| stub 返回值   | 只需固定外部输入输出         | `vi.fn().mockResolvedValue(...)` |
| spy 行为观测   | 需保留真实实现但观测调用       | `vi.spyOn(obj, 'method')`        |
| 完全 mock 模块 | 外部 API/支付SDK/不可控依赖 | `vi.mock('module')` / MSW        |


## 依赖类型建议


| 依赖          | 推荐                                                |
| ----------- | ------------------------------------------------- |
| 纯函数 / 工具库   | 不 mock                                            |
| 外部 HTTP API | MSW（优先）                                           |
| 同项目 tRPC    | mock context + 直接调 procedure                      |
| Prisma / DB | 测试 schema 或 in-memory；不行再 mock                    |
| 时间 / 定时器    | `vi.useFakeTimers()` + `vi.advanceTimersByTime()` |
| 随机数         | `vi.spyOn(Math, 'random')` 或依赖注入                  |
| 文件系统        | memfs/mock-fs 或专用测试目录                             |
| 支付 SDK      | 总是 mock                                           |


## 常见误区

- 只断言 mock 调用次数，不断言业务结果。
- 自动 mock 全模块，导致行为偏离真实路径。
- 在全局保留 mock 状态，污染后续测试。

## 最小样例（本文件专属）

```text
[Mock决策] createInvoice 调用外部计费API
选择：完全 mock（外部网络不稳定）
理由：验证本地分支与错误映射，不验证第三方服务可用性
期望：429/500 被映射为业务错误码，UI可观察到失败态
```

## 与 harness 对齐

在测试任务中补齐：

- `severity_if_fail`（严重/一般/轻微）
- `blocker_if_fail`

失败后修复建议按严重性排序；若“严重 + blocker”则必须修复。