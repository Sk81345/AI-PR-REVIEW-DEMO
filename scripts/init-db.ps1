# scripts/init_db.ps1
# Initializes SQLite database for PR logs
$database = "ai_reviews.db"

if (-not (Test-Path $database)) {
    Write-Host "📦 Creating SQLite database for AI reviews..."
    # The runner already has the SQLite assembly reference, but we use Add-Type defensively.
    Add-Type -AssemblyName System.Data.SQLite
    $connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$database;Version=3;")
    $connection.Open()

    $cmd = $connection.CreateCommand()
    $cmd.CommandText = @"
    CREATE TABLE IF NOT EXISTS reviews (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pr_number TEXT,
        file_name TEXT,
        review_summary TEXT,
        # Ensure timestamp is recorded for ordering past reviews
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    );
"@
    $cmd.ExecuteNonQuery()
    $connection.Close()
    Write-Host "✅ Database initialized."
} else {
    Write-Host "✅ Database already exists."
}
