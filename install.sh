#!/bin/bash
set -e
# ========================================================================================
# Aura Protocol - v18.0 (Graduate Edition)
# 以 v10 稳定内核为绝对基石，融合新架构能力，经专业语法检查器最终验证
# ========================================================================================
SCRIPT_VERSION="18.0 (Graduate Edition)"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
CONFIG_DIR="/etc/aura-protocol"; AURA_OPERATIONS_DIR="/opt/aura-protocol"; OPTIMIZE_DIR="${AURA_OPERATIONS_DIR}/optimizer"
CONFIG_FILE="${CONFIG_DIR}/config.json"; CF_META_FILE="${CONFIG_DIR}/cf_meta.conf"; INSTALL_PATH="/usr/local/bin/aura-server"
SERVICE_FILE="/etc/systemd/system/aura-server.service"; TUNNEL_CONFIG_DIR="/etc/cloudflared"; TUNNEL_CONFIG_FILE="${TUNNEL_CONFIG_DIR}/config.yml"
OPTIMIZER_LOCK_FILE="/var/run/aura-optimizer.lock"; OPTIMIZER_LOG_FILE="${OPTIMIZE_DIR}/optimizer.log"; LOGROTATE_CONFIG_FILE="/etc/logrotate.d/aura-protocol"
info() { echo -e "${GREEN}[信息]${NC} $1"; }; warn() { echo -e "${YELLOW}[警告]${NC} $1"; }; error() { echo -e "${RED}[错误]${NC} $1"; exit 1; }; ask() { echo -e -n "${CYAN}[询问]${NC} $1"; }; check_root() { if [[ $EUID -ne 0 ]]; then error "本脚本需要以 root 用户或 sudo 权限运行。"; fi; }

install_aura() {
    info "开始安装 Aura Protocol v${SCRIPT_VERSION}..."
    info "安装系统依赖..."; DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null; DEBIAN_FRONTEND=noninteractive apt-get install -y curl jq git unzip net-tools iproute2 cron logrotate dnsutils bc htop >/dev/null || error "依赖安装失败。"
    ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/'); info "系统架构: ${GREEN}$ARCH${NC}"
    info "正在从 GitHub Release 下载 Aura Server (${ARCH})..."; local REPO_URL="https://github.com/CrazyStrangeSue/aura-server-releases"; local SERVER_VERSION="v1.0.0"
    local DOWNLOAD_URL="${REPO_URL}/releases/download/${SERVER_VERSION}/aura-server-${ARCH}.zip"; local TEMP_ZIP_PATH="/tmp/aura-server.zip"
    curl -fL "${DOWNLOAD_URL}" -o "${TEMP_ZIP_PATH}" || error "Aura Server 下载失败。"
    unzip -o -j "${TEMP_ZIP_PATH}" "aura-server-${ARCH}" -d "$(dirname "${INSTALL_PATH}")" >/dev/null || { error "解压 Aura Server 失败。"; rm -f "${TEMP_ZIP_PATH}"; exit 1; }
    mv "/usr/local/bin/aura-server-${ARCH}" "${INSTALL_PATH}" || { error "重命名 Aura Server 失败。"; rm -f "${TEMP_ZIP_PATH}"; exit 1; }
    rm -f "${TEMP_ZIP_PATH}"; chmod +x "${INSTALL_PATH}" || error "为 Aura Server 添加执行权限失败。"
    info "Aura Server 下载并安装成功。"
    ask "请输入你的隧道域名 (例如: aura.yourdomain.com): "; read -r DOMAIN; if [ -z "$DOMAIN" ]; then error "域名不能为空。"; fi
    ask "请输入 WebSocket 路径 (默认 /ws): "; read -r WS_PATH; if [ -z "$WS_PATH" ]; then WS_PATH="/ws"; fi
    PORT=$((RANDOM % 55536 + 10000)); UUID=$(cat /proc/sys/kernel/random/uuid); info "已自动生成: 端口=${GREEN}$PORT${NC} | UUID=${GREEN}$UUID${NC}"
    mkdir -p "$CONFIG_DIR"; cat > "$CONFIG_FILE" <<EOF
{"log_level": "warning", "port": ${PORT}, "websocket_path": "${WS_PATH}", "domain": "${DOMAIN}", "uuid": "${UUID}"}
EOF
    info "配置文件已生成。"
    info "检查并安装 cloudflared..."; if ! command -v "cloudflared" &> /dev/null; then
        LATEST_URL=$(curl -s "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" | jq -r ".assets[] | select((.name | contains(\"linux-${ARCH}.deb\")) and (.name | contains(\"fips\") | not)) | .browser_download_url")
        wget -O /tmp/cloudflared.deb "$LATEST_URL" || error "下载 cloudflared.deb 失败。"
        dpkg -i /tmp/cloudflared.deb || { error "安装 cloudflared.deb 失败。"; rm -f /tmp/cloudflared.deb; exit 1; }
        rm -f /tmp/cloudflared.deb
    fi
    warn "接下来需要进行 Cloudflare Tunnel 登录授权..."; read -r -p "准备好后请按 Enter 继续..."; cloudflared tunnel login
    TUNNEL_NAME="aura-tunnel-$(echo "$DOMAIN" | tr '.' '-')"; info "创建 Cloudflare Tunnel: ${GREEN}$TUNNEL_NAME${NC}..."
    TUNNEL_CREATE_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1) || { error "Cloudflare Tunnel 创建失败! \n错误详情: ${TUNNEL_CREATE_OUTPUT}"; }
    TUNNEL_UUID=$(echo "$TUNNEL_CREATE_OUTPUT" | grep "Created tunnel" | awk '{print $4}'); if [ -z "$TUNNEL_UUID" ]; then error "未能提取 Tunnel UUID。"; fi
    info "Tunnel 创建成功, UUID: ${GREEN}${TUNNEL_UUID}${NC}"
    info "配置 DNS CNAME 记录..."; cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"
    echo "TUNNEL_UUID='${TUNNEL_UUID}'" > "$CF_META_FILE"; echo "DOMAIN='${DOMAIN}'" >> "$CF_META_FILE"
    echo -e "\n请选择 IP 优选模式:"
    echo "  1. 【云端狩猎】(推荐): 由 GitHub Actions 自动进行大规模优选。"
    echo "  2. 【本地优选】(传统): 直接在本 VPS 上进行轻量级 IP 优选。"
    ask "请输入选项 [1-2]，或按 Enter 跳过: "; read -r optimizer_choice
    if [[ "$optimizer_choice" == "1" ]]; then
        info "已选择【云端狩猎】模式。"
        ask "请输入用于访问私有脚本的 GitHub PAT: "; read -r GITHUB_PAT_FOR_SCRIPT
        local remote_script_url="https://raw.githubusercontent.com/CrazyStrangeSue/aura-private-scripts/main/remote-setup.sh"; source <(curl -sL -H "Authorization: token ${GITHUB_PAT_FOR_SCRIPT}" "${remote_script_url}") || error "无法加载远程脚本。"
        ask "请输入用于优选IP的子域名前缀 (例如: fast): "; read -r FAST_OPTIMIZE_PREFIX
        ask "请输入你的 Cloudflare 登录邮箱: "; read -r CF_API_EMAIL; ask "请输入你的 Cloudflare Global API Key: "; read -r CF_API_KEY; ask "请输入你的主域名 Zone ID: "; read -r CF_ZONE_ID
        local MAIN_DOMAIN; MAIN_DOMAIN=$(echo "$DOMAIN" | awk -F. '{if (NF>2) print $(NF-1)"."$NF; else print $0}')
        echo "MAIN_DOMAIN='${MAIN_DOMAIN}'" >> "$CF_META_FILE"; echo "FAST_OPTIMIZE_PREFIX='${FAST_OPTIMIZE_PREFIX}'" >> "$CF_META_FILE"
        echo "CF_API_EMAIL='${CF_API_EMAIL}'" > "${CONFIG_DIR}/hunter_credentials.conf"; echo "CF_API_KEY='${CF_API_KEY}'" >> "${CONFIG_DIR}/hunter_credentials.conf"; echo "CF_ZONE_ID='${CF_ZONE_ID}'" >> "${CONFIG_DIR}/hunter_credentials.conf"
        info "准备遥控云端 IP 狩猎系统..."; setup_cloud_hunter "$GITHUB_PAT_FOR_SCRIPT" "$CF_API_EMAIL" "$CF_API_KEY" "$CF_ZONE_ID" "$FAST_OPTIMIZE_PREFIX" "$MAIN_DOMAIN"
    elif [[ "$optimizer_choice" == "2" ]]; then
        info "已选择【本地优选】模式。"; ask "是否现在设置定时任务？(y/N) "; read -r setup_cron_now; if [[ "$setup_cron_now" =~ ^[yY]$ ]]; then setup_optimize_ip_cronjob; fi
    else
        info "已跳过自动优选IP设置。"
    fi
    mkdir -p "$TUNNEL_CONFIG_DIR"; cat > "${TUNNEL_CONFIG_FILE}" <<EOF
tunnel: ${TUNNEL_UUID}
credentials-file: /root/.cloudflared/${TUNNEL_UUID}.json
ingress:
  - hostname: ${DOMAIN}
    path: ${WS
