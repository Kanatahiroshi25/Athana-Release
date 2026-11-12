# Athana release builder (Windows PowerShell).
# Run it from the project folder:   powershell -ExecutionPolicy Bypass -File tools\release.ps1
#
# What it does, in order:
#   1. sets the version in pubspec.yaml
#   2. connects your signing key (keystore) to the project  -> android\key.properties (stays on this PC only)
#   3. edits android\app\build.gradle.kts so release builds are signed with that key
#   4. builds the release APK and copies it to your Downloads folder
#
# Your keystore and passwords are typed here, on your own PC. They are never uploaded anywhere.

$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) { throw 'Run this from the project folder (the one that contains pubspec.yaml), for example D:\athana_app' }

function Plain([System.Security.SecureString]$s) { [System.Net.NetworkCredential]::new('', $s).Password }

# ---------------------------------------------------------------- 1. version
$utf8 = New-Object System.Text.UTF8Encoding($false)
function ReadText($path) { [System.IO.File]::ReadAllText($path, $utf8) }
function WriteText($path, $text) { [System.IO.File]::WriteAllText($path, $text, $utf8) }
$pub = Join-Path $root 'pubspec.yaml'
$p = ReadText $pub
$cur = [regex]::Match($p, '(?m)^version:\s*([\d.]+)\+(\d+)')
$nextCode = 200
if ($cur.Success) { $nextCode = [Math]::Max(200, [int]$cur.Groups[2].Value + 1) }
$curName = if ($cur.Success) { $cur.Groups[1].Value } else { '2.0.0' }
Write-Host "Now in the project: version $curName, code $($cur.Groups[2].Value)" -ForegroundColor DarkGray
$version = Read-Host "Version name for this release (press Enter for $curName)"
if ([string]::IsNullOrWhiteSpace($version)) { $version = $curName }
$code = Read-Host "Version code, must be higher than the last release (press Enter for $nextCode)"
if ([string]::IsNullOrWhiteSpace($code)) { $code = "$nextCode" }
$p = [regex]::Replace($p, '(?m)^version:.*$', "version: $version+$code")
WriteText $pub $p
# the version shown inside the app (About, update check) must match
$st = Join-Path $root 'lib\app_state.dart'
$a = ReadText $st
$a = [regex]::Replace($a, "const String kVersion = '[^']*';", "const String kVersion = '$version';")
WriteText $st $a
Write-Host "pubspec.yaml and the app now say version $version ($code)" -ForegroundColor Green

# ---------------------------------------------------------------- 2. keystore
$props = Join-Path $root 'android\key.properties'
if (Test-Path $props) {
    Write-Host 'android\key.properties already exists, keeping it.' -ForegroundColor Yellow
} else {
    $jks = Read-Host 'Full path of your keystore file (example D:\keys\athana.jks). If you do not have one yet, type a new path and I will create it'
    $jks = $jks.Trim('"')
    if (Test-Path $jks -PathType Container) { throw "That is a folder. Type the full path of the keystore FILE, for example $($jks.TrimEnd('\'))\athana.jks  (run: dir $jks   to see the file name)" }
    if (-not (Test-Path $jks)) {
        $kt = (Get-Command keytool -ErrorAction SilentlyContinue)
        if ($kt) { $kt = $kt.Source }
        else {
            $cand = @("$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe", "$env:ProgramFiles\Android\Android Studio1\jbr\bin\keytool.exe")
            foreach ($c in $cand) { if (Test-Path $c) { $kt = $c; break } }
        }
        if (-not $kt) { throw 'keytool was not found. Open Android Studio, use Build > Generate Signed App Bundle or APK to create a keystore, then run this again.' }
        New-Item -ItemType Directory -Force -Path (Split-Path $jks) | Out-Null
        Write-Host 'Creating a new keystore. keytool will ask for a password and some details. KEEP THE FILE AND PASSWORD SAFE: you need them for every future update.' -ForegroundColor Yellow
        & $kt -genkeypair -v -keystore $jks -keyalg RSA -keysize 2048 -validity 10000 -alias athana
        if (-not (Test-Path $jks)) { throw 'The keystore was not created.' }
    }
    $alias = Read-Host 'Key alias (press Enter for athana)'
    if ([string]::IsNullOrWhiteSpace($alias)) { $alias = 'athana' }
    $sp = Plain (Read-Host 'Keystore password' -AsSecureString)
    $kp = Plain (Read-Host 'Key password (press Enter if it is the same as the keystore password)' -AsSecureString)
    if ([string]::IsNullOrEmpty($kp)) { $kp = $sp }
    $path = $jks.Replace('\', '/')
    $lines = @("storePassword=$sp", "keyPassword=$kp", "keyAlias=$alias", "storeFile=$path")
    Set-Content -Path $props -Value $lines
    Write-Host 'android\key.properties written (keep it private, never upload it).' -ForegroundColor Green
}

# keep secrets out of git
$gi = Join-Path $root '.gitignore'
$giText = if (Test-Path $gi) { Get-Content $gi -Raw } else { '' }
foreach ($entry in @('android/key.properties', '*.jks', '*.keystore')) {
    if ($giText -notmatch [regex]::Escape($entry)) { Add-Content -Path $gi -Value $entry }
}

# ---------------------------------------------------------------- 3. gradle
$gradle = Join-Path $root 'android\app\build.gradle.kts'
if (-not (Test-Path $gradle)) { throw 'android\app\build.gradle.kts was not found.' }
$t = ReadText $gradle
if ($t -match 'keystoreProperties') {
    Write-Host 'build.gradle.kts is already set up for signing.' -ForegroundColor Yellow
} else {
    $header = @'
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

'@
    $sign = @'
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
'@
    if ($t -notmatch '(?m)^\s*buildTypes\s*\{' -or $t -notmatch 'signingConfigs\.getByName\("debug"\)') {
        throw 'build.gradle.kts looks different from the standard Flutter one. Send me a screenshot of that file and I will give you the exact change.'
    }
    $t = [regex]::Replace($t, '(?m)^\s*buildTypes\s*\{', { param($m) $sign.TrimEnd("`r", "`n") }, [System.Text.RegularExpressions.RegexOptions]::None)
    $t = $t -replace 'signingConfigs\.getByName\("debug"\)', 'signingConfigs.getByName("release")'
    $t = $header + $t
    WriteText $gradle $t
    Write-Host 'build.gradle.kts now signs release builds with your key.' -ForegroundColor Green
}

# ---------------------------------------------------------------- 4. build
Write-Host 'Building the release APK (a few minutes the first time)...' -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'The build failed. Send me a screenshot of the first red error line.' }
$apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
$dest = Join-Path $HOME "Downloads\Athana-Melody-$version.apk"
Copy-Item $apk $dest -Force
Write-Host ''
Write-Host "Done. Your APK: $dest" -ForegroundColor Green
Write-Host 'Install it on a phone, or test it on the emulator with:  flutter install -d emulator-5554'
