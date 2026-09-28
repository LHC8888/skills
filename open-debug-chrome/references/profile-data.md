# Profile 里有什么

完整 Chrome `--user-data-dir`。

| 路径 | 角色 |
|------|------|
| `~/.chrome-debug-profile` | 源 profile（`start`），**无数字后缀** |
| `~/.chrome-debug-profile-1` 等 | `clone-start` 并行实例（末尾数字） |

- **不会**从日常 Chrome `Default` 整盘拷贝 cookie / 登录态 / 书签 / `Secure Preferences` 等
- 扩展是另一回事：`start` / `clone-start` 默认用 `--load-extension` **引用**日常 `Default/Extensions`（挂载，不拷贝）；只有显式跑 `sync-extensions` 才会把扩展文件拷进调试 profile
- `clone-start` 从**调试源 profile**复制（含已有 cookie/登录态，跳过锁文件），不是从日常 Chrome 复制
- `cleanup-clones`：停并删除所有 `*-<N>`，只留源
- `reset-profile`：删源（需确认），不管 numbered clones

## 扩展

日常插件文件在 `…/Chrome/Default/Extensions/`，启停状态在 `Secure Preferences`（带校验，不能靠拷贝复用启用状态）。  
调试实例默认 `--load-extension` 指向日常 Extensions 下各扩展最新版本目录；要改成加载已同步副本，设 `CHROME_DEBUG_EXTENSIONS_FROM` 指向调试 profile 内的 Extensions。
