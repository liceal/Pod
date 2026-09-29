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

ACCOUNT_ID="${R2_ACCOUNT_ID:-YOUR_ACCOUNT_ID}"
ACCESS_KEY_ID="${R2_ACCESS_KEY_ID:-YOUR_ACCESS_KEY_ID}"
SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY:-YOUR_SECRET_ACCESS_KEY}"
BUCKET_NAME="${R2_BUCKET_NAME:-pod-quick}"

upload_to_r2() {
  local FILE_PATH="$1"
  local REMOTE_KEY="$2"
  local HOST="${ACCOUNT_ID}.r2.cloudflarestorage.com"
  local DATE_STAMP=$(date -u +'%Y%m%d')
  local AMZ_DATE=$(date -u +'%Y%m%dT%H%M%SZ')

  echo "正在上传 $FILE_PATH 到 R2 ($BUCKET_NAME/$REMOTE_KEY)..."

  local PAYLOAD_HASH=$(openssl dgst -sha256 "$FILE_PATH" | awk '{print $2}')
  local CANONICAL_PATH="/${BUCKET_NAME}/${REMOTE_KEY}"
  local CANONICAL_HEADERS="host:${HOST}\nx-amz-content-sha256:${PAYLOAD_HASH}\nx-amz-date:${AMZ_DATE}\n"
  local SIGNED_HEADERS="host;x-amz-content-sha256;x-amz-date"
  local CANONICAL_REQ="PUT\n${CANONICAL_PATH}\n\n${CANONICAL_HEADERS}${SIGNED_HEADERS}\n${PAYLOAD_HASH}"

  local CREDENTIAL_SCOPE="${DATE_STAMP}/auto/s3/aws4_request"
  local REQ_HASH=$(printf "$CANONICAL_REQ" | openssl dgst -sha256 | awk '{print $2}')
  local STRING_TO_SIGN="AWS4-HMAC-SHA256\n${AMZ_DATE}\n${CREDENTIAL_SCOPE}\n${REQ_HASH}"

  local kDate=$(printf "$DATE_STAMP" | openssl dgst -sha256 -hmac "AWS4${SECRET_ACCESS_KEY}" -binary)
  local kRegion=$(printf "auto" | openssl dgst -sha256 -mac HMAC -macopt "keyhex:$(echo -n "$kDate" | xxd -p -c 256)" -binary)
  local kService=$(printf "s3" | openssl dgst -sha256 -mac HMAC -macopt "keyhex:$(echo -n "$kRegion" | xxd -p -c 256)" -binary)
  local kSigning=$(printf "aws4_request" | openssl dgst -sha256 -mac HMAC -macopt "keyhex:$(echo -n "$kService" | xxd -p -c 256)" -binary)
  local SIGNATURE=$(printf "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt "keyhex:$(echo -n "$kSigning" | xxd -p -c 256)" | awk '{print $2}')

  local AUTH_HEADER="AWS4-HMAC-SHA256 Credential=${ACCESS_KEY_ID}/${CREDENTIAL_SCOPE}, SignedHeaders=${SIGNED_HEADERS}, Signature=${SIGNATURE}"

  curl -X PUT "https://${HOST}${CANONICAL_PATH}" \
    -H "Host: ${HOST}" \
    -H "x-amz-date: ${AMZ_DATE}" \
    -H "x-amz-content-sha256: ${PAYLOAD_HASH}" \
    -H "Authorization: ${AUTH_HEADER}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${FILE_PATH}"
  echo ""
  echo "🎉 上传成功: $REMOTE_KEY"
}

# 1. 上传 PodQuick.dmg
upload_to_r2 "$DMG_FILE" "PodQuick.dmg"

# 2. 上传 release_info.json
if [ -f "release_info.json" ]; then
  upload_to_r2 "release_info.json" "release_info.json"
fi

echo "===================================="
echo "🎉 上传发布完成！"
echo "===================================="
