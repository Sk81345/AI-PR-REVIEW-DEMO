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
    Write-Host "⚠️ No Python files changed. Marking PR as clean and merging."
    $mergeUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/merge"
    $mergeBody = @{ merge_method = "squash" } | ConvertTo-Json
    try {
        $mergeResponse = Invoke-RestMethod -Uri $mergeUri -Headers $headersGH -Method Put -Body $mergeBody
        if ($mergeResponse.merged) {
            Write-Host "🚀 PR successfully merged by AI (no Python files)."
        } else {
            Write-Host "⚠️ Merge API returned but merge failed: $($mergeResponse.message)"
        }
    } catch {
        Write-Host "❌ Merge failed: $($_.Exception.Message)"
    }
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
    } catch { 
        $lint = "Lint failed" 
    }
    Remove-Item $tmpFile -Force

    # --- AI Review ---
    $userPrompt = "Review this Python code:\n$content\n\nLinter output:\n$lint"
    $body = @{
        messages = @(
            @{
                role    = "system"
                content = @"
You are a senior Python reviewer.
If the code is perfect and has no issues, your response MUST include the exact phrase:
'No issues found. LGTM.'
If there are only minor or style issues (like whitespace or PEP8 lint), say:
'Minor issues only. LGTM.'
Otherwise, provide detailed review comments and corrected code snippets inside ```python``` blocks.
"@
            },
            @{ role = "user"; content = $userPrompt }
        )
    } | ConvertTo-Json -Depth 4

    # --- Added: Retry logic for 429 Too Many Requests ---
    $aiUri = "$openaiEndpoint/openai/deployments/$deployment/chat/completions?api-version=2024-02-15-preview"
    $maxRetries = 3
    $retryDelay = 10
    $resp = $null

    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            $resp = Invoke-RestMethod -Uri $aiUri -Headers $headersAI -Method Post -Body $body
            break
        } catch {
            $status = $_.Exception.Response.StatusCode.value__
            if ($status -eq 429 -and $i -lt $maxRetries) {
                $delay = [math]::Pow($retryDelay, $i)
                Write-Host "⚠️ Rate limited (429). Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
            } elseif ($status -eq 400) {
                Write-Host "❌ 400 Bad Request — check deployment name, endpoint, or body format."
                throw
            } else {
                throw
            }
        }
    }

    if (-not $resp) {
        Write-Host "⚠️ Failed to get AI review response after retries for $fileName."
        continue
    }

    $review  = $resp.choices[0].message.content
    Write-Host "✅ AI Review done for $fileName"

    # --- Comment on PR ---
    $commentUri = "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments"
    $commentBody = @{ body = "🤖 **AI Review for `$fileName`**:`n$review" } | ConvertTo-Json
    Invoke-RestMethod -Uri $commentUri -Headers $headersGH -Method Post -Body $commentBody
    Write-Host "💬 Comment posted for $fileName"

    # --- Relaxed merge logic (includes minor/style issues) ---
    if ($review -match "(?i)(No issues found|LGTM|looks good|clean|no problems detected|minor|style)") {
        Write-Host "✅ File marked clean or minor by AI ($fileName)"
    } else {
        $issuesFound = $true
        Write-Host "⚠️ AI detected issues in $fileName"
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
        $mergeError = @{
            body = "❌ **AI Auto-Merge Failed:** $($_.Exception.Message)"
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments" -Headers $headersGH -Method Post -Body $mergeError
    }
}

Write-Host "🎯 AI review and merge process complete."
