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

# --- 2️⃣ Fetch PR changed files ---
Write-Host "[INFO] Fetching changed files for PR #$PR_NUMBER..."
$filesUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/files?per_page=100"
$files = Invoke-RestMethod -Uri $filesUri -Headers $headersGH
if (-not $files) {
    Write-Host "[ERROR] No files found in PR."
    exit 1
}

$reviewFiles = $files | Where-Object { $_.status -ne "removed" -and $_.filename -like "*.py" }

if (-not $reviewFiles) {
    Write-Host "[INFO] No Python files found. Skipping AI review, merging directly."
    $mergeUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/merge"
    $mergeBody = @{ merge_method = "squash" } | ConvertTo-Json
    Invoke-RestMethod -Uri $mergeUri -Headers $headersGH -Method Put -Body $mergeBody
    exit 0
}

# --- 3️⃣ Review loop ---
$issuesFound = $false
$reviewSummary = @()
$totalFiles = $reviewFiles.Count
$index = 1

foreach ($file in $reviewFiles) {
    $fileName = $file.filename
    $rawUrl   = $file.raw_url

    Write-Host ""
    Write-Host "[INFO] [$index/$totalFiles] Starting AI review for file: $fileName"

    try {
        $content = Invoke-RestMethod -Uri $rawUrl -Headers @{ "User-Agent"="ai-review" }
    } catch {
        Write-Host "[WARN] Could not fetch file: $fileName"
        continue
    }

    # --- RAG Filters ---

        $lines = $content -split "`n"
        if ($lines.Count -gt 40) {
            Write-Host "🚫 $fileName skipped (more than 40 lines per RAG rule). Marking as issue."
            $issuesFound = $true
            $reviewSummary += "⚠️ $fileName — Skipped due to exceeding 40-line RAG rule (manual review needed)."
            $index++
            continue
        }
        if ($content -match "(?i)(password|token|secret|apikey|authorization\s*[:=])") {
            Write-Host "🚫 $fileName skipped (possible secret detected). Marking as issue."
            $issuesFound = $true
            $reviewSummary += "⚠️ $fileName — Skipped due to potential secret detected (manual review required)."
            $index++
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
        max_tokens = 300
    } | ConvertTo-Json -Depth 5

    $aiUri = "$openaiEndpoint/openai/deployments/$deployment/chat/completions?api-version=2024-02-15-preview"

    $maxRetries = 5
    $retryDelay = 10
    $resp = $null

    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            $resp = Invoke-RestMethod -Uri $aiUri -Headers $headersAI -Method Post -Body $body
            break
        } catch {
            $status = $_.Exception.Response.StatusCode.value__
            if ($status -eq 429 -and $i -lt $maxRetries) {
                $delay = $retryDelay * $i
                Write-Host "[WARN] Rate limited (429). Waiting $delay seconds before retry $i..."
                Start-Sleep -Seconds $delay
            } else {
                Write-Host ("[ERROR] AI request failed for {0}: {1}" -f $fileName, $_.Exception.Message)
                break
            }
        }
    }

    if (-not $resp) {
        $review = "⚠️ AI failed after retries for $fileName."
    } else {
        $review = $resp.choices[0].message.content
        Write-Host "[AI] Review complete for $fileName"
    }

    # --- Post AI comment with file info ---
    $commentUri = "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments"
    $commentBody = @{
        body = "🤖 **AI Review for file `$($fileName)` ($index of $totalFiles)**`n`n$review`n`n---`n📄 *Next file will be reviewed automatically...*"
    } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri $commentUri -Headers $headersGH -Method Post -Body $commentBody
        Write-Host "[INFO] Comment posted for $fileName ($index of $totalFiles)"
    } catch {
        Write-Host "[WARN] Could not post comment for $fileName"
    }

    # --- Track issues for summary ---
    if ($review -match "(?i)(No issues found\. LGTM\.|Minor issues only\. LGTM\.)") {
        Write-Host "[INFO] Clean result detected for $fileName"
        $reviewSummary += "✅ $fileName — Clean or minor issues only."
    } else {
        $issuesFound = $true
        Write-Host "[WARN] Issues detected in $fileName"
        $reviewSummary += "⚠️ $fileName — Issues found, see AI comments."
    }

    Start-Sleep -Seconds 2
    $index++
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
    Write-Host "[INFO] Issues detected, skipping merge."
    exit 0
}

# --- Merge Clean PR ---
Write-Host "[INFO] All files clean — proceeding with auto-merge."
$mergeUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/merge"
$mergeBody = @{ merge_method = "squash" } | ConvertTo-Json
try {
    $mergeResponse = Invoke-RestMethod -Uri $mergeUri -Headers $headersGH -Method Put -Body $mergeBody
    if ($mergeResponse.merged) {
        Write-Host "[SUCCESS] 🚀 PR successfully merged by AI."
    } else {
        Write-Host "[WARN] Merge failed: $($mergeResponse.message)"
    }
} catch {
    Write-Host "[ERROR] Merge failed: $($_.Exception.Message)"
}
