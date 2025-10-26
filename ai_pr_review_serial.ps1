#!/usr/bin/env pwsh
# ============================================
# 🤖 AI PR Review with RAG + DB Logging (GitHub)
# ============================================

param(
    [string]$PR_NUMBER,
    [string]$REPO
)

# 1️⃣ Setup environment
$openaiEndpoint = $env:OPENAI_ENDPOINT
$openaiKey = $env:OPENAI_API_KEY
$deployment = $env:OPENAI_DEPLOYMENT_NAME
$ghToken = $env:GITHUB_TOKEN

$headersAI = @{
    "api-key" = $openaiKey
    "Content-Type" = "application/json"
}
$headersGH = @{
    "Authorization" = "Bearer $ghToken"
    "Accept" = "application/vnd.github+json"
}

# 2️⃣ Get changed files
Write-Host "🔍 Fetching changed files for PR #$PR_NUMBER..."
$filesUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/files"
$files = Invoke-RestMethod -Uri $filesUri -Headers $headersGH
$pythonFiles = $files | Where-Object { $_.filename -like "*.py" }

if (-not $pythonFiles) {
    Write-Host "⚠️ No Python files changed. Exiting."
    exit 0
}

# 3️⃣ Initialize SQLite DB
. ./scripts/init_db.ps1
Add-Type -AssemblyName System.Data.SQLite
$connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=ai_reviews.db;Version=3;")
$connection.Open()

foreach ($file in $pythonFiles) {
    $fileName = $file.filename
    $rawUrl = $file.raw_url
    Write-Host "📄 Checking file: $fileName"

    $content = Invoke-RestMethod -Uri $rawUrl -Headers $headersGH
    $lines = $content -split "`n"

    # === 🧠 RAG FILTER ===
    $isTooLong = $lines.Count -gt 40
    $hasSecrets = $content -match "(?i)(password|token|secret|apikey|authorization\s*[:=])"

    if ($isTooLong -or $hasSecrets) {
        Write-Host "⛔ Skipped by RAG Filter: $fileName (Too long or contains secrets)"
        continue
    }

    # Run linting
    $tmpFile = "tmp_$($fileName -replace '[\\/]', '_')"
    Set-Content $tmpFile $content
    try {
        $lint = python3 -m pylint $tmpFile --score=no 2>&1
    } catch { $lint = "Lint failed" }
    Remove-Item $tmpFile -Force

    # === AI REVIEW ===
    $body = @{
        messages = @(
            @{ role = "system"; content = "You are a senior Python reviewer. Find bugs, logic, and security issues." },
            @{ role = "user"; content = "Review this code:`n$content`nLinter output:`n$lint" }
        )
    } | ConvertTo-Json -Depth 4

    try {
        $aiUri = "$openaiEndpoint/openai/deployments/$deployment/chat/completions?api-version=2024-02-01"
        $response = Invoke-RestMethod -Uri $aiUri -Headers $headersAI -Method Post -Body $body
        $review = $response.choices[0].message.content
        Write-Host "✅ AI Review completed for $fileName"
    } catch {
        Write-Host "⚠️ AI review failed for $fileName"
        continue
    }

    # 🗃️ Save to DB
    $cmd = $connection.CreateCommand()
    $cmd.CommandText = "INSERT INTO reviews (pr_number, file_name, review_summary) VALUES (@pr, @file, @review)"
    $cmd.Parameters.AddWithValue("@pr", $PR_NUMBER) | Out-Null
    $cmd.Parameters.AddWithValue("@file", $fileName) | Out-Null
    $cmd.Parameters.AddWithValue("@review", $review) | Out-Null
    $cmd.ExecuteNonQuery()

    # 💬 Comment back to PR
    $commentUri = "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments"
    $bodyComment = @{ body = "🤖 **AI Review for `$fileName`:**`n$review" } | ConvertTo-Json
    Invoke-RestMethod -Uri $commentUri -Headers $headersGH -Method Post -Body $bodyComment
    Write-Host "💬 Comment posted for $fileName"
}

$connection.Close()
Write-Host "🎯 All reviews completed and logged to DB."
