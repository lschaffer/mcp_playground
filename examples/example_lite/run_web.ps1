# Run MCP Playground Example in Web Mode with CORS disabled
Write-Host "Launching MCP Playground Example in Web Mode..." -ForegroundColor Green
Write-Host "Bypassing CORS by disabling web security..." -ForegroundColor Yellow

flutter run -d chrome --web-browser-flag "--disable-web-security" --web-browser-flag "--user-data-dir=C:\temp\chrome_dev_session"
