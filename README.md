# claude-code-docker

AI 编程工具的开发容器基础镜像，预装 Claude Code、OpenCode 和 Codex。

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

## 自动更新

镜像通过两种机制保持最新：

1. **容器启动时**：`entrypoint.sh` 自动更新 Claude Code 和 OpenCode，并安装最新版 Codex
2. **每周自动构建**：GitHub Actions 每周一自动重建镜像并推送到 Docker Hub

所以即使忘记拉取新镜像，容器启动时工具也会是最新版。

## 手动构建

如果需要本地修改并推送：

```bash
docker build -t s7620605/claude-code-opencode:latest .
docker push s7620605/claude-code-opencode:latest
```

## 目录结构

```
.
├── Dockerfile                    # 镜像构建文件
├── entrypoint.sh                 # 容器入口脚本（初始化配置 + 自动更新）
├── .github/workflows/build-image.yml  # 每周自动构建
└── README.md
```
