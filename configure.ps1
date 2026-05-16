# configure.ps1 - 配置本地基础镜像（插件、状态栏、全局 CLAUDE.md）
#
# 做什么：启动临时容器 → [用户手动配置] → 扫描敏感内容 → 复制全局 CLAUDE.md → commit → 清理
# 前提：D:\Files\.env 存在（提供 API key，仅运行时使用，不进镜像）
#
# 用法：
#   .\configure.ps1          # 交互模式，按提示操作
#   .\configure.ps1 -SkipManual   # 跳过手动配置，直接扫描+commit（用于更新 CLAUDE.md 等）

param([switch]$SkipManual)

$Image = "s7620605/claude-code-opencode:latest"
$Temp = "temp-config"
$EnvFile = "D:\Files\.env"
$GlobalClaudeMd = "C:\Users\sry27\.claude\CLAUDE.md"

# 清理上次残留
docker rm -f $Temp 2>$null | Out-Null

# ── Step 1: 启动临时容器（挂载 .env 提供 API 访问，env 不进镜像） ──
Write-Host "[1/5] 启动临时容器..." -ForegroundColor Yellow
if (-not (Test-Path $EnvFile)) {
    Write-Host "  错误：找不到 $EnvFile" -ForegroundColor Red
    exit 1
}
docker run -d --name $Temp --env-file $EnvFile $Image | Out-Null

# ── Step 2: 用户手动配置 ──
if (-not $SkipManual) {
    Write-Host ""
    Write-Host "[2/5] 手动配置阶段" -ForegroundColor Yellow
    Write-Host "  请在新终端中执行以下命令进入容器：" -ForegroundColor Cyan
    Write-Host "    docker exec -it -u app $Temp bash" -ForegroundColor White
    Write-Host ""
    Write-Host "  在容器内完成以下操作：" -ForegroundColor Cyan
    Write-Host "    1. 运行 claude 进入交互模式"
    Write-Host "    2. 安装 Status Line 脚本"
    Write-Host "    3. 从插件市场安装 Superpowers"
    Write-Host "    4. 从插件市场安装 ECC（含 MCP 配置）"
    Write-Host "    5. 确认 OpenCode 已继承配置"
    Write-Host ""
    Write-Host "  完成后输入 exit 退出容器，然后回到这里" -ForegroundColor Cyan
    Read-Host "  按 Enter 继续"
} else {
    Write-Host "[2/5] 跳过手动配置（-SkipManual）" -ForegroundColor Yellow
}

# ── Step 3: 复制全局 CLAUDE.md ──
Write-Host "[3/5] 复制全局 CLAUDE.md..." -ForegroundColor Yellow
if (Test-Path $GlobalClaudeMd) {
    docker cp $GlobalClaudeMd "${Temp}:/home/app/.claude/CLAUDE.md"
    docker exec $Temp chown app:app /home/app/.claude/CLAUDE.md
    Write-Host "  已复制 $GlobalClaudeMd" -ForegroundColor Green
} else {
    Write-Host "  警告：找不到 $GlobalClaudeMd，跳过" -ForegroundColor Red
}

# ── Step 4: 扫描敏感内容 ──
Write-Host "[4/5] 扫描敏感内容..." -ForegroundColor Yellow

# 从 .env 中提取实际 key 值的前 8 位用于精确匹配
$envKeys = @()
if (Test-Path $EnvFile) {
    $envKeys = Get-Content $EnvFile |
        Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } |
        ForEach-Object {
            $val = ($_.Split('=', 2))[1].Trim().Trim('"').Trim("'")
            if ($val.Length -ge 8) { $val.Substring(0, 8) } else { $val }
        } |
        Where-Object { $_.Length -gt 0 }
}

$scanScript = @'
shopt -s nullglob
FOUND=0
TARGET_DIR="/home/app/.claude /home/app/.config"

PATTERNS="api_key\|apikey\|api\.key\|secret_key\|access_token\|auth_token\|password\|credential\|private_key"

for dir in $TARGET_DIR; do
    if [ -d "$dir" ]; then
        while IFS= read -r file; do
            if file "$file" | grep -q text; then
                MATCHES=$(grep -il "$PATTERNS" "$file" 2>/dev/null)
                if [ -n "$MATCHES" ]; then
                    echo "$MATCHES"
                    FOUND=1
                fi
            fi
        done < <(find "$dir" -type f 2>/dev/null)
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "CLEAN"
fi
'@

$scanResult = docker exec $Temp bash -c $scanScript

if ($scanResult -eq "CLEAN") {
    Write-Host "  未发现敏感内容" -ForegroundColor Green
} else {
    Write-Host "  发现可能包含敏感内容的文件：" -ForegroundColor Red
    $scanResult | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  请检查上述文件，确认不含 API key / token / secret" -ForegroundColor Red
    $confirm = Read-Host "  确认安全，继续 commit？(y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "  已取消。容器 $Temp 保留，可手动检查。" -ForegroundColor Yellow
        exit 1
    }
}

# 额外检查：.env 中的实际 key 值是否出现在文件系统中
if ($envKeys.Count -gt 0) {
    $keyPatterns = ($envKeys | ForEach-Object { [regex]::Escape($_) }) -join '\|'
    $keyScan = docker exec $Temp bash -c "grep -rl '$keyPatterns' /home/app/.claude /home/app/.config 2>/dev/null || echo CLEAN"

    if ($keyScan -ne "CLEAN") {
        Write-Host "  警告：发现 .env 中的实际 key 值出现在以下文件：" -ForegroundColor Red
        $keyScan | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        Write-Host "  这些文件不应被 commit！" -ForegroundColor Red
        $confirm = Read-Host "  确认安全，继续 commit？(y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "  已取消。" -ForegroundColor Yellow
            docker rm -f $Temp | Out-Null
            exit 1
        }
    }
}

# ── Step 5: 提交为新的基础镜像 ──
Write-Host "[5/5] 提交为新镜像..." -ForegroundColor Yellow
docker commit $Temp $Image
docker rm -f $Temp | Out-Null

Write-Host ""
Write-Host "Done. 各项目执行以下命令应用更新：" -ForegroundColor Green
Write-Host "  cd <项目>/docker && docker compose up -d --force-recreate"
