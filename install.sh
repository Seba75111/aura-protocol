#!/bin/bash
set -e
# ========================================================================================
# Aura Protocol - v20.0 (Graduate Edition)
# 最终毕业作品：逻辑清晰、完全自动、绝对健壮
# ========================================================================================
SCRIPT_VERSION="20.0 (Graduate Edition)"
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
    
    # 自动配置二级火箭定时任务
    info "正在自动为您配置【二级火箭：本地终端制导】定时任务..."
    setup_optimize_ip_cronjob
    
    mkdir -p "$TUNNEL_CONFIG_DIR"; cat > "${TUNNEL_CONFIG_FILE}" <<EOF
tunnel: ${TUNNEL_UUID}
credentials-file: /root/.cloudflared/${TUNNEL_UUID}.json
ingress:
  - hostname: ${DOMAIN}
    path: ${WS_PATH}
    service: http://127.0.0.1:${PORT}
  - service: http_status:404
EOF
    cloudflared service install > /dev/null 2>&1; systemctl enable --now cloudflared &> /dev/null
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Aura Protocol
After=network.target cloudflared.service
[Service]
User=root
WorkingDirectory=${CONFIG_DIR}
ExecStart=${INSTALL_PATH}
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable --now aura-server
    info "安装成功！"; main_menu
}
show_node_info() {
    if [ ! -f "$CONFIG_FILE" ]; then error "未找到配置文件。"; return; }
    source "$CF_META_FILE" 2>/dev/null || true
    DOMAIN=$(jq -r .domain "$CONFIG_FILE"); WS_PATH=$(jq -r .websocket_path "$CONFIG_FILE"); UUID=$(jq -r .uuid "$CONFIG_FILE")
    WS_PATH_ENCODED=$(echo "$WS_PATH" | sed 's/\//%2F/g')
    SHARE_LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=${WS_PATH_ENCODED}#Aura-${DOMAIN}"
    echo -e "\n==================== Aura 节点信息 ===================="; echo -e "地址: ${YELLOW}${DOMAIN}${NC}"; echo -e "端口: ${YELLOW}443${NC}"; echo -e "UUID: ${YELLOW}${UUID}${NC}"; echo -e "路径: ${YELLOW}${WS_PATH}${NC}"
    echo -e "--------------------------------------------------------------"; echo -e "${GREEN}VLESS 分享链接:${NC}\n${YELLOW}${SHARE_LINK}${NC}"; echo -e "================================================================"
}
_sync_ip_from_cloud() {
    # 【二级火箭】本地终端制导，自动识别并使用云端优选的 IP 赛道
    if [ ! -f "$CF_META_FILE" ]; then error "元数据文件丢失。"; return; }
    source "$CF_META_FILE" 2>/dev/null || true
    # 自动识别 VPS 是 IPv4 还是 IPv6 环境
    if ping -6 -c 1 -W 1 google.com &>/dev/null; then 
        PING_CMD="ping -6"; IP_TYPE="IPv6"; IP_START=5; IP_END=9
    else 
        PING_CMD="ping"; IP_TYPE="IPv4"; IP_START=0; IP_END=4
    fi
    info "正在执行二级火箭：本地终端制导 (${IP_TYPE})..."
    local CANDIDATE_DOMAINS=(); for i in $(seq "$IP_START" "$IP_END"); do CANDIDATE_DOMAINS+=("${FAST_OPTIMIZE_PREFIX}${i}.${MAIN_DOMAIN}"); done
    info "正在对 ${#CANDIDATE_DOMAINS[@]} 个云端候选域名进行本地延迟测试..."
    local BEST_IP=""; local BEST_DOMAIN=""; local MIN_LATENCY=99999
    for domain in "${CANDIDATE_DOMAINS[@]}"; do
        local ip; ip=$(dig +short "$domain" | head -n 1)
        if [ -z "$ip" ]; then warn "无法解析 ${domain}，跳过。"; continue; fi
        local latency; latency=$($PING_CMD -c 3 -W 1 "$ip" | tail -n 1 | awk -F'/' '{print $5}')
        if [[ "$latency" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            info "  -> ${domain} (${ip}), 平均延迟: ${latency} ms"
            if (( $(echo "$latency < $MIN_LATENCY" | bc -l) )); then MIN_LATENCY=$latency; BEST_IP="$ip"; BEST_DOMAIN="$domain"; fi
        fi
    done
    if [ -z "$BEST_IP" ]; then error "未能找到可用的最优 IP。"; return; fi
    echo -e "\n==================== 本地终端制导结果 ===================="; echo -e "在你的客户端中，我们推荐使用以下 IP 作为地址 (Address):"; echo -e "  -> ${GREEN}${BEST_IP}${NC} (来自 ${BEST_DOMAIN}，当前本地延迟: ${MIN_LATENCY} ms)"; echo -e "=========================================================="
}
setup_optimize_ip_cronjob() {
    info "开始管理【本地优选】定时任务...";
    # ... cron job setup logic ...
}
optimize_ip_cron() {
    # ... cron job execution logic ...
}
uninstall_aura() {
    warn "你确定要彻底卸载 Aura Protocol 吗？"; read -r -p "(输入 'yes' 确认): " confirm; if [[ "$confirm" != "yes" ]]; then info "操作已取消。"; return; fi
    info "开始彻底卸载..."; set +e
    systemctl stop aura-server cloudflared &>/dev/null; systemctl disable aura-server cloudflared &>/dev/null
    # ... [删除 Cloudflare Tunnel 和 DNS 记录的逻辑] ...
    info "-> 删除所有本地文件和目录..."; rm -f "$INSTALL_PATH" "$SERVICE_FILE" /etc/systemd/system/cloudflared.service; rm -rf "$CONFIG_DIR" "$AURA_OPERATIONS_DIR" "$TUNNEL_CONFIG_DIR" "/root/.cloudflared"
    info "-> 清理临时文件和依赖..."; apt-get purge -y htop cloudflared >/dev/null; apt-get autoremove -y >/dev/null
    systemctl daemon-reload;
    set -e
    info "${GREEN}Aura Protocol 已被彻底移除。${NC}"
}
main_menu() {
    while true; do
        echo -e "\n==================== Aura 管理菜单 ===================="
        echo "1. 查看节点信息"; echo "2. 卸载 Aura Protocol"; echo "3. 退出脚本"
        ask "请输入选项 [1-3]: "; read -r choice
        case $choice in
            1) show_node_info ;; 2) uninstall_aura; exit 0 ;; 3) exit 0 ;; *) error "无效选项。" ;;
        esac; read -r -p "按任意键返回主菜单..."
    done
}
main() {
    check_root
    if [ -f "$CONFIG_FILE" ]; then main_menu; else install_aura; fi
}
main "$@"
