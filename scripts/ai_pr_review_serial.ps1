#!/usr/bin/env pwsh
# =======================================================
# 🤖 AI Pull Request Review + Auto Comment + Auto Merge
# =======================================================

param(
    [string]$PR_NUMBER,
    [string]$REPO
)

# --- 1️⃣ Environment Setup ---
$openaiEndpoint = $env:OPENAI_ENDPOINT
$openaiKey      = $env:OPENAI_API_KEY
$deployment     = $env:OPENAI_DEPLOYMENT_NAME
$ghToken        = $env:GITHUB_TOKEN

$headersAI = @{
    "api-key"      = $openaiKey
    "Content-Type" = "application/json"
}
$headersGH = @{
    "Authorization" = "Bearer $ghToken"
    "Accept"        = "application/vnd.github+json"
}

# --- 2️⃣ Fetch PR changed files (all modified + new) ---
Write-Host "🔍 Fetching changed files for PR #$PR_NUMBER..."
$filesUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/files?per_page=100"
$files = Invoke-RestMethod -Uri $filesUri -Headers $headersGH
if (-not $files) {
    Write-Host "❌ No files found in PR."
    exit 1
}

# include all new + modified files, exclude deleted
$reviewFiles = $files | Where-Object { $_.status -ne "removed" -and $_.filename -like "*.py" }

if (-not $reviewFiles) {
    Write-Host "⚠️ No Python files found. Skipping AI review, merging directly."
    $mergeUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/merge"
    $mergeBody = @{ merge_method = "squash" } | ConvertTo-Json
    Invoke-RestMethod -Uri $mergeUri -Headers $headersGH -Method Put -Body $mergeBody
    exit 0
}

# --- 3️⃣ Review loop ---
$issuesFound = $false
$reviewSummary = @()

foreach ($file in $reviewFiles) {
    $fileName = $file.filename
    $rawUrl   = $file.raw_url

    Write-Host "`n📄 Reviewing file: $fileName"

    try {
        $content = Invoke-RestMethod -Uri $rawUrl -Headers @{ "User-Agent"="ai-review" }
    } catch {
        Write-Host "⚠️ Could not fetch file: $fileName"
        continue
    }

    # --- RAG Filters ---
    $lines = $content -split "`n"
    if ($lines.Count -gt 40) {
        Write-Host "⏭️ Skipping $fileName (more than 40 lines per RAG rule)."
        continue
    }
    if ($content -match "(?i)(password|token|secret|apikey|authorization\s*[:=])") {
        Write-Host "⏭️ Skipping $fileName (possible secret detected)."
        continue
    }

    # --- Lint & Syntax ---
    $tmpFile = "tmp_$($fileName -replace '[\\/]', '_')"
    Set-Content $tmpFile $content
    $lint = ""
    $syntaxOK = $true

    try { python3 -m py_compile $tmpFile } catch { $syntaxOK = $false }
    try { $lint = (python3 -m pylint $tmpFile --score=no 2>&1) } catch { $lint = "pylint failed" }
    Remove-Item $tmpFile -Force

    # --- AI Review ---
    $prompt = @"
Review the following Python file for code quality, logic, and security.
Include concrete improvement suggestions and example fixes.

File: $fileName
Content:
$content

Linter Output:
$lint

If code is perfect, reply exactly: "No issues found. LGTM."
If only minor issues, reply exactly: "Minor issues only. LGTM."
"@

    $body = @{
        messages = @(
            @{ role = "system"; content = "You are a senior Python reviewer. Be concise and accurate." },
            @{ role = "user"; content = $prompt }
        )
    } | ConvertTo-Json -Depth 5

    $aiUri = "$openaiEndpoint/openai/deployments/$deployment/chat/completions?api-version=2024-02-15-preview"

    try {
        $resp = Invoke-RestMethod -Uri $aiUri -Headers $headersAI -Method Post -Body $body
        $review = $resp.choices[0].message.content
        Write-Host "🤖 AI review complete for $fileName"
    } catch {
        $review = "⚠️ AI failed: $($_.Exception.Message)"
    }

    # --- Post AI comment ---
    $commentUri = "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments"
    $commentBody = @{ body = "🤖 **AI Review for `$fileName`**:`n`n$review" } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri $commentUri -Headers $headersGH -Method Post -Body $commentBody
        Write-Host "💬 Comment posted for $fileName"
    } catch {
        Write-Host "⚠️ Could not post comment for $fileName"
    }

    # --- Track issues for summary ---
    if ($review -match "(?i)(No issues found|LGTM|Minor issues only)") {
        $reviewSummary += "✅ $fileName — Clean or minor issues only."
    } else {
        $issuesFound = $true
        $reviewSummary += "⚠️ $fileName — Issues found, see AI comments."
    }
}

# --- 4️⃣ Final Summary Comment ---
$summaryText = if ($issuesFound) {
"🛑 **AI Summary:** Some files have issues.  
Please review the comments and fix the reported problems.  
The AI reviewer will automatically recheck and merge after new commits."
} else {
"✅ **AI Summary:** All reviewed files are clean or have only minor issues.  
Proceeding with automatic merge. 🚀"
}

$summaryBody = @{ body = $summaryText + "`n`n---`n`n" + ($reviewSummary -join "`n") } | ConvertTo-Json
Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments" -Headers $headersGH -Method Post -Body $summaryBody

# --- 5️⃣ Merge Decision ---
if ($issuesFound) {
    Write-Host "🚫 Issues detected, skipping merge."
    exit 0
}

# --- Merge Clean PR ---
Write-Host "🎉 All clean — proceeding with auto-merge."
$mergeUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/merge"
$mergeBody = @{ merge_method = "squash" } | ConvertTo-Json
try {
    $mergeResponse = Invoke-RestMethod -Uri $mergeUri -Headers $headersGH -Method Put -Body $mergeBody
    if ($mergeResponse.merged) {
        Write-Host "🚀 PR successfully merged by AI."
    } else {
        Write-Host "⚠️ Merge failed: $($mergeResponse.message)"
    }
} catch {
    Write-Host "❌ Merge failed: $($_.Exception.Message)"
}
