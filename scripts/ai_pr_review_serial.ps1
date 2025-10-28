#!/usr/bin/env pwsh
<<<<<<< HEAD
# =====================================================
# 🤖 AI Pull Request Review + Conditional Auto-Merge
# =====================================================
=======
# ============================================
# 🤖 AI PR Review with RAG + DB Logging (GitHub)
# ============================================
>>>>>>> master

param(
    [string]$PR_NUMBER,
    [string]$REPO
)

<<<<<<< HEAD
# --- 1️⃣ Environment Setup ---
$openaiEndpoint = $env:OPENAI_ENDPOINT
$openaiKey      = $env:OPENAI_API_KEY
$deployment     = $env:OPENAI_DEPLOYMENT_NAME
$ghToken        = $env:GITHUB_TOKEN

$headersAI = @{
    "api-key"      = $openaiKey
=======
# 1️⃣ Setup environment
$openaiEndpoint = $env:OPENAI_ENDPOINT
$openaiKey = $env:OPENAI_API_KEY
$deployment = $env:OPENAI_DEPLOYMENT_NAME
$ghToken = $env:GITHUB_TOKEN

$headersAI = @{
    "api-key" = $openaiKey
>>>>>>> master
    "Content-Type" = "application/json"
}
$headersGH = @{
    "Authorization" = "Bearer $ghToken"
<<<<<<< HEAD
    "Accept"        = "application/vnd.github+json"
}

# --- 2️⃣ Get Changed Files ---
Write-Host "🔍 Fetching changed files for PR #$PR_NUMBER..."
$filesUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/files"
$files    = Invoke-RestMethod -Uri $filesUri -Headers $headersGH
=======
    "Accept" = "application/vnd.github+json"
}

# 2️⃣ Get changed files
Write-Host "🔍 Fetching changed files for PR #$PR_NUMBER..."
$filesUri = "https://api.github.com/repos/$REPO/pulls/$PR_NUMBER/files"
$files = Invoke-RestMethod -Uri $filesUri -Headers $headersGH
>>>>>>> master
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

<<<<<<< HEAD
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
Otherwise, provide detailed review comments and corrected code snippets inside ```python``` blocks.
=======

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
>>>>>>> master
"@
            },
            @{ role = "user"; content = $userPrompt }
        )
    } | ConvertTo-Json -Depth 4

    try {
<<<<<<< HEAD
        $aiUri   = "$openaiEndpoint/openai/deployments/$deployment/chat/completions?api-version=2024-02-01"
        $resp    = Invoke-RestMethod -Uri $aiUri -Headers $headersAI -Method Post -Body $body
        $review  = $resp.choices[0].message.content
        Write-Host "✅ AI Review done for $fileName"
    } catch {
        Write-Host "⚠️ AI review failed for $($fileName): $($_.Exception.Message)"
        # Optional: post a failure comment to PR
        $errorComment = @{
            body = "⚠️ **AI Review Error:** Failed to analyze `$fileName`. Error: $($_.Exception.Message)"
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments" -Headers $headersGH -Method Post -Body $errorComment
        continue
    }

    # --- Comment on PR ---
    $commentUri = "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments"
    $commentBody = @{ body = "🤖 **AI Review for `$fileName`**:`n$review" } | ConvertTo-Json
    Invoke-RestMethod -Uri $commentUri -Headers $headersGH -Method Post -Body $commentBody
    Write-Host "💬 Comment posted for $fileName"

    # --- Track issues (Flexible detection) ---
    if ($review -match "(?i)(No issues found|LGTM|looks good|clean|no problems detected)") {
        Write-Host "✅ File marked clean by AI ($fileName)"
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
        $mergeError = @{
            body = "❌ **AI Auto-Merge Failed:** $($_.Exception.Message)"
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments" -Headers $headersGH -Method Post -Body $mergeError
    }
}

Write-Host "🎯 AI review and merge process complete."
=======
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
>>>>>>> master
