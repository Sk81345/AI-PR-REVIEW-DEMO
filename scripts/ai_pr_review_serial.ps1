#!/usr/bin/env pwsh
# =====================================================
# 🤖 AI Pull Request Review + Conditional Auto-Merge
# =====================================================

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

# --- 2️⃣ Get Changed Files ---
Write-Host "🔍 Fetching changed files for PR #$PR_NUMBER..."
$filesUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/files"
$files    = Invoke-RestMethod -Uri $filesUri -Headers $headersGH
$pythonFiles = $files | Where-Object { $_.filename -like "*.py" }

if (-not $pythonFiles) {
    Write-Host "⚠️ No Python files changed. Exiting."
    exit 0
}

# --- 3️⃣ Initialize Review Tracking ---
$issuesFound = $false

foreach ($file in $pythonFiles) {
    $fileName = $file.filename
    $rawUrl   = $file.raw_url
    Write-Host "📄 Reviewing file: $fileName"

    $content  = Invoke-RestMethod -Uri $rawUrl -Headers $headersGH
    $lines    = $content -split "`n"

    # --- RAG Filters ---
    $isTooLong  = $lines.Count -gt 40
    $hasSecrets = $content -match "(?i)(password|token|secret|apikey|authorization\s*[:=])"
    if ($isTooLong -or $hasSecrets) {
        Write-Host "⛔ Skipped: $fileName (too long or contains secrets)"
        continue
    }

    # --- Run Pylint ---
    $tmpFile = "tmp_$($fileName -replace '[\\/]', '_')"
    Set-Content $tmpFile $content
    try {
        $lint = python3 -m pylint $tmpFile --score=no 2>&1
    } catch { $lint = "Lint failed" }
    Remove-Item $tmpFile -Force

    # --- AI Review ---
    $userPrompt = "Review this Python code:\n$content\n\nLinter output:\n$lint"
    $body = @{
        messages = @(
            @{
                role    = "system"
                content = "You are a senior Python reviewer. If code is perfect, say 'No issues found. LGTM.' Otherwise, explain and show fixes inside ```python ...``` blocks."
            },
            @{ role = "user"; content = $userPrompt }
        )
    } | ConvertTo-Json -Depth 4

    try {
        $aiUri   = "$openaiEndpoint/openai/deployments/$deployment/chat/completions?api-version=2024-02-01"
        $resp    = Invoke-RestMethod -Uri $aiUri -Headers $headersAI -Method Post -Body $body
        $review  = $resp.choices[0].message.content
        Write-Host "✅ AI Review done for $fileName"
    } catch {
        Write-Host "⚠️ AI review failed for $fileName: $($_.Exception.Message)"
        continue
    }

    # --- Comment on PR ---
    $commentUri = "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments"
    $commentBody = @{ body = "🤖 **AI Review for `$fileName`**:`n$review" } | ConvertTo-Json
    Invoke-RestMethod -Uri $commentUri -Headers $headersGH -Method Post -Body $commentBody
    Write-Host "💬 Comment posted for $fileName"

    # --- Track issues ---
    if ($review -notmatch "(?i)No issues found\.?\s*LGTM\.?") {
        $issuesFound = $true
    }
}

# --- 4️⃣ Decision: Merge or Wait ---
if ($issuesFound) {
    Write-Host "🚫 Issues detected — skipping auto-merge."
    $summary = @{
        body = "🛑 **AI Review Summary:** Some files need correction. Please review comments and push fixes. The workflow will re-run automatically after new commits."
    } | ConvertTo-Json
    Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments" -Headers $headersGH -Method Post -Body $summary
}
else {
    Write-Host "🎉 All files clean (LGTM). Proceeding with auto-approval and merge."

    # --- Approve PR ---
    $reviewUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/reviews"
    $approveBody = @{
        event = "APPROVE"
        body  = "🤖 AI Review: All checks passed. Automatically approving and merging."
    } | ConvertTo-Json
    Invoke-RestMethod -Uri $reviewUri -Headers $headersGH -Method Post -Body $approveBody
    Write-Host "✅ PR approved by AI."

    # --- Merge PR (Squash) ---
    $mergeUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/merge"
    $mergeBody = @{ merge_method = "squash" } | ConvertTo-Json
    try {
        $mergeResponse = Invoke-RestMethod -Uri $mergeUri -Headers $headersGH -Method Put -Body $mergeBody
        if ($mergeResponse.merged) {
            Write-Host "🚀 PR successfully merged by AI."
        } else {
            Write-Host "⚠️ Merge API returned but merge failed: $($mergeResponse.message)"
        }
    } catch {
        Write-Host "❌ Merge failed: $($_.Exception.Message)"
    }
}

Write-Host "🎯 AI review and merge process complete."
