$root = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev\animated_notch_bottom_bar-1.0.4\lib"
Get-ChildItem -Path $root -Recurse -Filter *.dart | ForEach-Object {
    Write-Output "===== $($_.FullName) ====="
    Get-Content $_.FullName | Select-Object -First 200
}