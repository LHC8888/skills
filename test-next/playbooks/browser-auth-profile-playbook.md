# Browser Auth Profile Playbook

## 适用条件

- browser 用例依赖登录态、权限、付费、配额、workspace、组织成员等账号状态。
- 用户希望本地无头跑 browser 测试，但登录过程需要人工完成或真实站点交互。

## 核心规则

1. 登录入口优先从代码推断，不预设配置文件位置。
2. 推断不出或存在多个合理入口时，才询问用户提供登录 URL。
3. source profile 必须是 headed Playwright 登录生成的专用 automation profile；不要复制日常 Chrome 主 profile。
4. 默认 `workers: 1`，无头测试直接使用 source profile；需要并发/CI 时才开启 per-worker hot-copy。
5. 有头模式只负责初始化/刷新登录态；无头模式只复用 profile 执行测试。
6. 持久化测试只用 Playwright；不要把临时浏览器引用或人工探索步骤写进 spec。

## 登录入口推断顺序

按顺序查找，找到后仍要验证它能到达登录/授权流程：

1. 现有 Playwright/Vitest/browser spec 中的登录、auth、profile、dashboard、workspace URL。
2. 应用路由与页面：`login`、`signin`、`auth`、`callback`、`account`、`workspace`、`dashboard`。
3. UI 入口：导航、登录按钮、`href`、`router.push`、`Link`、表单 action。
4. Auth 相关代码：middleware、guard、session provider、OAuth/SSO callback、401 redirect。
5. README、`.env.example`、开发脚本里出现的本地域名或登录说明。

询问用户的条件：

- 没找到任何入口。
- 找到多个入口且会进入不同环境或不同账号体系。
- 入口依赖外部 SSO/组织环境，代码无法判断应该用哪一个。

## 运行文件

默认把业务 spec 和项目根 `playwright.config.ts` 落到项目；auth helper / harness 运行文件放在系统临时目录，不写入项目。

```text
<tmp-runtime>/auth.config.ts
<tmp-runtime>/auth-login.ts
<tmp-runtime>/auth-check.spec.ts
<tmp-runtime>/fixtures.ts
```

从模板复制后按项目修改：

- `templates/browser-auth-config.template.ts`
- `templates/browser-auth-login.template.ts`
- `templates/browser-auth-check.spec.template.ts`
- `templates/playwright-fixtures.template.ts`

## Profile 约定

- 默认 source profile：`~/.test-next-profile/<project-slug>/auth-source`
- source profile 覆盖：`TEST_NEXT_SOURCE_PROFILE_DIR=/path/to/profile`
- 强制要求已初始化账号态：`TEST_NEXT_REQUIRE_AUTH_PROFILE=true`
- 兼容旧变量：`TEST_NEXT_PROFILE_DIR=/path/to/profile`
- 并发/CI 临时 profile base：`TEST_NEXT_PROFILE_BASE_DIR=/tmp/test-next-profile/<project-slug>`
- 禁止提交 profile 内容。
- 默认不补 `.gitignore`。运行产物在系统临时目录，认证 source profile 在 home 目录。

`<project-slug>` 从 `package.json` 的 `name`、仓库目录名或应用名派生，必须稳定、可读、hyphen-case。

## 执行流程

### Step 1 推断登录入口

输出简短证据：

```text
loginUrl: <url>
推断依据:
- <file>:<line> <why>
```

若不能确定，停止并询问用户提供登录 URL。

### Step 2 生成/更新 auth helper

创建或增量更新：

- `auth.config.ts`：导出 `sourceProfileDir`、`loginUrl`、`checkUrls`、`loggedInSignals`、`loginPageSignals`。
- `auth-login.ts`：headed 打开 `loginUrl`，让用户人工登录并保存 profile。
- `auth-check.spec.ts`：headless 复用 source profile，验证登录态仍有效。
- `fixtures.ts`：默认 `launchPersistentContext(sourceProfileDir)`；在 worker setup 内完成 require-auth 校验，并发时按 worker 复制临时 profile。

### Step 3 初始化登录态

运行 `auth-login.ts`，由用户在打开的浏览器中完成登录。

登录完成后关闭浏览器窗口；profile 留在 `~/.test-next-profile/<project-slug>/auth-source`。

### Step 4 无头校验

先跑 `auth-check.spec.ts`：

```bash
pnpm exec playwright test <tmp-runtime>/auth-check.spec.ts --config <tmp-runtime>/playwright.config.ts
```

失败策略：

- 命中登录页/登录失效信号：提示重新运行 `auth-login.ts`。
- 无法访问目标环境：报告环境问题，不改业务 spec。
- selector 不稳：回到源码添加持久化 id 后再写 spec。

### Step 5 写业务 spec

业务 spec 不写死 profile 路径；账号态 profile 由运行期 auth helper / auth config 注入，同一项目复用同一份项目根 `playwright.config.ts`。

账号态验证建议设置 `TEST_NEXT_REQUIRE_AUTH_PROFILE=true`，避免未登录时误用空 profile。默认项目配置使用 `workers: 1`。如果要并发跑账号态 browser spec，显式设置 `workers > 1`，并设置 `TEST_NEXT_COPY_PROFILE_PER_WORKER=true`，让 fixture 从 source profile 复制到每个 worker 的临时目录，避免多个 persistent context 抢同一个 `userDataDir`。

元素定位优先级：

1. `getByTestId`
2. `getByRole` + accessible name
3. `getByLabel` / `getByPlaceholder`
4. 稳定 id / class
5. 文本断言

若没有稳定定位方式，并且本次任务允许改源码，给被测元素添加持久化 id（如 `data-testid`）。添加 id 属于测试可维护性改动，保持范围只覆盖当前用例需要的元素。

## 增量更新规则

- 先读本轮 tmp runtime 中已有的 `auth.config.ts` / `auth-login.ts` / `auth-check.spec.ts`，不要重写稳定内容。
- 登录入口未变时，不改登录 helper。
- 新增账号态页面时，只补 `checkUrls` / `loggedInSignals` 或新增业务 spec。
- 代码改动触及登录、权限、workspace、配额时，先跑 `auth-check.spec.ts`，再跑受影响业务 spec。
