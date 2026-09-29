# PodQuick R2 Windows Upload Script
$OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Load credentials from local private config (.env.local or .env)
$envFiles = @("$PSScriptRoot\.env.local", "$PSScriptRoot\.env")
foreach ($envFile in $envFiles) {
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -and !$line.StartsWith('#') -and $line.Contains('=')) {
                $parts = $line.Split('=', 2)
                $k = $parts[0].Trim()
                $v = $parts[1].Trim().Trim('"').Trim("'")
                if ($k -and $v -and ![Environment]::GetEnvironmentVariable($k, 'Process')) {
                    [Environment]::SetEnvironmentVariable($k, $v, 'Process')
                }
            }
        }
    }
}

$accountId = if ($env:R2_ACCOUNT_ID) { $env:R2_ACCOUNT_ID } else { 'YOUR_ACCOUNT_ID' }
$accessKeyId = if ($env:R2_ACCESS_KEY_ID) { $env:R2_ACCESS_KEY_ID } else { 'YOUR_ACCESS_KEY_ID' }
$secretAccessKey = if ($env:R2_SECRET_ACCESS_KEY) { $env:R2_SECRET_ACCESS_KEY } else { 'YOUR_SECRET_ACCESS_KEY' }
$bucketName = if ($env:R2_BUCKET_NAME) { $env:R2_BUCKET_NAME } else { 'pod-quick' }

Write-Host "====================================" -ForegroundColor Cyan
Write-Host "  PodQuick R2 Upload (Windows)   " -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# 2. Check credentials
$hasCreds = ($accountId -ne 'YOUR_ACCOUNT_ID' -and ![string]::IsNullOrWhiteSpace($accountId) -and $accessKeyId -ne 'YOUR_ACCESS_KEY_ID' -and ![string]::IsNullOrWhiteSpace($accessKeyId) -and $secretAccessKey -ne 'YOUR_SECRET_ACCESS_KEY' -and ![string]::IsNullOrWhiteSpace($secretAccessKey))

if (-not $hasCreds) {
    Write-Host "ERROR: Cloudflare R2 credentials are not configured!" -ForegroundColor Red
    Write-Host "Please create a .env.local file in the project root with the following (see .env.example):" -ForegroundColor Yellow
    Write-Host "R2_ACCOUNT_ID=YOUR_CLOUDFLARE_ACCOUNT_ID" -ForegroundColor Gray
    Write-Host "R2_ACCESS_KEY_ID=YOUR_R2_ACCESS_KEY_ID" -ForegroundColor Gray
    Write-Host "R2_SECRET_ACCESS_KEY=YOUR_R2_SECRET_ACCESS_KEY" -ForegroundColor Gray
    Write-Host "R2_BUCKET_NAME=pod-quick" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Note: .env.local is in .gitignore and will never be committed to Git." -ForegroundColor Green
    exit 1
}

$exePath = "$PSScriptRoot\build\PodQuick.exe"
if (!(Test-Path $exePath)) {
    Write-Host "ERROR: File 'build\PodQuick.exe' not found! Please run build_windows.bat first." -ForegroundColor Red
    exit 1
}

function Upload-R2File($filePath, $remoteKey) {
    if (!(Test-Path $filePath)) { return }
    $fileName = Split-Path $filePath -Leaf
    Write-Host "Uploading $fileName -> Cloudflare R2 ($bucketName/$remoteKey)..." -ForegroundColor Yellow

    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $hostHeader = "$accountId.r2.cloudflarestorage.com"
    $canonicalPath = "/$bucketName/$remoteKey"
    $now = [DateTime]::UtcNow
    $amzDate = $now.ToString("yyyyMMddTHHmmssZ")
    $dateStamp = $now.ToString("yyyyMMdd")

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    $payloadHash = [System.BitConverter]::ToString($hashBytes).Replace('-','').ToLower()

    $canonicalHeaders = "host:$hostHeader`nx-amz-content-sha256:$payloadHash`nx-amz-date:$amzDate`n"
    $signedHeaders = "host;x-amz-content-sha256;x-amz-date"
    $canonicalRequest = "PUT`n$canonicalPath`n`n$canonicalHeaders`n$signedHeaders`n$payloadHash"

    $credentialScope = "$dateStamp/auto/s3/aws4_request"
    $reqHashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonicalRequest))
    $reqHashStr = [System.BitConverter]::ToString($reqHashBytes).Replace('-','').ToLower()
    $stringToSign = "AWS4-HMAC-SHA256`n$amzDate`n$credentialScope`n$reqHashStr"

    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes("AWS4$secretAccessKey")
    $kDate = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($dateStamp))
    $hmac.Key = $kDate
    $kRegion = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("auto"))
    $hmac.Key = $kRegion
    $kService = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("s3"))
    $hmac.Key = $kService
    $kSigning = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("aws4_request"))
    $hmac.Key = $kSigning
    $sigBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign))
    $signature = [System.BitConverter]::ToString($sigBytes).Replace('-','').ToLower()

    $authHeader = "AWS4-HMAC-SHA256 Credential=$accessKeyId/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature"
    $url = "https://$hostHeader$canonicalPath"

    $tmpOut = [System.IO.Path]::GetTempFileName()
    $httpCode = curl.exe -s -o $tmpOut -w "%{http_code}" -X PUT $url -H "Host: $hostHeader" -H "x-amz-date: $amzDate" -H "x-amz-content-sha256: $payloadHash" -H "Authorization: $authHeader" -H "Content-Type: application/octet-stream" --data-binary "@$filePath"
    $body = ""
    if (Test-Path $tmpOut) {
        $body = [System.IO.File]::ReadAllText($tmpOut)
        Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
    }

    if ($httpCode -eq "200" -or $httpCode -eq "201") {
        Write-Host "SUCCESS: Uploaded $fileName to R2 root!" -ForegroundColor Green
        Write-Host "URL: $url" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Upload $fileName (HTTP $httpCode)" -ForegroundColor Red
        if ($body) {
            Write-Host "Server Response: $body" -ForegroundColor DarkYellow
        }
    }
}

# 1. 上传 PodQuick.exe (单文件运行版本/应用内升级替换)
Upload-R2File "$PSScriptRoot\build\PodQuick.exe" "PodQuick.exe"

# 2. 上传 PodQuick_Setup.exe (标准 Windows 安装包)
$setupFile = "$PSScriptRoot\build\PodQuick_Setup.exe"
if (Test-Path $setupFile) {
    Upload-R2File $setupFile "PodQuick_Setup.exe"
}

# 3. 上传 release_info.json
$releaseInfoFile = "$PSScriptRoot\release_info.json"
if (Test-Path $releaseInfoFile) {
    Upload-R2File $releaseInfoFile "release_info.json"
}

Write-Host "====================================" -ForegroundColor Cyan
Write-Host "  Upload Task Finished!             " -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
