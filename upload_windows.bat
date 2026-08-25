@echo off
echo ====================================
echo   PodQuick R2 Upload (Windows)
echo ====================================

if not exist "build\PodQuick.exe" (
    echo ERROR: File 'build\PodQuick.exe' not found. Please run build_windows.bat first!
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$accountId='YOUR_CLOUDFLARE_ACCOUNT_ID'; $accessKeyId='YOUR_R2_ACCESS_KEY_ID'; $secretAccessKey='YOUR_R2_SECRET_ACCESS_KEY'; $bucketName='pod-quick'; function Upload-R2File($filePath, $remoteKey) { if (!(Test-Path $filePath)) { return }; $fileName = Split-Path $filePath -Leaf; Write-Host ('Uploading ' + $fileName + ' -> R2...'); $bytes = [System.IO.File]::ReadAllBytes($filePath); $hostHeader = $accountId + '.r2.cloudflarestorage.com'; $canonicalPath = '/' + $bucketName + '/' + $remoteKey; $now = [DateTime]::UtcNow; $amzDate = $now.ToString('yyyyMMddTHHmmssZ'); $dateStamp = $now.ToString('yyyyMMdd'); $sha256 = [System.Security.Cryptography.SHA256]::Create(); $payloadHash = [System.BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-','').ToLower(); $nl = [char]10; $canonicalHeaders = 'host:' + $hostHeader + $nl + 'x-amz-content-sha256:' + $payloadHash + $nl + 'x-amz-date:' + $amzDate + $nl; $signedHeaders = 'host;x-amz-content-sha256;x-amz-date'; $canonicalRequest = 'PUT' + $nl + $canonicalPath + $nl + $nl + $canonicalHeaders + $nl + $signedHeaders + $nl + $payloadHash; $credentialScope = $dateStamp + '/auto/s3/aws4_request'; $reqHashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonicalRequest)); $reqHashStr = [System.BitConverter]::ToString($reqHashBytes).Replace('-','').ToLower(); $stringToSign = 'AWS4-HMAC-SHA256' + $nl + $amzDate + $nl + $credentialScope + $nl + $reqHashStr; $hmac = New-Object System.Security.Cryptography.HMACSHA256; $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes('AWS4' + $secretAccessKey); $kDate = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($dateStamp)); $hmac.Key = $kDate; $kRegion = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('auto')); $hmac.Key = $kRegion; $kService = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('s3')); $hmac.Key = $kService; $kSigning = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('aws4_request')); $hmac.Key = $kSigning; $signature = [System.BitConverter]::ToString($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign))).Replace('-','').ToLower(); $authHeader = 'AWS4-HMAC-SHA256 Credential=' + $accessKeyId + '/' + $credentialScope + ', SignedHeaders=' + $signedHeaders + ', Signature=' + $signature; $url = 'https://' + $hostHeader + $canonicalPath; $resp = curl.exe -s -w '%%{http_code}' -X PUT $url -H \"Host: $hostHeader\" -H \"x-amz-date: $amzDate\" -H \"x-amz-content-sha256: $payloadHash\" -H \"Authorization: $authHeader\" -H \"Content-Type: application/octet-stream\" --data-binary \"@$filePath\"; if ($resp -eq '200' -or $resp -eq '201') { Write-Host ('SUCCESS: Uploaded ' + $fileName) -ForegroundColor Green; Write-Host ('URL: ' + $url) -ForegroundColor Green; } else { Write-Host ('FAILED: Upload ' + $fileName + ' (HTTP ' + $resp + ')') -ForegroundColor Red; } }; Upload-R2File 'build\PodQuick.exe' 'PodQuick.exe';"

echo.
echo ====================================
echo Upload Task Finished!
echo ====================================
pause
