# configure.ps1 - Configure local base image (plugins, statusline, global CLAUDE.md)
#
# What: start temp container -> [user manual config] -> scan secrets -> copy CLAUDE.md -> commit -> cleanup
# Prereq: D:\Files\.env exists (provides API keys at runtime, never baked into image)
#
# Usage:
#   .\configure.ps1          # interactive mode
#   .\configure.ps1 -SkipManual   # skip manual config, just scan + commit (e.g. update CLAUDE.md only)

param([switch]$SkipManual)

$Image = "s7620605/claude-code-opencode:latest"
$Temp = "temp-config"
$EnvFile = "D:\Files\.env"
$GlobalClaudeMd = "C:\Users\sry27\.claude\CLAUDE.md"

# Cleanup leftover container from previous run
docker rm -f $Temp 2>$null | Out-Null

# -- Step 1: Start temp container with .env for API access (env vars don't enter image) --
Write-Host "[1/5] Starting temp container..." -ForegroundColor Yellow
if (-not (Test-Path $EnvFile)) {
    Write-Host "  ERROR: $EnvFile not found" -ForegroundColor Red
    exit 1
}
docker run -d --name $Temp --env-file $EnvFile `
    --add-host=host.docker.internal:host-gateway `
    -e HTTP_PROXY=http://host.docker.internal:7890 `
    -e HTTPS_PROXY=http://host.docker.internal:7890 `
    -e NO_PROXY=localhost,127.0.0.1,open.bigmodel.cn,.bigmodel.cn `
    $Image | Out-Null

# -- Step 2: User manual configuration --
if (-not $SkipManual) {
    Write-Host ""
    Write-Host "[2/5] Manual configuration" -ForegroundColor Yellow
    Write-Host "  Open a new terminal and run:" -ForegroundColor Cyan
    Write-Host "    docker exec -it -u app $Temp bash" -ForegroundColor White
    Write-Host ""
    Write-Host "  Inside the container:" -ForegroundColor Cyan
    Write-Host "    1. Run 'claude' to enter interactive mode"
    Write-Host "    2. Install Status Line script"
    Write-Host "    3. Install Superpowers from marketplace"
    Write-Host "    4. Install ECC from marketplace (includes MCP config)"
    Write-Host "    5. Verify OpenCode inherits Claude Code config"
    Write-Host ""
    Write-Host "  Type 'exit' when done, then come back here" -ForegroundColor Cyan
    Read-Host "  Press Enter to continue"
} else {
    Write-Host "[2/5] Skipping manual config (-SkipManual)" -ForegroundColor Yellow
}

# -- Step 3: Apply base configuration (settings.json env block + global CLAUDE.md) --
Write-Host "[3/5] Applying base configuration..." -ForegroundColor Yellow

# 3a: Ensure settings.json has Zhipu env block
# Claude Code overwrites settings.json during manual config, dropping the env block.
# Must re-merge it before commit.
$envScript = @'
import json
p = "/home/app/.claude/settings.json"
try:
    s = json.load(open(p))
except:
    s = {}
s["env"] = {
    "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-5-turbo",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "glm-5-turbo",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "glm-5.1",
    "ANTHROPIC_MODEL": "glm-5-turbo",
    "ANTHROPIC_REASONING_MODEL": "glm-5.1",
    "ENABLE_TOOL_SEARCH": "true",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "API_TIMEOUT_MS": "3000000"
}
json.dump(s, open(p, "w"), indent=2)
print("OK")
'@
$tmpPy = "$env:TEMP\ensure_env.py"
$envScript | Set-Content $tmpPy -Encoding UTF8
docker cp $tmpPy "${Temp}:/tmp/ensure_env.py"
docker exec $Temp python3 /tmp/ensure_env.py
Remove-Item $tmpPy
Write-Host "  settings.json env block ensured" -ForegroundColor Green

# 3b: Copy global CLAUDE.md
if (Test-Path $GlobalClaudeMd) {
    docker cp $GlobalClaudeMd "${Temp}:/home/app/.claude/CLAUDE.md"
    docker exec $Temp chown app:app /home/app/.claude/CLAUDE.md
    Write-Host "  Copied $GlobalClaudeMd" -ForegroundColor Green
} else {
    Write-Host "  WARNING: $GlobalClaudeMd not found, skipping" -ForegroundColor Red
}

# -- Step 4: Scan for sensitive content --
Write-Host "[4/5] Scanning for sensitive content..." -ForegroundColor Yellow

# Extract first 8 chars of each value from .env for exact matching
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

# Show extracted key previews for verification
if ($envKeys.Count -gt 0) {
    $previews = $envKeys | ForEach-Object { "$($_.Substring(0, [Math]::Min($_.Length, 4)))..." }
    Write-Host "  Checking $($envKeys.Count) .env values: $($previews -join ', ')" -ForegroundColor Cyan
} else {
    Write-Host "  WARNING: no key values extracted from $EnvFile" -ForegroundColor Red
}

# Pattern-based scan for sensitive keywords
# Write scan script to file to avoid PowerShell argument passing issues with bash -c
$scanScript = @'
#!/bin/bash
EXCLUDE="--exclude-dir=backups --exclude-dir=cache --exclude-dir=paste-cache --exclude-dir=projects --exclude-dir=todos --exclude-dir=plugins --exclude-dir=rules --exclude-dir=skills --exclude-dir=sessions --exclude-dir=learned"
FOUND=0
for dir in /home/app/.claude /home/app/.config; do
    if [ -d "$dir" ]; then
        MATCHES=$(grep -rIil $EXCLUDE "api_key\|apikey\|secret_key\|access_token\|auth_token\|password\|credential\|private_key" "$dir" 2>/dev/null)
        if [ -n "$MATCHES" ]; then
            echo "$MATCHES"
            FOUND=1
        fi
    fi
done
if [ "$FOUND" -eq 0 ]; then
    echo "CLEAN"
fi
'@
$tmpScan = "$env:TEMP\scan_secrets.sh"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tmpScan, $scanScript, $utf8NoBom)
docker cp $tmpScan "${Temp}:/tmp/scan_secrets.sh"
Remove-Item $tmpScan

$rawOutput = (docker exec $Temp bash /tmp/scan_secrets.sh 2>&1) -join "`n"
$rawOutput = $rawOutput.Trim() -replace '\x1b\[[0-9;]*m', ''

if ($rawOutput -eq "CLEAN") {
    Write-Host "  No sensitive content found" -ForegroundColor Green
} else {
    $scanLines = $rawOutput -split "[`n`r]+" | Where-Object { $_.Trim().Length -gt 0 }
    Write-Host "  Potential sensitive content found in:" -ForegroundColor Red
    $scanLines | ForEach-Object { Write-Host "    $($_.Trim())" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Please verify these files don't contain API key/token/secret" -ForegroundColor Red
    $confirm = Read-Host "  Safe to continue commit? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "  Cancelled. Container $Temp preserved for inspection." -ForegroundColor Yellow
        exit 1
    }
}

# Exact match: check if actual .env key values appear in filesystem
if ($envKeys.Count -gt 0) {
    $keyPatterns = ($envKeys | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $keyScanScript = @'
#!/bin/bash
EXCLUDE="--exclude-dir=backups --exclude-dir=cache --exclude-dir=paste-cache --exclude-dir=projects --exclude-dir=todos --exclude-dir=plugins --exclude-dir=rules --exclude-dir=skills --exclude-dir=sessions --exclude-dir=learned"
RESULT=$(grep -rl $EXCLUDE '__KEYPATTERNS__' /home/app/.claude /home/app/.config 2>/dev/null)
if [ -n "$RESULT" ]; then
    echo "$RESULT"
else
    echo "CLEAN"
fi
'@
    $keyScanScript = $keyScanScript -replace '__KEYPATTERNS__', $keyPatterns
    $tmpKeyScan = "$env:TEMP\scan_keys.sh"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tmpKeyScan, $keyScanScript, $utf8NoBom)
    docker cp $tmpKeyScan "${Temp}:/tmp/scan_keys.sh"
    Remove-Item $tmpKeyScan

    $rawKeyOutput = (docker exec $Temp bash /tmp/scan_keys.sh 2>&1) -join "`n"
    $rawKeyOutput = $rawKeyOutput.Trim() -replace '\x1b\[[0-9;]*m', ''

    if ($rawKeyOutput -ne "CLEAN") {
        $keyLines = $rawKeyOutput -split "[`n`r]+" | Where-Object { $_.Trim().Length -gt 0 }
        Write-Host "  WARNING: actual .env key values found in:" -ForegroundColor Red
        $keyLines | ForEach-Object { Write-Host "    $($_.Trim())" -ForegroundColor Red }
        Write-Host "  These files should NOT be committed!" -ForegroundColor Red
        $confirm = Read-Host "  Safe to continue commit? (y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "  Cancelled." -ForegroundColor Yellow
            docker rm -f $Temp | Out-Null
            exit 1
        }
    } else {
        Write-Host "  No .env key values found in image" -ForegroundColor Green
    }
}

# -- Step 5: Commit as new base image --
Write-Host "[5/5] Committing new image..." -ForegroundColor Yellow
docker commit $Temp $Image
docker rm -f $Temp | Out-Null

Write-Host ""
Write-Host "Done. Apply to each project:" -ForegroundColor Green
Write-Host "  cd PROJECT/docker; docker compose up -d --force-recreate"
