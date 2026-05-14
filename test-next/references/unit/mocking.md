# Mock 策略

目标：既避免外部依赖不稳定，又避免"测到的是 mock 不是业务行为"。

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


## 频繁变更下的腐烂防护（关键）

**最危险的失败模式不是 fail，是假 pass**——接口契约变了，mock 没跟上 → 测试通过但实际接口已经返回不同结构。silent，难发现，频繁变更项目必须按下列三条防护。

### 防护 1：type-driven mock（强制，禁手写 object literal）

不要凭脑子写 mock 数据结构。从 schema / 类型推导，让 TS / zod 替你卡变更。

**好 — zod schema 推导**：

```ts
import { createOrderInputSchema } from '@/server/schemas'

const validInput = createOrderInputSchema.parse({
  amount: 100,
  productId: 'p_1',
})
// schema 字段加 / 删 / 改类型 → parse 立刻 throw
```

**好 — TS 类型 + factory**：

```ts
import type { Order } from '@loc/prisma'

const mockOrder = (overrides?: Partial<Order>): Order => ({
  id: 'o_1',
  amount: 100,
  status: 'pending',
  createdAt: new Date(),
  ...overrides,
})
// Order 加字段 → TS 立刻报错（factory 不全）
```

**坏 — 手写 literal**：

```ts
const mockOrder = { id: 'o_1', amount: 100 }
// Order 加 10 个字段也不会报错，runtime 才崩 / silent 假 pass
```

### 防护 2：MSW handler 复用真实 schema

外部 HTTP / 内部 tRPC 的 mock handler，**用真实 response schema 校验自己的输出**：

```ts
import { rest } from 'msw'
import { createOrderResponseSchema } from '@/server/schemas'

rest.post('/api/order', (_req, res, ctx) => {
  const body = createOrderResponseSchema.parse({
    id: 'o_1',
    status: 'pending',
  })
  return res(ctx.json(body))
})
// 后端改 response schema → handler 内部 parse 立刻报错
```

handler 不是脱离 schema 的"自由捏造"，而是 schema 实例化的产物。

### 防护 3：mock 同步检查清单（改 API / schema / DB 必跑）

按顺序检查：

- [ ] 该 API 的所有 mock 文件（搜 `vi.mock` / MSW handler）是否报 TS 错？
- [ ] 字段重命名 / 含义变化时，断言语义是否仍合理？（不只是 TS 通过）
- [ ] fixture / factory 函数是否同步更新？
- [ ] 全套 `pnpm test` 跑一遍 → 看 type error + test fail 综合报告
- [ ] 共享 mock（多文件 import 同一份）改动后，跑所有调用方的 test

### 腐烂症状（出现立刻查 mock）

- 测试 pass，手测发现接口实际返回结构不同
- TS 编译过，runtime 报 mock 字段缺失
- 多个 test 共用一份 mock，改一处全套挂 → 说明 mock 散在各文件没收口
- mock 数据是字符串 / 数字字面量，不可能跟着 schema 演化
- 测试断言文案 / 枚举值与 source 里的常量不一致

## 常见误区

- **只断言 mock 调用次数**当主断言（如 `toHaveBeenCalledTimes(1)`）→ 实现细节，重构必碎；调用次数只能作辅证
- **自动 mock 全模块**（`vi.mock('@/lib/foo')` 不传 factory）→ 行为偏离真实路径，测了个寂寞
- **全局保留 mock 状态**，污染后续测试 → `beforeEach` 必须 reset / `vi.clearAllMocks()`
- **手写 mock 数据 literal**，schema 改了不报错 → 见防护 1
- **mock 与真实接口契约脱节**，silent 假 pass → 见防护 2 + 3

## 最小样例（本文件专属）

```text
[Mock决策] createInvoice 调用外部计费API
选择：完全 mock（外部网络不稳定）
理由：验证本地分支与错误映射，不验证第三方服务可用性
期望：429/500 被映射为业务错误码，UI 可观察到失败态
mock 来源：复用 server/schemas/invoiceResponseSchema 推导（防护 1+2）
```
