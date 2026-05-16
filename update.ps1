# update.ps1 - 更新基础镜像中的 AI 工具
#
# 更新什么：Claude Code、OpenCode、Codex
# 更新方式：启动临时容器 → npm update → 提交为新镜像 → 清理临时容器
# 耗时：约 2-5 分钟
#
# 用法：直接运行
#   .\update.ps1

$Image = "s7620605/claude-code-opencode:latest"
$Temp = "temp-update"

# 清理上次可能残留的临时容器
docker rm -f $Temp 2>$null | Out-Null

Write-Host "[1/4] 启动临时容器..." -ForegroundColor Yellow
docker run -d --name $Temp $Image | Out-Null

Write-Host "[2/4] 更新工具..." -ForegroundColor Yellow
docker exec $Temp npm update -g @anthropic-ai/claude-code opencode-ai @openai/codex

Write-Host "[3/4] 提交为新镜像..." -ForegroundColor Yellow
docker commit $Temp $Image

Write-Host "[4/4] 清理临时容器..." -ForegroundColor Yellow
docker rm -f $Temp | Out-Null

Write-Host ""
Write-Host "Done. 各项目执行以下命令应用更新：" -ForegroundColor Green
Write-Host "  cd <项目>/docker && docker compose up -d --force-recreate"
