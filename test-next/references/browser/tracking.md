# 埋点用例（按需触发）

**触发条件**（满足任一即必生成埋点用例，否则跳过）：

- 本次改动涉及埋点代码新增 / 修改 / 删除
- 改动落在 L4（流程类、高风险），且功能本身有埋点
- 用户明确要求生成埋点用例

**不满足触发条件时**：明确声明"未涉及埋点改动，跳过埋点"，不要硬写（与 SKILL.md §2.6 用户覆盖一致）。

## 用例方向（触发时按相关性挑）


| 事件类型                     | 用例方向                                |
| ------------------------ | ----------------------------------- |
| 曝光（impression / view）    | DOM 进入视口时 Network 看到上报；遮挡 / 不可见时不上报 |
| 点击（click）                | 点击触发时上报，点击 disable 态不上报             |
| 表单 change                | 关键字段改变时上报，不要每个 keystroke 都上报        |
| 表单 submit / submit_error | 成功 / 失败两条路径分别上报                     |
| 漏斗                       | 多步流程每步都上报，每段都不能掉                    |


## 验证手段

DevTools Network → filter `track` 或 `analytics` → 确认事件名、参数、时序对得上。

## 输出格式

```
[埋点] 提交按钮点击上报｜期望：Network 看到 POST /track，event=submit_click，含 form_id 字段｜P0｜DevTools Network
[埋点] 错误提示曝光上报｜期望：错误出现时 event=error_view，error_type 字段对得上｜P1｜DevTools Network
[埋点] 漏斗：登录 → dashboard → 首次创建｜期望：3 个 event 按顺序上报，每段都不缺｜P0｜DevTools Network
```

