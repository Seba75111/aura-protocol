#!/bin/bash

# ========================================================================================
# Aura Protocol - v12.4 (Phoenix Edition)
# 采用混合模式架构：公开安装脚本，私有核心逻辑，公开二进制分发
# ========================================================================================

# --- 脚本信息与颜色定义 ---
SCRIPT_VERSION="12.4 (Phoenix Edition)"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# --- 目录与变量定义 ---
CONFIG_DIR="/etc/aura-protocol"
AURA_OPERATIONS_DIR="/opt/aura-protocol"
OPTIMIZE_DIR="${AURA_OPERATIONS_DIR}/optimizer"
CONFIG_FILE="${CONFIG_DIR}/config.json"
CF_META_FILE="${CONFIG_DIR}/cf_meta.conf"
INSTALL_PATH="/usr/local/bin/aura-server"
SERVICE_FILE="/etc/systemd/system/aura-server.service"
TUNNEL_CONFIG_DIR="/etc/cloudflared"
TUNNEL_CONFIG_FILE="${TUNNEL_CONFIG_DIR}/config.yml"
OPTIMIZER_LOG_FILE="${OPTIMIZE_DIR}/optimizer.log"
LOGROTATE_CONFIG_FILE="/etc/logrotate.d/aura-protocol"

# --- 通用函数 ---
info() { echo -e "${GREEN}[信息]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }
ask() { echo -e -n "${CYAN}[询问]${NC} $1"; }
check_root() { if [[ $EUID -ne 0 ]]; then error "本脚本需要以 root 用户或 sudo 权限运行。"; exit 1; fi }

# --- 主功能实现 ---
function install_aura() {
    info "开始安装 Aura Protocol v${SCRIPT_VERSION}..."
    info "安装系统依赖 (curl, jq, git, unzip, net-tools, iproute2, cron, logrotate, dnsutils, bc)..."
    DEBIAN_FRONTEND=noninteractive; apt-get update >/dev/null
    apt-get install -y curl jq git unzip net-tools iproute2 cron logrotate dnsutils bc >/dev/null
    if [ $? -ne 0 ]; then error "依赖安装失败。"; exit 1; fi

    ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
    if [[ ! "$ARCH" =~ ^(amd64|arm64)$ ]]; then error "不支持的系统架构: $ARCH。"; exit 1; fi
    info "系统架构: ${GREEN}$ARCH${NC}"

    info "正在从 GitHub Release 下载 Aura Server (${ARCH})..."
    local REPO_URL="https://github.com/CrazyStrangeSue/aura-server-releases" # <-- 指向全新的公有仓库
    local SERVER_VERSION="v1.0.0"
    local DOWNLOAD_URL="${REPO_URL}/releases/download/${SERVER_VERSION}/aura-server-${ARCH}.zip"

    local TEMP_ZIP_PATH="/tmp/aura-server.zip"
    if ! curl -fL "${DOWNLOAD_URL}" -o "${TEMP_ZIP_PATH}"; then
        error "Aura Server (${ARCH}) 压缩包下载失败。请检查网络或确保 '${REPO_URL}' 仓库的 Release 中存在对应的附件。"
        exit 1
    fi

    # 【已修复的代码块】
    local TEMP_EXTRACT_PATH="/usr/local/bin/aura-server-${ARCH}"

    unzip -o -j "${TEMP_ZIP_PATH}" "aura-server-${ARCH}" -d "$(dirname ${INSTALL_PATH})" >/dev/null || { error "解压 Aura Server 失败。"; rm -f "${TEMP_ZIP_PATH}"; exit 1; }

    # 关键修复：将解压后的文件重命名为标准路径
    mv "${TEMP_EXTRACT_PATH}" "${INSTALL_PATH}" || { error "重命名 Aura Server 失败。"; rm -f "${TEMP_ZIP_PATH}" "${TEMP_EXTRACT_PATH}"; exit 1; }

    rm -f "${TEMP_ZIP_PATH}"
    chmod +x "${INSTALL_PATH}" || { error "为 Aura Server 添加执行权限失败。"; exit 1; }

    info "Aura Server 下载、解压并安装成功。"

    ask "请输入你的隧道域名 (例如: aura.yourdomain.com): "; read -r DOMAIN
    if [ -z "$DOMAIN" ]; then error "域名不能为空。"; exit 1; fi
    ask "请输入 WebSocket 路径 (以 / 开头, 例如: /ws): "; read -r WS_PATH
    if [ -z "$WS_PATH" ]; then error "路径不能为空。"; exit 1; fi
    if [[ ! "$WS_PATH" =~ ^/ ]]; then WS_PATH="/${WS_PATH}"; fi

    PORT=$((RANDOM % 55536 + 10000)); UUID=$(cat /proc/sys/kernel/random/uuid)
    info "已自动生成随机端口: ${GREEN}$PORT${NC} | UUID: ${GREEN}$UUID${NC}"

    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
{
  "log_level": "warning",
  "port": ${PORT},
  "websocket_path": "${WS_PATH}",
  "domain": "${DOMAIN}",
  "uuid": "${UUID}"
}
EOF
    info "Aura Protocol 配置文件已生成: ${GREEN}$CONFIG_FILE${NC}"

    info "检查并安装 Cloudflare Tunnel 客户端 (cloudflared)..."
    if ! command -v "cloudflared" &> /dev/null; then
        LATEST_URL=$(curl -s "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" | jq -r ".assets[] | select((.name | contains(\"linux-${ARCH}.deb\")) and (.name | contains(\"fips\") | not)) | .browser_download_url")
        # 【调试模式的代码块】
        echo -e "${YELLOW}[调试]${NC} 获取到的 Cloudflared 下载地址: ${LATEST_URL}"
        if [ -z "$LATEST_URL" ]; then
            error "无法从 GitHub API 获取 Cloudflared 下载地址，请检查网络。"
            exit 1
        fi

        echo -e "${GREEN}[信息]${NC} 正在下载 Cloudflared..."
        wget -O cloudflared.deb "$LATEST_URL" || { error "使用 wget 下载 cloudflared.deb 失败。"; exit 1; }

        echo -e "${GREEN}[信息]${NC} 正在使用 dpkg 安装 Cloudflared..."
        sudo dpkg -i cloudflared.deb || { error "使用 dpkg 安装 cloudflared.deb 失败。"; rm -f cloudflared.deb; exit 1; }

        rm -f cloudflared.deb
        if ! command -v "cloudflared" &> /dev/null; then error "cloudflared 安装失败。"; exit 1; fi
    fi

    warn "接下来需要进行 Cloudflare Tunnel 登录授权..."
    read -r -p "准备好后请按 Enter 继续..."
    cloudflared tunnel login

    TUNNEL_NAME="aura-tunnel-$(echo "$DOMAIN" | tr '.' '-')"
    info "创建 Cloudflare Tunnel: ${GREEN}$TUNNEL_NAME${NC}..."
    TUNNEL_UUID=$(cloudflared tunnel create "$TUNNEL_NAME" | grep "Created tunnel" | awk '{print $4}')
    if [[ -z "$TUNNEL_UUID" ]]; then error "无法获取新创建的 Tunnel UUID。"; exit 1; fi

    info "配置 DNS CNAME 记录，将 ${DOMAIN} 指向 Tunnel..."
    cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"

    mkdir -p "$CONFIG_DIR"
    echo "TUNNEL_UUID='${TUNNEL_UUID}'" > "$CF_META_FILE"
    echo "DOMAIN='${DOMAIN}'" >> "$CF_META_FILE"

    ask "是否启用云端自动优选 IP 功能？(Y/n): "; read -r enable_cloud_optimizer
    if [[ ! "$enable_cloud_optimizer" =~ ^[nN]$ ]]; then
        info "正在从 GitHub 私有仓库获取最新的远程配置脚本..."
        ask "请输入用于访问私有脚本的 GitHub PAT: "; read -r GITHUB_PAT_FOR_SCRIPT
        
        # ====================【核心修改点】====================
        # 从新的、私有的 aura-private-scripts 仓库拉取核心逻辑
        local remote_script_url="https://raw.githubusercontent.com/CrazyStrangeSue/aura-private-scripts/main/remote-setup.sh"
        source <(curl -sL -H "Authorization: token ${GITHUB_PAT_FOR_SCRIPT}" "${remote_script_url}")
        # ======================================================

        if ! command -v setup_cloud_hunter &> /dev/null; then
            error "无法从私有仓库加载远程配置脚本。请检查您的 PAT 权限是否包含 'repo'，并确保网络通畅。"
            exit 1
        fi

        ask "请输入用于优选IP的子域名前缀 (例如: fast): "; read -r FAST_OPTIMIZE_PREFIX
        ask "请输入你的 Cloudflare 登录邮箱: "; read -r CF_API_EMAIL
        ask "请输入你的 Cloudflare Global API Key: "; read -r CF_API_KEY
        ask "请输入你的主域名 Zone ID: "; read -r CF_ZONE_ID
        MAIN_DOMAIN=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')

        info "准备遥控云端 IP 狩猎系统 (Aura-IP-Hunter)..."
        setup_cloud_hunter "$GITHUB_PAT_FOR_SCRIPT" "$CF_API_EMAIL" "$CF_API_KEY" "$CF_ZONE_ID" "$FAST_OPTIMIZE_PREFIX" "$MAIN_DOMAIN"

        echo "FAST_OPTIMIZE_PREFIX='${FAST_OPTIMIZE_PREFIX}'" >> "$CF_META_FILE"
        setup_optimize_ip_cronjob
    fi

    mkdir -p "$TUNNEL_CONFIG_DIR"
    cat > "${TUNNEL_CONFIG_FILE}" <<EOF
tunnel: ${TUNNEL_UUID}
credentials-file: /root/.cloudflared/${TUNNEL_UUID}.json
ingress:
  - hostname: ${DOMAIN}
    path: ${WS_PATH}
    service: ws://127.0.0.1:${PORT}
  - service: http_status:404
EOF

    cloudflared service install > /dev/null 2>&1
    systemctl enable --now cloudflared &> /dev/null

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
    systemctl daemon-reload
    systemctl enable --now aura-server

    info "安装成功！"
    show_node_info
}

function show_node_info() {
    if [ ! -f "$CONFIG_FILE" ]; then error "配置文件丢失。"; return; fi
    source "$CF_META_FILE" 2>/dev/null || true
    DOMAIN=$(jq -r .domain "$CONFIG_FILE"); WS_PATH=$(jq -r .websocket_path "$CONFIG_FILE"); UUID=$(jq -r .uuid "$CONFIG_FILE")
    WS_PATH_ENCODED=$(echo "$WS_PATH" | sed 's/\//%2F/g')
    SHARE_LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=${WS_PATH_ENCODED}#Aura-${DOMAIN}"

    echo -e "\n==================== Aura Protocol 节点信息 ===================="
    echo -e "地址 (Address):      ${YELLOW}${DOMAIN}${NC}"
    echo -e "端口 (Port):         ${YELLOW}443${NC}"
    echo -e "用户ID (UUID):      ${YELLOW}${UUID}${NC}"
    echo -e "路径 (Path):         ${YELLOW}${WS_PATH}${NC}"
    echo -e "--------------------------------------------------------------"
    echo -e "${GREEN}VLESS 分享链接:${NC}\n${YELLOW}${SHARE_LINK}${NC}"
    echo -e "================================================================"

    if [[ -n "$FAST_OPTIMIZE_PREFIX" && "$FAST_OPTIMIZE_PREFIX" != "null" ]]; then
        MAIN_DOMAIN=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')
        echo -e "\n===========【推荐】云端优选 IP (舰队模式) 使用提示 ==========="
        echo -e "以下 ${GREEN}5${NC} 个域名将由云端自动更新为最优 IP，请在客户端中手动测试"
        echo -e "哪个延迟最低，就使用哪个作为你的客户端地址 (Address)。"
        for ((i=1; i<=5; i++)); do
            echo -e "  -> ${YELLOW}${FAST_OPTIMIZE_PREFIX}${i}.${MAIN_DOMAIN}${NC}"
        done
        echo -e "保持伪装域名 (Host) 和 SNI 仍为: ${YELLOW}${DOMAIN}${NC}"
        echo -e "你也可以运行脚本菜单中的“执行 IP 优选”来自动找出本地延迟最低的 IP。"
        echo -e "================================================================"
    fi
}

function _sync_ip_from_cloud() {
    mkdir -p "$OPTIMIZE_DIR"
    if [ ! -f "$CF_META_FILE" ]; then error "元数据文件丢失。"; return 1; fi
    source "$CF_META_FILE" 2>/dev/null || true

    if [[ -z "$FAST_OPTIMIZE_PREFIX" || "$FAST_OPTIMIZE_PREFIX" == "null" ]]; then
        warn "优选IP前缀未设置，跳过。"
        return 0
    fi

    info "正在执行本地终端制导优选 IP..."

    local PING_CMD="ping"
    if ping -6 -c 1 -W 1 google.com &>/dev/null; then
        info "检测到 IPv6 网络环境。"
        PING_CMD="ping -6"
    else
        info "使用 IPv4 网络环境。"
    fi

    local FLEET_MEMBERS=5
    local CANDIDATE_IPS=()

    info "正在从云端舰队获取 IP 地址..."
    MAIN_DOMAIN=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')
    for ((i=1; i<=$FLEET_MEMBERS; i++)); do
        local target_domain="${FAST_OPTIMIZE_PREFIX}${i}.${MAIN_DOMAIN}"
        local ip=$(dig +short "$target_domain" | head -n 1)
        if [ -n "$ip" ]; then
            info "  -> 侦测到 ${target_domain}: ${ip}"
            CANDIDATE_IPS+=("$ip")
        fi
    done

    if [ ${#CANDIDATE_IPS[@]} -eq 0 ]; then warn "未能从云端舰队获取任何有效 IP。"; return 1; fi

    info "正在对 ${#CANDIDATE_IPS[@]} 个候选 IP 进行本地延迟测试..."
    local BEST_IP=""
    local MIN_LATENCY=99999

    for ip in "${CANDIDATE_IPS[@]}"; do
        local latency=$($PING_CMD -c 3 -W 1 "$ip" | tail -n 1 | awk -F'/' '{print $5}')
        if [[ "$latency" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            info "  -> IP: ${ip}, 平均延迟: ${latency} ms"
            if (( $(echo "$latency < $MIN_LATENCY" | bc -l) )); then
                MIN_LATENCY=$latency
                BEST_IP="$ip"
            fi
        fi
    done

    if [ -z "$BEST_IP" ]; then error "未能找到可用的最优 IP。"; return 1; fi

    echo -e "\n==================== 本地优选 IP 结果 ===================="
    echo -e "在你的客户端中，我们推荐使用以下 IP 作为地址 (Address):"
    echo -e "  -> ${GREEN}${BEST_IP}${NC} (当前本地延迟: ${MIN_LATENCY} ms)"
    echo -e "请记得保持伪装域名 (Host) 和 SNI 仍为: ${YELLOW}${DOMAIN}${NC}"
    echo -e "=========================================================="
}

function optimize_ip() {
    _sync_ip_from_cloud
}

function optimize_ip_cron() {
    (
      echo "$(date '+%Y-%m-%d %H:%M:%S'): 开始执行本地终端制导..."
      if [ -f "$CF_META_FILE" ]; then
        source "$CF_META_FILE" 2>/dev/null || true
        _sync_ip_from_cloud
      fi
    ) >> "${OPTIMIZER_LOG_FILE}" 2>&1
}

function setup_logrotate() {
    info "配置日志管理策略 (日志轮转)..."
    mkdir -p "$(dirname "$OPTIMIZER_LOG_FILE")"
    touch "$OPTIMIZER_LOG_FILE"
    cat > "$LOGROTATE_CONFIG_FILE" <<EOF
${OPTIMIZER_LOG_FILE} {
    daily
    rotate 7
    size 10M
    compress
    delaycompress
    missingok
    notifempty
}
EOF
    info "日志轮转策略已配置: ${GREEN}${LOGROTATE_CONFIG_FILE}${NC}"
}

function setup_optimize_ip_cronjob() {
    info "正在为您设置默认的本地优选IP定时任务 (每天凌晨4点)..."
    mkdir -p "${AURA_OPERATIONS_DIR}"
    cp "$0" "${AURA_OPERATIONS_DIR}/run.sh"
    local cron_command="0 4 * * * bash ${AURA_OPERATIONS_DIR}/run.sh optimize_ip_cron"
    (crontab -l 2>/dev/null | grep -v "optimize_ip_cron"; echo "$cron_command") | crontab -
    setup_logrotate
    info "定时任务已设置。"
}

function uninstall_aura() {
    warn "你确定要彻底卸载 Aura Protocol 吗？"
    read -r -p "这将删除所有相关服务和文件。 (输入 'yes' 确认): " confirm
    if [[ "$confirm" != "yes" ]]; then info "操作已取消。"; exit 0; fi

    info "开始卸载..."
    systemctl stop aura-server cloudflared &>/dev/null
    systemctl disable aura-server cloudflared &>/dev/null

    if [ -f "$CF_META_FILE" ]; then
        source "$CF_META_FILE"
        if [[ -n "$TUNNEL_UUID" ]]; then
            info "删除 Cloudflare Tunnel..."
            cloudflared tunnel delete "$TUNNEL_UUID"
        fi
    fi

    info "删除所有本地文件和目录..."
    rm -f "$INSTALL_PATH" "$SERVICE_FILE" /etc/systemd/system/cloudflared.service "$LOGROTATE_CONFIG_FILE"
    rm -rf "$CONFIG_DIR" "$AURA_OPERATIONS_DIR" "$TUNNEL_CONFIG_DIR" "/root/.cloudflared"

    crontab -l 2>/dev/null | grep -v "optimize_ip_cron" | crontab -

    systemctl daemon-reload
    info "Aura Protocol 已被彻底移除。"
}

function main_menu() {
    while true; do
        echo ""
        echo "==================== Aura Protocol 管理菜单 ===================="
        echo "1. 查看节点信息"
        echo "2. 执行 IP 优选 (终端制导)"
        echo "3. 卸载 Aura Protocol"
        echo "4. 退出脚本"
        echo "--------------------------------------------------------------"
        ask "请输入选项 [1-4]: "
        read -r menu_choice
        case $menu_choice in
            1) show_node_info ;;
            2) optimize_ip ;;
            3) uninstall_aura; exit 0 ;;
            4) exit 0 ;;
            *) error "无效选项。" ;;
        esac
        read -r -p "按任意键返回主菜单..."
    done
}

main() {
    check_root
    if [[ "$1" == "optimize_ip_cron" ]]; then
        if [ -f "$CF_META_FILE" ]; then
            optimize_ip_cron
        fi
        exit 0
    fi

    if [ -f "$CONFIG_FILE" ]; then
        main_menu
    else
        install_aura
    fi
}

main "$@"
