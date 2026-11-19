# 给 Gemini App 接入 GitHub MCP Server（自建 OAuth App 全流程）

## 1. 在 Gemini 侧新建 MCP 服务器并获取 Redirect URI

1. 打开 Gemini 连接器设置页：`https://gemini.google.com/customize/connectors`。
2. 如果之前装过旧版/精简版 GitHub 插件，先卸载避免工具路由冲突。
3. 点击 **Connect to an MCP server**，服务器地址填入：
   - `https://api.githubcopilot.com/mcp/`
4. 点击下方的 **复制重定向 URI（Copy Redirect URI）**，留待下一步使用。

## 2. 在 GitHub 注册个人 OAuth App

1. 打开 `https://github.com/settings/applications/new`。
2. 按下表填写（其余选项保持默认）：
   - **Application name**：全 GitHub 唯一，建议带个人标识（例如 `<your-handle>-gemini-mcp-2026`）
   - **Homepage URL**：`https://gemini.google.com`
   - **Authorization callback URL**：粘贴第 1 步复制出的 Redirect URI
3. 创建后记录 **Client ID**，并点击 **Generate a new client secret** 生成 **Client Secret**。

## 3. 回填凭据并完成授权

1. 回到 Gemini 连接器表单，填入 `Client ID` 与 `Client Secret`，点击 **Next → Connect**。
2. 在 Google 账号关联确认弹窗中点继续，跳转到 GitHub OAuth 页后点击 **Authorize**。
3. **可选（办公免逐次确认）**：在 Gemini 的 `@GitHub MCP Server` 详情页中，`App actions → Write / delete` 默认均为 `Always ask`，按需切换为 `Always allow`。

## 4. 权限边界说明（为什么写 `.github/workflows/` 会 403）

- 该 OAuth 授权会获得 `repo`（含私有仓库读写）、Issue、PR、分支等完整权限。
- **但不会申请 `workflow` scope**，且 GitHub 网页端 OAuth App 设置页不提供手动勾选 `workflow` 的开关——scope 完全由发起授权的客户端决定。
- 因此：日常代码读写、建仓、发 Issue、读评论、提 PR 均可由 Gemini 直接完成；**唯独 `.github/workflows/*.yml` 的首次写入或修改需要本地 `git push`（或带 `workflow` scope 的 `gh` CLI）推一次**。
