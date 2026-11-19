# gemini-mac-github-bridge

> **Gemini App + GitHub MCP + macOS Self-Hosted Runner 远程本地控制通道**：不依赖 Actions Dispatch / Artifact 下载接口，直接用 **GitHub Issues 作为异步 RPC 通道**，支持多槽位并发执行、防休眠常驻与完整登录 `zsh` 权限。

## 架构与设计动机

与 [claude-codex-github-loop](https://github.com/ychenfen/claude-codex-github-loop) 不同，Gemini 通过 `api.githubcopilot.com/mcp/` 接入 GitHub 后，具备仓库读写、建仓、分支、PR 和 **Issue / Issue Comment** 权限，但**不暴露 `workflow_dispatch` 与 Artifact 下载 API**，且 OAuth token 不含 `workflow` scope。

本方案用最轻量的闭环绕开这两点限制：

```text
Gemini App (GitHub MCP)
   │  1. issue_write: 创建标题以 [gemini-run] 开头的 Issue（正文含 JSON / 代码块命令）
   ▼
GitHub Private Repo (main 分支)
   │  2. on: issues: [opened] 自动触发 + authorize 校验仅限仓库 Owner 本人
   ▼
macOS Self-Hosted Runners (1..N 个并发槽位, 标签 mac-bridge)
   │  3. 以 /bin/zsh -l -c 完整登录环境执行命令（支持内部多线程 + 多槽位并行）
   │  4. 使用内置 GITHUB_TOKEN + GITHUB_API_URL 将 exit_code 与输出回帖到该 Issue 并自动关闭
   ▼
Gemini App (GitHub MCP)
   └─ 5. issue_read(get_comments) 读取回传结果
```

## 快速部署（4 步打通）

### 第 1 步：给 Gemini 接入 GitHub MCP

完整步骤见 [`docs/gemini-oauth-mcp-guide.md`](docs/gemini-oauth-mcp-guide.md)（含 Redirect URI、OAuth App 创建、`Always allow` 开关与 `workflow` scope 边界说明）。

### 第 2 步：在你的私有控制仓部署工作流

1. 创建一个**私有仓库**（强烈建议私有，切勿在公开仓库部署无沙箱远程执行工作流），并按 GitHub 官方指引在 Mac 上注册首个 Self-Hosted Runner（带标签 `mac-bridge`，或按需改成你自己的标签）。
2. 在 Mac 本地将本仓库的 [`.github/workflows/gemini-mac.yml`](.github/workflows/gemini-mac.yml) 复制到你的私有仓库并推送到 `main` 分支（首次推送必须由本地完成，原因见下文踩坑记录）。
3. 测试触发：让 Gemini 在你的私有仓库创建一条标题为 `[gemini-run] smoke test` 的 Issue，正文示例：

```json
{
  "workdir": "~",
  "timeout_minutes": 5,
  "command": "echo USER=$(whoami) HOST=$(hostname) CPUS=$(sysctl -n hw.ncpu); sw_vers; python3 --version"
}
```

几秒后 Runner 会将结果回帖到该 Issue 并自动将其关闭。

### 第 3 步：扩容多槽位并发 Runner（真多任务并行）

单个 GitHub Actions Runner 进程同一时间只执行 1 个 job。本工作流已将 `concurrency` 设为按 Issue 隔离（`gemini-mac-${{ github.event.issue.number }}`），配合多槽位即可真正并行：

```bash
chmod +x scripts/add-runner-slots.sh
./scripts/add-runner-slots.sh <owner>/<private-repo> mac-bridge 2 3 "$HOME/Library/Application Support/mac-runner"
```

### 第 4 步：防休眠常驻与权限自检

```bash
# 1. 安装开机/登录常驻的 caffeinate -ims（开盖插电永不休眠，允许屏幕熄屏省电）
chmod +x scripts/install-keepawake.sh && ./scripts/install-keepawake.sh

# 2. 探测 Runner 槽位、防休眠锁与 macOS TCC 权限
chmod +x scripts/probe-permissions.sh && ./scripts/probe-permissions.sh
```

- **合盖不休眠（可选）**：`caffeinate -ims` 管开盖状态；如需合盖继续跑，本地执行 `sudo pmset -a disablesleep 1`（用完恢复：`sudo pmset -a disablesleep 0`）。
- **隐私目录 / 截屏 / 键鼠控制**：需在 macOS「系统设置 → 隐私与安全性」中对 Runner 进程授予对应权限（完全磁盘访问、辅助功能、自动化、屏幕录制）。

## 实测踩坑与局限（Lessons Learned）

| 问题 | 根因 | 解法 |
| :--- | :--- | :--- |
| Gemini 直接写 `.github/workflows/*.yml` 报 `403 Forbidden` | GitHub MCP OAuth 授权不含 `workflow` scope，且网页端无法手动补开 | 工作流文件由 Mac 本地 `git push` 推一次，之后日常执行全走 Issue 通道 |
| `curl: (3) bad range in URL position 2` | 从网页聊天复制脚本时，明文 URL 被自动转成 `[https://...](https://...)` | 工作流脚本全面改用 Actions 内置环境变量 `GITHUB_API_URL`，零明文网址 |
| Python f-string 报语法错误 | `bash --noprofile --norc` 可能命中系统自带 Python 3.9（不支持 f-string 花括号内 `
`） | 保持 Python 3.9+ 语法兼容，且用系统 `curl` 调 GitHub API 规避 Python SSL 证书差异 |
| 宽泛 `find ~` 长时间卡住 | 递归扫入 `~/Library` / iCloud 或触发未授权目录弹窗 | 定向扫描具体工作目录，避免不加 `-prune` 的全盘 `find ~` |
| `./svc.sh status` 报 `Must run from runner root` | `svc.sh` 依赖当前工作目录定位 `.service` | 必须 `cd <runner-dir> && ./svc.sh status` |
| Issue 评论长度限制 | GitHub 单条评论上限 65,536 字符 | 工作流自动保留头尾并截断超长中间段（56,000 字符上限）；大文件建议写到本地或同步云盘 |

## 安全边界提示

- **仅用于私有仓库**：工作流虽校验 `github.actor == github.repository_owner`，但请务必放在仅自己有写权限的私有仓。
- **Token 隔离**：工作流在启动用户子进程前会 `env.pop("GH_TOKEN", None)`，避免子命令意外泄露临时令牌。
- **不要开无密码 `sudo`**：日常开发、Python/LaTeX/Docker 与桌面自动化均无需 root。

## 相关项目

- [`ychenfen/claude-codex-github-loop`](https://github.com/ychenfen/claude-codex-github-loop)：Cloud Brain（Claude Web）+ Local Hands（Codex CLI / Claude Code）异步工程闭环模板
- [`ychenfen/claude-agent-skills-collection`](https://github.com/ychenfen/claude-agent-skills-collection)：Agent Skills 与自动化工具集
