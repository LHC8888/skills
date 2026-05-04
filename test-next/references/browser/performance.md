# 性能（按需触发）

**触发条件**（满足任一即必生成性能用例）：

- 改了**列表渲染**（含分页、无限滚动、虚拟列表）
- 改了**大数据**展示（>100 项 / >1MB JSON / 大图大视频）
- 改了**关键转化路径**（首页、登录、支付、生成入口）的渲染策略
- 改了**bundle 体积影响因素**（新依赖、动态 import、SSR/CSR 切换）
- 用户明确要求测性能

**不满足时**：在 SKILL.md §7 用例清单的「⊘ 不生成」栏写"未涉及性能敏感改动，跳过性能"。

## 用例维度


| 维度            | 用例方向                                       | 验证手段                                     |
| ------------- | ------------------------------------------ | ---------------------------------------- |
| **首屏指标**      | LCP < 2.5s / FCP < 1.8s / TTI < 3.5s（关键页）  | Lighthouse / Chrome DevTools Performance |
| **运行时帧率**     | 大列表滚动 ≥ 50 fps，不卡顿；动画过渡平滑                  | Chrome DevTools Performance Frames       |
| **内存**        | 长开页面 / 反复跳转无明显泄漏（heap snapshot diff < 10%） | DevTools Memory Profiler                 |
| **大数据渲染**     | 1000 条列表渲染时长 < 500ms；超过用虚拟列表               | 注入 mock 数据测                              |
| **重渲染**       | 关键交互不引发 N+1 重渲染                            | React DevTools Profiler                  |
| **图片加载**      | 首屏图懒加载、占位图无 CLS、retina srcset 生效           | Network + DevTools 看图大小                  |
| **bundle 增长** | 新引入依赖未让首屏 JS 增加 > 50KB（gzipped）            | 构建产物对比 / Bundle Analyzer                 |


## 性能用例的特点

性能用例和功能用例不同：

- **期望必须是数值阈值**（不能是"快"/"流畅"）
- **执行手段必须是工具量取**（DevTools / Lighthouse / Profiler，不能凭感觉）
- **每条用例附环境**（哪种网络、哪种 CPU 节流、哪种设备模拟）
- **基线对比**：重构 / 性能优化类改动必须给"改前 / 改后"两个数值

## 输出格式

```
[性能] 详情页首屏 LCP｜期望：< 2.5s（4G 网络、Macbook Pro M1 / Chrome）｜P0｜Lighthouse
[性能] 1000 条列表滚动 fps｜期望：≥ 50 fps，无明显掉帧（DevTools Performance Frames）｜P1｜Chrome DevTools
[性能] bundle 大小变化｜期望：首屏 JS gzipped 增加 < 50KB（改前 X KB / 改后 Y KB）｜P0｜构建对比
```

## 禁用语（性能用例特有）

- "快了 / 慢了" → 给数值（具体多少 ms / fps / KB）
- "流畅 / 卡顿" → 量化（fps 数值、长任务数量）
- "差不多" → 量化阈值

