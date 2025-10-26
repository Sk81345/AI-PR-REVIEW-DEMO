# $ErrorActionPreference = "Stop"

# Write-Host "📦 Creating SQLite database for AI reviews..."
# # Load the SQLite Assembly
# Add-Type -AssemblyName System.Data.SQLite
# $connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=ai_reviews.db")
# $connection.Open()

# # Create the reviews table if it doesn't exist
# $cmd = $connection.CreateCommand()
# $cmd.CommandText = @"
# CREATE TABLE IF NOT EXISTS reviews (
#     id INTEGER PRIMARY KEY AUTOINCREMENT,
#     pr_number INTEGER NOT NULL,
#     file_name TEXT NOT NULL,
#     review TEXT,
#     created_at TEXT NOT NULL
# );
# "@
# $cmd.ExecuteNonQuery()

# $connection.Close()
# Write-Host "✅ Database initialized."
