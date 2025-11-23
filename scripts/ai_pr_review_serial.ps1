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
    # RAG Rule: File must be 40 lines or less, AND must not contain secrets.
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


    # 4️⃣ LONG CHAIN: FETCH CONTEXT FROM DB (NEW LOGIC)
    $priorReviews = ""
    try {
        $cmd = $connection.CreateCommand()
        # Fetch the last 3 prior reviews for this file, ordered by timestamp
        $cmd.CommandText = "SELECT review_summary FROM reviews WHERE pr_number = @pr AND file_name = @file ORDER BY timestamp DESC LIMIT 3"
        $cmd.Parameters.AddWithValue("@pr", $PR_NUMBER) | Out-Null
        $cmd.Parameters.AddWithValue("@file", $fileName) | Out-Null

        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) {
            $priorReviews += "--- Prior Review Context ---\n" + $reader.GetString(0) + "\n"
        }
    } catch {
        Write-Host "⚠️ Could not read prior reviews from DB. Proceeding without history."
    }

    # 5️⃣ AI REVIEW (Structured Suggestion Prompt)
    $userPrompt = "Review the following Python code:\n$content\n\nLinter output:\n$lint"
    if ($priorReviews) {
        # Prepend history to the prompt if available
        $userPrompt = "Historical Review Context:\n$priorReviews\n\n--- New Code to Review ---\n" + $userPrompt
    }

    $body = @{
        messages = @(
            @{
                role = "system";
                # CRITICAL: Force the AI to output suggestions in a structured markdown block
                content = @"
You are a senior Python reviewer and quality engineer. Your output MUST be a detailed, constructive review.
For every suggestion, provide the corrected code within a clean, isolated **Python markdown code block (\`\`\`python ... \`\`\`)** immediately following your explanation.
If you find no issues, state 'No issues found. LGTM.'
"@
            },
            @{ role = "user"; content = $userPrompt }
        )
    } | ConvertTo-Json -Depth 4

    try {
        $aiUri = "$openaiEndpoint/openai/deployments/$deployment/chat/completions?api-version=2024-02-01"
        $response = Invoke-RestMethod -Uri $aiUri -Headers $headersAI -Method Post -Body $body
        $review = $response.choices[0].message.content
        Write-Host "✅ AI Review completed for $fileName"
    } catch {
        Write-Host "⚠️ AI review failed for $fileName. Error: $($_.Exception.Message)"
        continue
    }

    # 6️⃣ Save to DB and Post Comment

    # 🗃️ Save to DB
    $cmd = $connection.CreateCommand()
    # Note: We use the correct column name 'timestamp' here
    $cmd.CommandText = "INSERT INTO reviews (pr_number, file_name, review_summary) VALUES (@pr, @file, @review)"
    $cmd.Parameters.AddWithValue("@pr", $PR_NUMBER) | Out-Null
    $cmd.Parameters.AddWithValue("@file", $fileName) | Out-Null
    $cmd.Parameters.AddWithValue("@review", $review) | Out-Null
    $cmd.ExecuteNonQuery()
    Write-Host "🗃️ Review summary logged to SQLite DB."

    # 💬 Comment back to PR
    $commentUri = "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments"
    $bodyComment = @{
        body = "🤖 **AI Code Suggestion for `$fileName`** (Reviewed with History):`n$review"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri $commentUri -Headers $headersGH -Method Post -Body $bodyComment
    Write-Host "💬 Comment posted for $fileName"
}

$connection.Close()
Write-Host "🎯 All reviews completed and logged to DB."
