# Browser API Mock

## 原则

- mock 前先观察真实响应：用 `page.on('response')` 或临时 explore spec sniff 一次后端 wire 格式。
- mock 只覆盖当前用例需要的接口，不把整条业务链路都 mock 掉。
- `route.fetch()` 可用于 pass-through，但不要默认依赖；cookie 转发、代理、上游慢或长轮询场景可能 hang。使用时加超时/错误兜底，失败后改为显式 mock。

## tRPC + superjson

tRPC 使用 superjson 时，mock 响应通常不是裸 `{ result: { data } }`，而要保留 wire 包装：

```ts
await route.fulfill({
  status: 200,
  contentType: 'application/json',
  body: JSON.stringify({
    result: {
      data: {
        json: {
          items: [],
        },
        meta: {
          values: {},
        },
      },
    },
  }),
});
```

如果真实响应没有 `meta` 或结构不同，以 sniff 到的响应为准，不要套模板硬造。
