
powershell -Command "(New-Object Net.WebClient).DownloadFile('https://getfile.dokpub.com/yandex/get/https://disk.yandex.ru/d/10aqLqCm3uProg', 'binaries.zip' )"

@echo off
for /f "delims=" %%H in ('powershell -NoProfile -Command ^ "(Get-FileHash -Path 'binaries.zip' -Algorithm SHA256).Hash"') do (
    set "HASH=%%H"
)

if /i "%HASH%"=="E2D41F31F6DCEDD8D3F8F0578FEE74DB6C41C83FB2C0FEBDD8D75A97E1E6E1E2" (
	powershell Expand-Archive binaries.zip -DestinationPath "." -Force
	del "binaries.zip"
    exit /b 0
) else (
    echo *** HASH MISMATCH ***
    echo Actual: %HASH%
	pause
    exit /b 1
)
