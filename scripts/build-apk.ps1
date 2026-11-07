# Build APK cho Ví Lép (máy có Android SDK + JDK 21)
#
#   pwsh ./scripts/build-apk.ps1 -ApiBase http://192.168.1.30:5080
#
# Nếu bạn dùng Android Studio: mở apps/mobile rồi Run/Build APK, không cần script này.
param(
    [string]$ApiBase = "http://192.168.1.30:5080",
    [string]$JdkHome = $env:JAVA_HOME,
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$AndroidUserHome = "$env:TEMP\vilep-android-home"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if (-not $JdkHome -or -not (Test-Path $JdkHome)) {
    throw "Thiếu JAVA_HOME (cần JDK 17 hoặc 21). Cài Android Studio hoặc Temurin rồi đặt JAVA_HOME."
}
if (-not $AndroidSdk -or -not (Test-Path $AndroidSdk)) {
    throw "Thiếu ANDROID_HOME. Cài Android SDK (Android Studio > SDK Manager) rồi đặt ANDROID_HOME."
}

$env:JAVA_HOME = $JdkHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
New-Item -ItemType Directory -Force $AndroidUserHome | Out-Null
$env:ANDROID_USER_HOME = $AndroidUserHome
Remove-Item Env:ANDROID_SDK_HOME, Env:ANDROID_PREFS_ROOT -ErrorAction SilentlyContinue
$env:Path = "$JdkHome\bin;$AndroidSdk\platform-tools;$AndroidSdk\cmdline-tools\latest\bin;$env:Path"

Push-Location (Join-Path $root "apps/mobile")
flutter build apk --release --dart-define=API_BASE=$ApiBase
$apk = Join-Path $root "apps/mobile/build/app/outputs/flutter-apk/app-release.apk"
if (Test-Path $apk) {
    Write-Host "`nAPK: $apk" -ForegroundColor Green
    Write-Host "Cài lên điện thoại: adb install -r `"$apk`""
} else {
    Write-Host "Không thấy APK — xem log phía trên." -ForegroundColor Red
}
Pop-Location
