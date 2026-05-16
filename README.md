# claude-code-docker

AI 编程工具的开发容器基础镜像，预装 Claude Code、OpenCode 和 Codex，默认使用智谱 API。

## 包含工具

| 工具 | 说明 |
|------|------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Anthropic 官方 CLI 编程助手 |
| [OpenCode](https://github.com/opencode-ai/opencode) | 开源 AI 编程终端 |
| [Codex](https://github.com/openai/codex) | OpenAI 编程 CLI |
| Node.js 20 | JS/TS 运行环境 |
| Python 3 | Python 运行环境 |
| Git + GitHub CLI | 版本控制 |

## 快速使用

```bash
docker pull s7620605/claude-code-opencode:latest
```

在你的 `docker-compose.yml` 中引用：

```yaml
services:
  app:
    image: s7620605/claude-code-opencode:latest
    container_name: dev-container
    user: "0:0"
    volumes:
      - ./your-project:/home/app/project
      - config:/home/app/.claude
    environment:
      - ANTHROPIC_API_KEY=your-key-here
    stdin_open: true
    tty: true

volumes:
  config:
```

启动容器后运行 `claude` 即可开始使用。

## 默认配置

容器首次启动时，`entrypoint.sh` 会自动创建 `settings.json`，默认配置：

- **API 地址**：`open.bigmodel.cn/api/anthropic`（智谱 API）
- **模型映射**：glm-5-turbo（日常）、glm-5.1（推理）
- 已跳过 Claude Code 引导流程

如需自定义配置，挂载你的 `settings.json` 到 `/home/app/.claude/settings.json` 即可覆盖。

## 更新工具

### 本地更新（Windows）

运行项目中的 `update.ps1`，它会启动临时容器、更新工具并提交为新镜像：

```powershell
.\update.ps1
```

更新完成后，各项目执行以下命令应用：

```bash
docker compose up -d --force-recreate
```

### 每周自动构建

GitHub Actions 每周一自动重建镜像并推送到 Docker Hub，也可在 Actions 页面手动触发。

## 手动构建

```bash
docker build -t s7620605/claude-code-opencode:latest .
docker push s7620605/claude-code-opencode:latest
```

## 目录结构

```
.
├── Dockerfile                         # 镜像构建文件
├── entrypoint.sh                      # 容器入口脚本（配置恢复 + 初始化设置）
├── update.ps1                         # 本地更新工具（Windows PowerShell）
├── .github/workflows/build-image.yml  # 每周自动构建
└── README.md
```
