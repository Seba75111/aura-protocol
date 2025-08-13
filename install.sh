sudo bash <<'EOF'
# =================================================================
# Aura Protocol - 终极净化脚本
# 目标：无视一切现有状态，将系统恢复到绝对干净
# =================================================================

# 颜色定义
GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
echo -e "${GREEN}[信息]${NC} 启动终极净化程序..."

# 使用 set +e 确保即使某一步失败，脚本也会继续执行，以求最大程度的清理
set +e

# 停止并禁用所有可能的服务
echo -e "${GREEN}[信息]${NC} 正在停止并禁用 aurs-server 和 cloudflared 服务..."
systemctl stop aura-server cloudflared &>/dev/null
systemctl disable aura-server cloudflared &>/dev/null

# 手动杀死所有残留进程
echo -e "${GREEN}[信息]${NC} 正在强制杀死所有相关进程..."
pkill -f "aura-server" &>/dev/null
pkill -f "cloudflared" &>/dev/null

# 删除所有核心文件和目录
echo -e "${GREEN}[信息]${NC} 正在删除所有 Aura Protocol 的核心文件和目录..."
rm -f /usr/local/bin/aura-server
rm -f /etc/systemd/system/aura-server.service
rm -f /etc/systemd/system/cloudflared.service
rm -f /etc/logrotate.d/aura-protocol
rm -rf /etc/aura-protocol
rm -rf /opt/aura-protocol
rm -rf /etc/cloudflared
rm -rf /root/.cloudflared

# 清理 cron 任务
echo -e "${GREEN}[信息]${NC} 正在清理 cron 定时任务..."
(crontab -l 2>/dev/null | grep -v "optimize_ip_cron") | crontab -

# 清理安装时下载的临时文件
echo -e "${GREEN}[信息]${NC} 正在清理安装时下载的临时文件..."
rm -f /root/install.sh /tmp/cloudflared.deb /tmp/aura-server.zip /tmp/gh.deb

# 卸载所有相关依赖
echo -e "${GREEN}[信息]${NC} 正在卸载为 Aura Protocol 安装的依赖 (gh, cloudflared)..."
DEBIAN_FRONTEND=noninteractive apt-get purge -y gh cloudflared >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null

# 重新加载 systemd
systemctl daemon-reload

echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN} Aura Protocol 终极净化程序执行完毕。${NC}"
echo -e "${GREEN} 您的系统现已恢复到绝对干净的状态。${NC}"
echo -e "${YELLOW} 请注意：本程序不会删除 Cloudflare 上的 Tunnel 或 DNS 记录，请根据需要手动清理。${NC}"
echo -e "${GREEN}=====================================================${NC}"
EOF
