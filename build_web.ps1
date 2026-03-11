# Stop on error
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " StreamDot Protocol Builder (Dart2JS)"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Build version
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Write-Host "[INFO] Build Version: $timestamp"

# Run Flutter build (No Wasm)
Write-Host "[INFO] Running Flutter build..."

flutter build web `
--release `
--tree-shake-icons `
--dart2js-optimization O4 `
--no-source-maps `
--pwa-strategy none

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Flutter build failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "[INFO] Flutter build completed."

$webDir = "build\web"
$indexPath = "$webDir\index.html"

if (!(Test-Path $indexPath)) {
    Write-Host "[ERROR] index.html not found!" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Starting asset fingerprinting (Redundancy)..."

function Get-ShortHash($file) {
    $hash = (Get-FileHash $file -Algorithm SHA256).Hash
    return $hash.Substring(0,10).ToLower()
}

$renameMap = @{}

# STAGE 1: Hash the core JS files first
$coreFiles = @(
    "$webDir\main.dart.js",
    "$webDir\flutter.js"
)

foreach ($file in $coreFiles) {
    if (!(Test-Path $file)) { continue }

    $hash = Get-ShortHash $file
    $name = [System.IO.Path]::GetFileNameWithoutExtension($file)
    $ext = [System.IO.Path]::GetExtension($file)
    
    $newName = "$name.$hash$ext"
    $newPath = Join-Path $webDir $newName

    if (Test-Path $newPath) { Remove-Item $newPath -Force }
    Move-Item $file $newPath -Force

    $renameMap[[System.IO.Path]::GetFileName($file)] = $newName
    Write-Host "[HASH] $name -> $newName"
}

# STAGE 2: Update references INSIDE flutter_bootstrap.js before hashing it
$bootstrapPath = "$webDir\flutter_bootstrap.js"
if (Test-Path $bootstrapPath) {
    Write-Host "[INFO] Syncing internal Wasm/JS references..."
    $bootText = Get-Content $bootstrapPath -Raw
    foreach ($key in $renameMap.Keys) {
        $bootText = $bootText.Replace($key, $renameMap[$key])
    }
    Set-Content $bootstrapPath $bootText -Encoding UTF8

    # Now hash the bootstrap file itself
    $hash = Get-ShortHash $bootstrapPath
    $newName = "flutter_bootstrap.$hash.js"
    $newPath = Join-Path $webDir $newName
    
    if (Test-Path $newPath) { Remove-Item $newPath -Force }
    Move-Item $bootstrapPath $newPath -Force
    
    $renameMap["flutter_bootstrap.js"] = $newName
    Write-Host "[HASH] flutter_bootstrap -> $newName"
}

Write-Host "[INFO] Updating index.html with telemetry and hashes..."

$html = Get-Content $indexPath -Raw

# Update all references in HTML
foreach ($key in $renameMap.Keys) {
    $html = $html.Replace($key, $renameMap[$key])
}

if ($html -notmatch "rel=`"preconnect`"") {
    $preconnect = '<link rel="preconnect" href="/" crossorigin>'
    $html = $html.Replace("</head>", "$preconnect`n</head>")
}

# Inject Telemetry Loading Screen (Cleaned UX)
$loadingDiv = @"
<div id="loading">
<style>
body { margin:0; background:#0F172A; display:flex; justify-content:center; align-items:center; height:100vh; font-family: sans-serif; color:white; }
.spinner { border: 4px solid rgba(255, 255, 255, 0.1); border-left-color: #E6007A; border-radius: 50%; width: 48px; height: 48px; animation: spin 1s linear infinite; margin: 0 auto 20px auto; }
@keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
.loading-text { font-size: 18px; font-weight: bold; letter-spacing: 1px; color: #E6007A; }
</style>
<div style="text-align: center;">
    <div class="spinner" id="spinner"></div>
    <div class="loading-text" id="loading-title">INITIALIZING PROTOCOL...</div>
</div>
</div>
<script>
    function logBoot(msg, isError = false) {
        if (isError) {
            console.error('[StreamDot Boot] ' + msg);
        } else {
            console.log('[StreamDot Boot] ' + msg);
        }
    }

    window.addEventListener('error', function(e) {
        logBoot('FATAL ERROR: ' + e.message + ' at ' + e.filename + ':' + e.lineno, true);
        document.getElementById('loading-title').innerText = 'BOOT FAILED';
        document.getElementById('loading-title').style.color = '#ef4444';
        document.getElementById('spinner').style.borderLeftColor = '#ef4444';
        document.getElementById('spinner').style.animation = 'none';
    });

    logBoot('HTML Parsed. Downloading JS Engine...');

    window.addEventListener('flutter-first-frame', function() {
        logBoot('First frame rendered. Destroying telemetry UI...');
        setTimeout(function() {
            var loader = document.getElementById('loading');
            if (loader) loader.remove();
        }, 500);
    });
</script>
"@

if ($html -notmatch "id=`"loading`"") {
    $html = $html.Replace("<body>", "<body>`n$loadingDiv")
}

$buildLog = "<script>console.log('StreamDot Build Version: $timestamp');</script>"
$html = $html.Replace("</head>", "$buildLog`n</head>")

Set-Content $indexPath $html -Encoding UTF8
Write-Host "[INFO] index.html optimized with telemetry."

Write-Host "[INFO] Compressing assets..."
Get-ChildItem $webDir -Recurse -Include *.js,*.json | ForEach-Object {
    $gzipPath = "$($_.FullName).gz"
    $input = [IO.File]::OpenRead($_.FullName)
    $output = [IO.File]::Create($gzipPath)
    $gzip = New-Object IO.Compression.GzipStream($output, [IO.Compression.CompressionMode]::Compress)
    $input.CopyTo($gzip)
    $gzip.Close()
    $input.Close()
    $output.Close()
    Write-Host "[GZIP] $($_.Name)"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " BUILD SUCCESSFUL"
Write-Host " Location: build/web"
Write-Host " Version: $timestamp"
Write-Host "========================================" -ForegroundColor Green
Write-Host ""