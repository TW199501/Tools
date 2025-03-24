#!/bin/bash
set -e

INSTALL_DIR="/home/nginxWebUI"
SERVICE_NAME="nginxwebui"
PORT=8080
JAR_NAME="nginxWebUI.jar"
JAR_PATH="$INSTALL_DIR/$JAR_NAME"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
JDK_PATH="/usr/bin/java"

GEOIP_DIR="/etc/nginx"
GEOIP_UPDATE_SCRIPT="/usr/local/bin/update-geoip2.sh"
GEOIP_LOG="/var/log/geoip2_update.log"

COUNTRY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
CITY_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"

echo "🔧 安裝 OpenJDK 11..."
sudo apt update
sudo apt install -y openjdk-11-jdk wget unzip curl

echo "📁 建立資料夾 $INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
sudo chown $USER:$USER "$INSTALL_DIR"

echo "🌐 抓取最新版 nginxWebUI 版本號..."
LATEST_VERSION=$(curl -s https://gitee.com/cym1102/nginxWebUI/releases | grep -oP 'releases/download/\K[0-9]+\.[0-9]+\.[0-9]+' | sort -Vr | head -n 1)

if [ -z "$LATEST_VERSION" ]; then
  echo "❌ 無法取得最新版號，請檢查網路或 Gitee"
  exit 1
fi

echo "📦 最新版為 v$LATEST_VERSION，下載中..."
JAR_URL="https://gitee.com/cym1102/nginxWebUI/releases/download/${LATEST_VERSION}/nginxWebUI-${LATEST_VERSION}.jar"
wget -O "$JAR_PATH" "$JAR_URL"

echo "📝 建立 systemd 服務：$SERVICE_NAME"
sudo tee "$SYSTEMD_FILE" >/dev/null <<EOF
[Unit]
Description=NginxWebUI
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$JDK_PATH -jar -Dfile.encoding=UTF-8 $JAR_PATH --server.port=$PORT --project.home=$INSTALL_DIR
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "🔄 重新載入 systemd 並啟用 $SERVICE_NAME"
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl restart $SERVICE_NAME

echo "🌍 安裝 GeoLite2-Country / City 至 $GEOIP_DIR"
sudo mkdir -p "$GEOIP_DIR"
sudo wget -q -O "$GEOIP_DIR/GeoLite2-Country.mmdb" "$COUNTRY_URL"
sudo wget -q -O "$GEOIP_DIR/GeoLite2-City.mmdb" "$CITY_URL"

echo "🛠️ 建立 GeoIP2 自動更新腳本：$GEOIP_UPDATE_SCRIPT"
sudo tee "$GEOIP_UPDATE_SCRIPT" >/dev/null <<'EOS'

#!/bin/bash
set -e

# === GeoIP2 mmdb 下載來源 ===
COUNTRY_URL="https://cdn.jsdelivr.net/gh/P3TERX/GeoLite.mmdb/GeoLite2-Country.mmdb"
CITY_URL="https://cdn.jsdelivr.net/gh/P3TERX/GeoLite.mmdb/GeoLite2-City.mmdb"

# === 存放路徑 ===
COUNTRY_PATH="/etc/nginx/GeoLite2-Country.mmdb"
CITY_PATH="/etc/nginx/GeoLite2-City.mmdb"

# === 暫存目錄 ===
TMP_DIR="/tmp/geoip2_update"
mkdir -p "$TMP_DIR"

# === 通用下載並替換 ===
download_and_replace() {
    local url="$1"
    local path="$2"
    local name="$(basename "$path")"
    local tmp_file="$TMP_DIR/$name"

    echo "🌐 正在下載 $name ..."
    wget -q -O "$tmp_file" "$url"

    if [ -s "$tmp_file" ]; then
        sudo mv "$tmp_file" "$path"
        echo "✅ 已更新：$name"
    else
        echo "❌ 下載失敗或檔案為空：$name，略過"
    fi
}

download_and_replace "$COUNTRY_URL" "$COUNTRY_PATH"
download_and_replace "$CITY_URL" "$CITY_PATH"

# === 檢查 nginx 並 reload ===
echo "🔁 檢查 nginx 設定 ..."
if nginx -t 2>/dev/null; then
    sudo systemctl reload nginx && echo "🚀 nginx 已重新載入"
else
    echo "⚠️ nginx 設定錯誤，未重載"
fi
EOS

sudo chmod +x "$GEOIP_UPDATE_SCRIPT"

echo "📅 加入排程，每週三與六凌晨 03:00 自動更新 GeoIP2"
sudo crontab -l | {
    cat
    echo ""
    echo "# 每週三與六更新 GeoIP2 mmdb 並 reload nginx"
    echo "0 3 * * 3,6 $GEOIP_UPDATE_SCRIPT >> $GEOIP_LOG 2>&1"
} | sudo crontab -

echo ""
echo "✅ 全部安裝完成！"
echo "🌐 nginxWebUI： http://$(hostname -I | awk '{print $1}'):$PORT/"
echo "🔐 預設帳號：admin / 123456"
echo "📦 GeoIP2 已安裝於：$GEOIP_DIR"
echo "🕓 每週三、六 03:00 自動更新 GeoIP2 資料庫"
echo "執行" "chmod +x install_nginxwebui_with_geoip2.sh"
echo "執行" "./install_nginxwebui_with_geoip2.sh"
