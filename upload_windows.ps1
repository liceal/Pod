# PodQuick R2 Windows Upload Script
$OutputEncoding = [System.Text.Encoding]::UTF8

$accountId = 'YOUR_CLOUDFLARE_ACCOUNT_ID'
$accessKeyId = 'YOUR_R2_ACCESS_KEY_ID'
$secretAccessKey = 'YOUR_R2_SECRET_ACCESS_KEY'
$bucketName = 'pod-quick'

Write-Host "====================================" -ForegroundColor Cyan
Write-Host "  PodQuick R2 Upload (Windows)   " -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

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

    $resp = curl.exe -s -w "%{http_code}" -X PUT $url -H "Host: $hostHeader" -H "x-amz-date: $amzDate" -H "x-amz-content-sha256: $payloadHash" -H "Authorization: $authHeader" -H "Content-Type: application/octet-stream" --data-binary "@$filePath"

    if ($resp -eq "200" -or $resp -eq "201") {
        Write-Host "SUCCESS: Uploaded $fileName to R2 root!" -ForegroundColor Green
        Write-Host "URL: $url" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Upload $fileName (HTTP $resp)" -ForegroundColor Red
    }
}

# 1. 上传 PodQuick.exe
Upload-R2File "$PSScriptRoot\build\PodQuick.exe" "PodQuick.exe"

# 2. 上传 release_info.json
$releaseInfoFile = "$PSScriptRoot\release_info.json"
if (Test-Path $releaseInfoFile) {
    Upload-R2File $releaseInfoFile "release_info.json"
}

Write-Host "====================================" -ForegroundColor Cyan
Write-Host "  Upload Task Finished!             " -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
