#!/bin/sh
# StreamSight — 首次環境設定
# 用法：sh setup.sh
set -e

# ── Clone 子專案 ────────────────────────────────────────────────
echo ">>> Clone 子專案..."

clone_if_missing() {
  dir="$1"; url="$2"
  if [ -d "$dir/.git" ]; then
    echo "  $dir 已存在，跳過"
  else
    git clone "$url" "$dir"
  fi
}

clone_if_missing StreamSightBackend   https://github.com/Yintc123/StreamSightBackend.git
clone_if_missing StreamSightFrontend  https://github.com/Yintc123/StreamSightFrontend.git
clone_if_missing StreamSightStreamlit https://github.com/Yintc123/StreamSightStreamlit.git

# ── 產生 .env ────────────────────────────────────────────────────
echo ""
echo ">>> 建立 .env..."

if [ -f .env ]; then
  printf "  .env 已存在，要覆蓋嗎？[y/N] "
  read -r overwrite
  case "$overwrite" in
    [yY]) ;;
    *) echo "  跳過，保留現有 .env"; echo ""; echo ">>> 完成！執行 docker compose up -d 啟動服務"; exit 0 ;;
  esac
fi

# 問 admin 資訊
echo ""
echo "--- 初始管理員設定 ---"

printf "  Username [admin]: "
read -r admin_username
admin_username="${admin_username:-admin}"
# 正規化（strip + lowercase），對齊後端 normalize_username
admin_username=$(printf '%s' "$admin_username" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if ! printf '%s' "$admin_username" | grep -qE '^[a-z0-9._-]{3,100}$'; then
  echo "  錯誤：username 只能含小寫英數、. _ -，長度 3-100 個字元" >&2
  exit 1
fi

printf "  Display name [Administrator]: "
read -r admin_name
admin_name="${admin_name:-Administrator}"

read_secret() {
  prompt="$1"
  printf '%s' "$prompt" >&2
  if [ -t 0 ]; then
    stty -echo
    read -r _secret
    stty echo
    printf '\n' >&2
  else
    read -r _secret
  fi
  printf '%s' "$_secret"
}

admin_password=$(read_secret "  Password: ")

if [ -z "$admin_password" ]; then
  echo "  錯誤：密碼不能為空" >&2
  exit 1
fi

_pw_len=$(printf '%s' "$admin_password" | wc -c | tr -d ' ')
if [ "$_pw_len" -lt 8 ] || [ "$_pw_len" -gt 128 ]; then
  echo "  錯誤：密碼長度必須為 8-128 個字元（目前：${_pw_len}）" >&2
  exit 1
fi

admin_password2=$(read_secret "  確認密碼: ")

if [ "$admin_password" != "$admin_password2" ]; then
  echo "  錯誤：兩次密碼不一致" >&2
  exit 1
fi

# 產生 secrets（純隨機，不依賴 .env.example 的值）
echo ""
echo "  產生 secrets..."

rand_base64() {
  if command -v openssl > /dev/null 2>&1; then
    openssl rand -base64 48 | tr -d '\n'
  else
    head -c 48 /dev/urandom | base64 | tr -d '\n='
  fi
}

ENCRYPTION_KEY=$(rand_base64)
JWT_SECRET_KEY=$(rand_base64)
REFRESH_TOKEN_HASH_SECRET=$(rand_base64)
SESSION_SECRET=$(rand_base64)

# .env.example 作為非 secret 設定的結構基底；
# secret 與 admin 欄位直接覆寫整行（key 名稱比對，不看 placeholder 值）
cp .env.example .env

set_env() {
  key="$1"; val="$2"
  tmp=$(mktemp)
  sed "s|^${key}=.*|${key}=${val}|" .env > "$tmp" && mv "$tmp" .env
}

set_env ENCRYPTION_KEY          "$ENCRYPTION_KEY"
set_env JWT_SECRET_KEY          "$JWT_SECRET_KEY"
set_env REFRESH_TOKEN_HASH_SECRET "$REFRESH_TOKEN_HASH_SECRET"
set_env SESSION_SECRET          "$SESSION_SECRET"
set_env INITIAL_ADMIN_USERNAME  "$admin_username"
set_env INITIAL_ADMIN_NAME      "$admin_name"
set_env INITIAL_ADMIN_PASSWORD  "$admin_password"

echo "  .env 已產生"

# ── 完成 ─────────────────────────────────────────────────────────
echo ""
echo ">>> 完成！執行以下指令啟動服務："
echo "  docker compose up -d"
