@echo off
cd /d "%~dp0"
echo ============================================
echo   Pixel Math / Neon After School
echo   Starting local server...
echo ============================================
java -jar kids-math-practice.jar --spring.config.additional-location=file:./application.properties
echo.
echo Server stopped.
pause
