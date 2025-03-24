
#!/bin/bash
set -e
# === 預設參數 ===
NGINX_VERSION="1.24.0"
BUILD_DIR="/home/nginx_build_geoip2"

# === 處理傳入參數 ===
for ARG in "$@"; do
    case $ARG in
        --path=*)
            BUILD_DIR="${ARG#*=}"
            shift
            ;;
        --version=*)
            NGINX_VERSION="${ARG#*=}"
            shift
            ;;
        *)
            echo "❌ 未知參數：$ARG"
            exit 1
            ;;
    esac
done

NGINX_SRC_DIR="$BUILD_DIR/nginx-${NGINX_VERSION}"
HTTP_ZIP_URL=https://github.com/leev/ngx_http_geoip2_module/archive/refs/heads/master.zip
HTTP_MODULE_DIR=$BUILD_DIR/ngx_http_geoip2_module
GEOIP_DB_PATH=/etc/nginx/GeoLite2-Country.mmdb
GEOIP_DB_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"

# === 自動偵測 nginx modules 目錄 ===
NGINX_MODULES_PATH=$(nginx -V 2>&1 | grep -- '--modules-path=' | sed -E 's/.*--modules-path=([^ ]+).*/\1/')
if [ -z "$NGINX_MODULES_PATH" ]; then
  NGINX_MODULES_PATH="/usr/local/nginx/modules"  # fallback 預設值
fi

echo "🧩 NGINX modules path: $NGINX_MODULES_PATH"

echo "[1/7] 建立工作目錄：$BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "[2/7] 安裝必要套件"
sudo apt update
sudo apt install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev wget unzip libmaxminddb-dev

echo "[3/7] 下載 NGINX 原始碼 v$NGINX_VERSION"
wget -q http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
tar -xf nginx-${NGINX_VERSION}.tar.gz

echo "[4/7] 下載並解壓 ngx_http_geoip2_module"
wget -q -O ngx_http_geoip2_module.zip "$HTTP_ZIP_URL"
unzip -q ngx_http_geoip2_module.zip
mv ngx_http_geoip2_module-* "$HTTP_MODULE_DIR"

echo "[5/7] 編譯 ngx_http_geoip2_module 為動態模組"
cd "$NGINX_SRC_DIR"
./configure --with-compat --add-dynamic-module="$HTTP_MODULE_DIR"
make modules

echo "📁 建立模組目錄（若不存在）：$NGINX_MODULES_PATH"
sudo mkdir -p "$NGINX_MODULES_PATH"

echo "📦 安裝模組到：$NGINX_MODULES_PATH"
sudo cp objs/ngx_http_geoip2_module.so "$NGINX_MODULES_PATH/"

echo "[6/7] 下載 GeoLite2-Country.mmdb 至 $GEOIP_DB_PATH"
sudo mkdir -p /etc/nginx
sudo wget -q -O "$GEOIP_DB_PATH" "$GEOIP_DB_URL"
[ -f "$GEOIP_DB_PATH" ] && echo "✅ GeoIP2 資料庫已下載" || echo "❌ GeoIP2 資料庫下載失敗"

echo "[7/8] 凍結 nginx 套件版本，避免未來 apt 升級導致 geoip2 模組失效..."
sudo apt-mark hold nginx nginx-core nginx-common

echo "[8/9]"
echo "✅ 已凍結以下套件："
apt-mark showhold | grep nginx || echo "⚠️ 未成功凍結，請手動確認"
echo "📌 提醒：若未來需要升級 nginx，請務必重新編譯 geoip2 模組以相容新版 nginx binary。"

echo "[9/9] ✅ 安裝完成！請在 nginx.conf 做以下設定："
echo ""
echo "---- [ nginx.conf 最上方 ] ----"
echo "load_module $NGINX_MODULES_PATH/ngx_http_geoip2_module.so;"
echo ""
echo "---- [ http {} 區塊內範例 ] ----"
cat <<'EOF'
http {
    geoip2 /etc/nginx/GeoLite2-Country.mmdb {
       auto_reload 5m;
       $geoip2_metadata_country_build metadata build_epoch;
       $geoip2_data_country_code source=$remote_addr country iso_code;
       $geoip2_data_country_name country names en;
       }

    geoip2 /etc/nginx/GeoLite2-City.mmdb {
       $geoip2_data_city_name city names en;
       $geoip2_data_city_longitude location longitude;
       $geoip2_data_city_latitude location latitude;
       }
     }

    log_format json_combined escape=json
        '{'
                '"time_local":"$time_local",'
                '"remote_addr":"$remote_addr",'
                '"request":"$request",'
                '"status": "$status",'
                '"body_bytes_sent":"$body_bytes_sent",'
                '"http_referer":"$http_referer",'
                '"http_user_agent":"$http_user_agent",'
                '"request_time":"$request_time",'
                '"upstream_response_time":"$upstream_response_time",'
                '"country_name":"$geoip2_data_country_name",'
                '"country_code":"$geoip2_data_country_code",'
                '"city_name":"$geoip2_data_city_name",'
                '"longitude":"$geoip2_data_city_longitude",'
                '"latitude":"$geoip2_data_city_latitude"'
        '}';
    access_log /var/log/nginx/access.log;

    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        modsecurity on;
        modsecurity_rules_file /etc/nginx/modsecurity.conf;

        access_log /var/log/nginx/access_json.log json_combined;

        root /var/www/html;

        # Add index.php to the list if you are using PHP
        index index.html index.htm index.nginx-debian.html;

        server_name _;

        location / {
                # First attempt to serve request as file, then
                # as directory, then fall back to displaying a 404.
                try_files $uri $uri/ =404;
        }

        location /basic_status {
                stub_status;
                allow 127.0.0.1;
                deny all;
        }

         location /geoip2 {
         default_type text/html;
         charset utf-8;
         return 200 "geoip2_data_country_name=$geoip2_data_country_name<br>geoip2_data_country_code=$geoip2_data_country_code<br>geoip2_data_city_name=$geoip2_data_city_name\n";
        }
}
}

EOF

echo ""
echo "🚀 最後請執行："
echo "    sudo nginx -t && sudo systemctl restart nginx"
