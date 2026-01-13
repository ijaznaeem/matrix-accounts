@echo off
echo ====================================
echo Matrix Accounts - Quick Start
echo ====================================
echo.
echo Starting Laravel server...
cd /d G:\Work-Flutter\matrix_accounts\laravel_sync
start "Laravel Server" /min cmd /c "php artisan serve"
echo.
echo Waiting for server to start...
timeout /t 3 /nobreak >nul
echo.
echo Testing API...
curl http://127.0.0.1:8000/api/health
echo.
echo.
echo ====================================
echo Server Status:
echo ====================================
echo Laravel API: http://127.0.0.1:8000
echo.
echo To stop the server:
echo - Close the "Laravel Server" window
echo - Or press Ctrl+C in that window
echo.
echo Next steps:
echo 1. Run Flutter app: flutter run
echo 2. Test sync in the app
echo.
pause
