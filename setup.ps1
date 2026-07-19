# StreamSight — 首次環境設定（Windows PowerShell）
# 用法：.\setup.ps1
# 需要 PowerShell 5.1+（Windows 內建）或 PowerShell 7+
#
# 若出現「無法執行指令碼」，先執行一次：
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

$ErrorActionPreference = "Stop"

# ── Clone 子專案 ─────────────────────────────────────────────────
Write-Host ">>> Clone 子專案..."

function Clone-IfMissing($Dir, $Url) {
    if (Test-Path "$Dir\.git") {
        Write-Host "  $Dir 已存在，跳過"
    } else {
        git clone $Url $Dir
    }
}

Clone-IfMissing "StreamSightBackend"   "https://github.com/Yintc123/StreamSightBackend.git"
Clone-IfMissing "StreamSightFrontend"  "https://github.com/Yintc123/StreamSightFrontend.git"
Clone-IfMissing "StreamSightStreamlit" "https://github.com/Yintc123/StreamSightStreamlit.git"

# ── 建立 .env ─────────────────────────────────────────────────────
Write-Host ""
Write-Host ">>> 建立 .env..."

if (Test-Path ".env") {
    $overwrite = Read-Host "  .env 已存在，要覆蓋嗎？[y/N]"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") {
        Write-Host "  跳過，保留現有 .env"
        Write-Host ""
        Write-Host ">>> 完成！執行 docker compose up -d 啟動服務"
        exit 0
    }
}

# ── Admin 資訊 ───────────────────────────────────────────────────
Write-Host ""
Write-Host "--- 初始管理員設定 ---"

$adminUsername = Read-Host "  Username [admin]"
if ([string]::IsNullOrEmpty($adminUsername)) { $adminUsername = "admin" }

$adminName = Read-Host "  Display name [Administrator]"
if ([string]::IsNullOrEmpty($adminName)) { $adminName = "Administrator" }

$adminPassSecure  = Read-Host "  Password"         -AsSecureString
$adminPass2Secure = Read-Host "  確認密碼"         -AsSecureString

# SecureString → plaintext（僅在記憶體中短暫存在）
$bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassSecure)
$bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPass2Secure)
$adminPassword  = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr1)
$adminPassword2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)

if ([string]::IsNullOrEmpty($adminPassword)) {
    Write-Error "錯誤：密碼不能為空"; exit 1
}
if ($adminPassword -ne $adminPassword2) {
    Write-Error "錯誤：兩次密碼不一致"; exit 1
}

# ── 產生 secrets ─────────────────────────────────────────────────
Write-Host ""
Write-Host "  產生 secrets..."

function New-RandomBase64 {
    $bytes = New-Object byte[] 48
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    [System.Convert]::ToBase64String($bytes)
}

$secrets = @{
    "ENCRYPTION_KEY"            = New-RandomBase64
    "JWT_SECRET_KEY"            = New-RandomBase64
    "REFRESH_TOKEN_HASH_SECRET" = New-RandomBase64
    "SESSION_SECRET"            = New-RandomBase64
    "INITIAL_ADMIN_USERNAME"    = $adminUsername
    "INITIAL_ADMIN_NAME"        = $adminName
    "INITIAL_ADMIN_PASSWORD"    = $adminPassword
}

# ── 讀 .env.example，逐行覆寫對應欄位 ──────────────────────────
$lines = Get-Content ".env.example" | ForEach-Object {
    $line = $_
    foreach ($key in $secrets.Keys) {
        if ($line -match "^$key=") {
            $line = "${key}=$($secrets[$key])"
            break
        }
    }
    $line
}

# 寫出 UTF-8 without BOM（docker / bash 相容）
$envPath = Join-Path $PWD ".env"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($envPath, $lines, $utf8NoBom)

Write-Host "  .env 已產生"
Write-Host ""
Write-Host ">>> 完成！執行以下指令啟動服務："
Write-Host "  docker compose up -d"
