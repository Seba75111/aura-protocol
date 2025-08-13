# 🚀 Aura Protocol: 安全、高速、傻瓜式代理上网解决方案

![Aura Protocol Banner](https://github.com/CrazyStrangeSue/Aura-IP-Hunter/blob/main/images/aura-logo.png?raw=true)

## ✨ 项目简介

Aura Protocol 是一个致力于提供**安全、高速、自动化、傻瓜式**代理上网体验的开源项目。聚合 Cloudflare Tunnel、优选IP、云端自动化等功能，在帮助用户轻松搭建和管理自己的代理服务，有效对抗网络审查，同时确保极致的隐私和隐匿性。

---

## 💡 核心亮点与优势

*   **🛡️ 极致安全与隐匿：**
    *   **流量混入 Cloudflare HTTPS：** 您的所有代理流量将伪装成正常的 HTTPS 流量通过 Cloudflare 的全球 CDN 传输，不暴露真实服务器 IP，不易被识别和封锁。
    *   **零端口暴露：** 服务器端无需开放任何端口，Cloudflare Tunnel 自动建立安全通道，提升安全性，降低被扫描和攻击的风险。
    *   **混淆加密：** 程序将进行代码混淆，极大增加逆向分析和破解的难度。

*   **⚡ 高速稳定与低延迟：**
    *   **Cloudflare CDN 加速：** 利用 Cloudflare 全球边缘节点优势，降低您的网络延迟。
    *   **自动化优选 IP：** 脚本自动寻找当前网络环境下表现最佳的 Cloudflare IP，并通过专用域名智能更新，确保您始终连接到最快的节点。

*   **🤖 自动化与傻瓜式管理：**
    *   **一键部署：** 提供简易的 Shell 脚本，自动化所有复杂的安装、配置和启动步骤。
    *   **菜单式管理：** 脚本提供交互式菜单，方便您查看节点信息、手动优选 IP、设置定时任务和进行彻底卸载。
    *   **跨平台兼容：** 核心程序支持主流服务器架构，自动适配。

*   **📊 实时系统监控：**
    *   集成实时系统监控工具，让您无需额外部署复杂面板，即可通过 SSH 简单查看服务器的 CPU、内存、网络和进程状态，确保项目健康运行，打消挖矿、僵尸网络等疑虑。

---

## 🔒 如何确保项目安全与信任？ (用户必读)

我们深知您对项目安全和隐私的担忧。Aura Protocol 的设计理念是**透明与安全并重**：

1.  **`install.sh` 脚本完全开源且可读：** 
    我们安装脚本的所有代码都是公开的，您可以（也鼓励您）在运行前**逐行审查**。我们承诺脚本不会进行任何挖矿、植入后门、加入僵尸网络或损害您服务器的恶意行为。它的每一个操作都是透明可见的。
    **您可以通过阅读脚本代码来验证我们的承诺。**

2.  **核心程序 `aura-server` 经过混淆加固：**
    `aura-server` 是用 Go 语言开发的代理核心，其源代码不公开是为了**防止审查机构进行逆向分析**，从而保护项目的长期可用性。您下载和运行的是我们提供经过 `Garble` 工具混淆的二进制文件，它极大增加了逆向分析的难度。

3.  **实时系统监控 (`htop`) 方便验证：**
    安装完成后，您可以随时通过 SSH 登录您的 VPS，运行 `htop` 命令来实时查看服务器的 CPU、内存、网络和进程列表。您可以清晰地看到资源占用情况，并确保没有其他异常或高资源占用的进程在运行。这为您提供了持续验证项目健康度的能力。

---

## 🚀 快速开始 (一键部署)

安装前准备：
1.  一个**域名** (例如 `免费的 dpdns.org`)。
2.  将该域名**托管到 Cloudflare**，并确保 DNS 解析模式为**橙色小云朵 (Proxied)**。
3.  购买了一台 **VPS (Linux 服务器)**，并获得了 SSH 登录权限。

### 1. 准备工作 (在 Cloudflare 面板)

安装之前，请前往 Cloudflare 和GitHub面板完成以下设置，以确保最佳兼容性和性能：

*   **SSL/TLS 加密模式：**
    前往 **SSL/TLS** -> **概述 (Overview)**，确保加密模式设置为 **`完全 (Full)`**。
*   **API Token （Cloudflare）：**
    前往 **My Profile** (右上角头像) -> **API Tokens**。点击 **`Create Token`**。
    查看 Global API Key
*   **API Token （GitHub）：**
    前往 GitHub Tokens 设置页面:
       访问 https://github.com/settings/tokens
    生成一个全新的、权限完美的令牌:
       点击 "Generate new token" -> "Generate new token (classic)"
       Note (备注): 给它起个清晰的名字，比如 Aura-Protocol
       Expiration (有效期): 为了方便，可以选择 "No expiration"
       Select scopes (选择权限): 【至关重要】 请务必、务必勾选以下三个复选框：
          ✅ repo (完全控制仓库，包括私有仓库)
          ✅ workflow (修改和运行 Actions 工作流)
          ✅ admin:org -> read:org (读取组织信息，这是解决我们认证失败的关键)
    生成并复制令牌:
       点击页面最下方的 "Generate token"。
       GitHub 只会显示这一次新令牌，请立刻将它复制下来，存放在一个安全的地方。
    

### 2. 下载并运行安装脚本 (在 VPS 上)

**建议在干净的 Ubuntu/Debian 系统上运行。**

# SSH 连接到您的 VPS

```bash
# 下载安装脚本
bash <(curl -sL https://raw.githubusercontent.com/CrazyStrangeSue/aura-protocol/main/install.sh)
```
---

# 接下来你会看到的提示：

**1.脚本应该正停在 [询问] 请输入你的隧道域名 (例如: aura.yourdomain.com ): 这个地方等待您的输入**
   输入隧道域名：例如 tunnel.aura.com (假设您的主域名是 aura.com )
   请在终端中准确输入这个域名，然后按 Enter
   
**2.要求输入 WebSocket 路径**
   可以直接按 Enter 使用默认的 /ws ，或者输入您喜欢的路径（例如 /my-aura-path）

**3.自动生成端口和 UUID**

**4.授权域名**
   提示进行 tunnel login
   复制终端中显示的 URL ，同时确保已经登录 Cloudflare ，并在浏览器中粘贴这个 URL 回车，授权后终端自动运行

**5.询问是否启用云端优选功能，请输入 Y（如果需要每天自动更新优选 IP ）**

**关键步骤：它会依次向您索要：**

   - GitHub PAT

   - 优选IP的子域名前缀 (例如： aura)

   - Cloudflare 登录邮箱

   - Cloudflare Global API Key

   -  Zone ID

脚本产生的文件和对应位置：
/etc/aura-protocol 
/opt/aura-protocol 
/usr/local/bin/aura-server 
/root/.cloudflared

请依次准确输入以上信息，如果你的 VPS 和域名是永久免费的，这样你就拥有一个永久、低延迟、全自动化、安全性较高的 Aura 协议
