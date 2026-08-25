#!/usr/bin/env bash
set -e

echo "===================================="
echo "  PodQuick R2 Upload (macOS)"
echo "===================================="

DMG_FILE="build/PodQuick.dmg"
if [ ! -f "$DMG_FILE" ]; then
  DMG_FILE="build/PodQuick-macOS.dmg"
fi

if [ ! -f "$DMG_FILE" ]; then
  echo "❌ 未找到 build/PodQuick.dmg，请先运行 ./build_macos.sh！"
  exit 1
fi

ACCOUNT_ID="YOUR_CLOUDFLARE_ACCOUNT_ID"
ACCESS_KEY_ID="YOUR_R2_ACCESS_KEY_ID"
SECRET_ACCESS_KEY="YOUR_R2_SECRET_ACCESS_KEY"
BUCKET_NAME="pod-quick"
REMOTE_KEY="PodQuick.dmg"

echo "正在上传 $DMG_FILE 到 R2 ($BUCKET_NAME/$REMOTE_KEY)..."

HOST="${ACCOUNT_ID}.r2.cloudflarestorage.com"
DATE_STAMP=$(date -u +'%Y%m%d')
AMZ_DATE=$(date -u +'%Y%m%dT%H%M%SZ')

PAYLOAD_HASH=$(openssl dgst -sha256 "$DMG_FILE" | awk '{print $2}')
CANONICAL_PATH="/${BUCKET_NAME}/${REMOTE_KEY}"
CANONICAL_HEADERS="host:${HOST}\nx-amz-content-sha256:${PAYLOAD_HASH}\nx-amz-date:${AMZ_DATE}\n"
SIGNED_HEADERS="host;x-amz-content-sha256;x-amz-date"
CANONICAL_REQ="PUT\n${CANONICAL_PATH}\n\n${CANONICAL_HEADERS}${SIGNED_HEADERS}\n${PAYLOAD_HASH}"

CREDENTIAL_SCOPE="${DATE_STAMP}/auto/s3/aws4_request"
REQ_HASH=$(printf "$CANONICAL_REQ" | openssl dgst -sha256 | awk '{print $2}')
STRING_TO_SIGN="AWS4-HMAC-SHA256\n${AMZ_DATE}\n${CREDENTIAL_SCOPE}\n${REQ_HASH}"

kDate=$(printf "$DATE_STAMP" | openssl dgst -sha256 -hmac "AWS4${SECRET_ACCESS_KEY}" -binary)
kRegion=$(printf "auto" | openssl dgst -sha256 -mac HMAC -macopt "keyhex:$(echo -n "$kDate" | xxd -p -c 256)" -binary)
kService=$(printf "s3" | openssl dgst -sha256 -mac HMAC -macopt "keyhex:$(echo -n "$kRegion" | xxd -p -c 256)" -binary)
kSigning=$(printf "aws4_request" | openssl dgst -sha256 -mac HMAC -macopt "keyhex:$(echo -n "$kService" | xxd -p -c 256)" -binary)
SIGNATURE=$(printf "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt "keyhex:$(echo -n "$kSigning" | xxd -p -c 256)" | awk '{print $2}')

AUTH_HEADER="AWS4-HMAC-SHA256 Credential=${ACCESS_KEY_ID}/${CREDENTIAL_SCOPE}, SignedHeaders=${SIGNED_HEADERS}, Signature=${SIGNATURE}"

curl -X PUT "https://${HOST}${CANONICAL_PATH}" \
  -H "Host: ${HOST}" \
  -H "x-amz-date: ${AMZ_DATE}" \
  -H "x-amz-content-sha256: ${PAYLOAD_HASH}" \
  -H "Authorization: ${AUTH_HEADER}" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@${DMG_FILE}"

echo ""
echo "🎉 上传完成！"
echo "🔗 下载链接: https://${HOST}${CANONICAL_PATH}"
