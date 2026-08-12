$path = 'c:\Users\Nazmul\StudioProjects\diabeticsmeal\supabasesql\03_seed_foods.sql'
$lines = Get-Content $path
$insertCount = 0
$badRows = @()
foreach ($line in $lines) {
  if ($line -match "^\('") {
    $insertCount++
    # count commas only in the part after the id (which is wrapped in single quotes)
    $rest = ($line -split "'", 3)[2]
    $commas = ([regex]::Matches($rest, ',')).Count
    if ($commas -ne 17) {
      $id = ($line -split "'")[1]
      $badRows += "$id : $commas commas"
    }
  }
}
Write-Host "Rows: $insertCount (expected ~52)"
if ($badRows.Count -eq 0) { Write-Host "All rows have exactly 17 commas (18 columns)." }
else { Write-Host "BAD ROWS:"; $badRows | ForEach-Object { Write-Host "  $_" } }
