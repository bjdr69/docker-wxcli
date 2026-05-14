# docker-wxcli

在 `nickrunning/wechat-selkies` Docker 容器内全链路部署 `wcdb-key-tool`（密钥提取）与 `wx-cli`（数据编排服务），实现毫秒级微信数据 CLI 交互。

## 架构

```
┌─ 宿主机 ──────────────────────────────────┐
│  docker-compose.yml                        │
│  ┌─ Container: wechat-selkies ───────────┐ │
│  │  port 3000 ─── noVNC/nginx Web桌面     │ │
│  │  cap_add SYS_PTRACE ── gdb 权限       │ │
│  │  shm_size 1gb ──── PBKDF2 OOM防护     │ │
│  │                                         │ │
│  │  /opt/wechat/wechat ← 微信 Linux 主进程 │ │
│  │  /opt/wechat/RadiumWMPF/ ← 子进程架构  │ │
│  │                                         │ │
│  │  /config/tools/                         │ │
│  │    ├── wcdb-key-tool/wcdb_key_tool.py   │ │
│  │    └── wx-cli              ← v0.1.10   │ │
│  │                                         │ │
│  │  /config/.wx-cli/          ← 持久化配置│ │
│  │    ├── config.json                      │ │
│  │    └── all_keys.json       ← AES 密钥   │ │
│  │                                         │ │
│  │  /config/xwechat_files/    ← 微信数据   │ │
│  │    └── wxid_xxx/db_storage/ ← 加密 DB   │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### 数据流

```
WeChat 登录 → 内存中生成 passphrase (32B)
                    ↓
    wcdb-key-tool (GDB 断点捕获 passphrase)
                    ↓
    PBKDF2-SHA512(256K 次迭代) → 每个 DB 的 enc_key
                    ↓
    all_keys.json → wx-cli → 解密 DB → CLI 查询
```

**关键发现：** 此容器中微信采用 **RadiumWMPF 架构**，`WCDB Config.Cipher` 锚点字符串在主 `wechat` 二进制中，但实际子进程 `WeChatAppEx` 处理数据库。`wcdb-key-tool` 的 ELF 静态分析能正确定位主进程中的 hook 函数地址。

## 快速开始

```bash
# 1. 启动容器
docker-compose up -d

# 2. 等待容器就绪后，注入依赖
#    注意：容器重启后 apt 安装的包会丢失，需要重新运行
docker exec -it wechat-selkies bash /config/setup_env.sh

# 3. 对齐配置路径
docker exec -it wechat-selkies bash /config/config_align.sh

# 4. 浏览器打开 http://localhost:3000，启动微信到二维码/登录界面
#
# 5. 提取密钥（详见下方时序说明）
docker exec -it wechat-selkies bash /config/extract_keys.sh

# 6. 冒烟测试
docker exec -it wechat-selkies /config/tools/wx-cli sessions
docker exec -it wechat-selkies /config/tools/wx-cli search "关键词" --json
```

## 端口

| 端口 | 用途 |
|------|------|
| 3000 | noVNC Web 桌面界面 (nginx HTTP) |
| 3001 | noVNC Web 桌面界面 (nginx HTTPS) |

## 目录结构

```
docker-wxcli/
├── docker-compose.yml       # SYS_PTRACE + 1GB shm
├── setup_env.sh             # gdb/python3/sqlcipher/wx-cli
├── config_align.sh          # 自动侦测 wxid → config.json
├── extract_keys.sh          # wcdb-key-tool 密钥提取
├── start_daemon.sh          # wx init + 冒烟测试
├── README.md
└── config/                  # 持久化卷（挂载至容器 /config）
    ├── tools/
    │   ├── wcdb-key-tool/   # git clone wcdb-key-tool 源码
    │   └── wx-cli           # jackwener/wx-cli v0.1.10 amd64
    ├── .wx-cli/
    │   ├── config.json      # wx-cli 配置（db_dir 等）
    │   └── all_keys.json    # AES 密钥，chmod 600
    ├── xwechat_files/       # 微信数据文件（容器内自动生成）
    └── config_align.sh      # 同步到宿主机
```

## 阶段详解

### Phase 1 — 基础设施

`docker-compose.yml`：

```yaml
services:
  wechat-selkies:
    image: nickrunning/wechat-selkies:latest
    cap_add:
      - SYS_PTRACE          # gdb ptrace 必须
    shm_size: "1gb"         # PBKDF2 防 OOM
    volumes:
      - ./config:/config    # 持久化
    ports:
      - "3000:3000"         # noVNC (nginx)
      - "3001:3001"         # noVNC (nginx HTTPS)
    restart: unless-stopped
```

> **注意：** 此容器使用 nginx 暴露 noVNC（3000-3001），非传统的 5800-5900。容器基于 s6 init 系统，每次重启会重置 `/opt/wechat` 外的 apt 安装包。

### Phase 2 — 依赖注入

在容器内安装工具链：

```bash
docker exec wechat-selkies bash /config/setup_env.sh
```

安装内容：
- **系统包：** `gdb`, `python3-pip`, `sqlcipher`
- **Python：** `sqlcipher3`, `pycryptodome`
- **wcdb-key-tool：** `github.com/bjdr69/wcdb-key-tool` 克隆到 `/config/tools/`
- **wx-cli：** `github.com/jackwener/wx-cli` v0.1.10 Linux x86_64 二进制

容器重启后 apt 包丢失，需要重跑此脚本（通过 `/config` 卷持久化的 wx-cli 和 wcdb-key-tool 保留）。

### Phase 3 — 配置对齐

```bash
docker exec wechat-selkies bash /config/config_align.sh
```

- 扫描 `/config/xwechat_files/` 下的 `wxid_xxx` 目录
- 生成 `~/.wx-cli/config.json`：
  ```json
  {
    "db_dir": "/config/xwechat_files/wxid_xxx/db_storage",
    "keys_file": "all_keys.json",
    "decrypted_dir": "cache",
    "wechat_process": "wechat"
  }
  ```
- 创建 `~/.wx-cli` → `/config/.wx-cli` 软链接（持久化）

### Phase 4 — 密钥提取（核心难点）

**原理：** `wcdb-key-tool` 通过 ELF 静态分析在 wechat 二进制中找到密钥写入函数地址，GDB 设置断点。当用户重新登录微信时，passphrase 写入函数被触发，GDB 从 CPU 寄存器（RSI/RDX）读取 32 字节 passphrase，再 PBKDF2-SHA512(256K 次迭代) 派生每个数据库的 enc_key。

```
wcdb_key_tool.py extract → GDB attach → 断点就绪
       ↓
用户退出登录 → 重新扫码 → 断点触发
       ↓
捕获 passphrase (32B hex)
       ↓
PBKDF2 派生 15 个 enc_key → all_keys.json
```

**时序要求（关键）：** 断点设置必须在登录流程之前。流程为：
1. 微信处于已登录状态
2. 运行 `extract_keys.sh`（GDB 设置断点并等待）
3. **期间**在 noVNC 中退出登录 → 重新扫码登录
4. 断点命中，捕获 passphrase，派生密钥

> **注意：** Docker Desktop for Windows 在 WSL2 中运行时，`docker exec` 可能无法直接使用。解决方法：
> ```
> # 用 Windows 端 docker.exe 
> /mnt/c/Program\ Files/Docker/Docker/resources/bin/docker.exe exec ...
> # 或创建指向 guest-services 的上下文
> docker context create wsl-desktop --docker "host=unix:///mnt/wsl/docker-desktop/shared-sockets/guest-services/docker.proxy.sock"
> ```

**密钥格式转换：** wcdb-key-tool 输出嵌套 JSON，wx-cli 需要扁平 hex 格式：
```json
{
  "bizchat/bizchat.db": "0d455210c8ac80...",
  "contact/contact.db": "d185c419ee84ce..."
}
```
`extract_keys.sh` 自动完成转换。

### Phase 5 — wx-cli 查询

wx-cli v0.1.10 没有 `daemon start` 命令（daemon 是 lazy-start 的）。直接在首次查询时自动拉起。

```bash
# 列出最近会话
docker exec wechat-selkies /config/tools/wx-cli sessions

# 搜索消息（JSON 输出）
docker exec wechat-selkies /config/tools/wx-cli search "你好" --json

# 聊天记录
docker exec wechat-selkies /config/tools/wx-cli history

# 联系人
docker exec wechat-selkies /config/tools/wx-cli contacts

# 未读消息
docker exec wechat-selkies /config/tools/wx-cli unread
```

## 容器重启后的恢复流程

此容器每次重启会丢失 gdb、python3-pip、sqlcipher 等 apt 包。恢复步骤：

```bash
# 1. 检查容器状态
docker ps --filter name=wechat-selkies

# 2. 重装依赖（apt 包丢失，但 wcdb-key-tool/wx-cli 在 /config 卷中保留）
docker exec wechat-selkies bash /config/setup_env.sh

# 3. 验证密钥仍然有效
docker exec wechat-selkies /config/tools/wx-cli sessions
```

> 如果 all_keys.json 丢失（未挂载卷或格式问题），需要重新执行 Phases 3-4。

## 完整重新部署方案

从头部署新环境的步骤：

```bash
# Step 1: 拉项目
git clone <repo-url> docker-wxcli
cd docker-wxcli

# Step 2: 创建持久化目录
mkdir -p config/tools config/.wx-cli

# Step 3: 启动容器
docker-compose up -d
sleep 10  # 等待容器初始化

# Step 4: 安装依赖
docker exec wechat-selkies bash /config/setup_env.sh

# Step 5: 验证 SYS_PTRACE
docker exec wechat-selkies capsh --print | grep cap_sys_ptrace

# Step 6: 浏览器打开 http://localhost:3000
#         双击 WeChat 图标，等待出现二维码

# Step 7: 运行提取（配合扫码时序）
#         a. 先让微信处于二维码/未登录状态
#         b. 运行脚本：
docker exec -it wechat-selkies bash /config/extract_keys.sh
#         c. 按提示退出登录 → 重新扫码登录
#         d. 等待 PBKDF2 派生完成

# Step 8: 查询验证
docker exec wechat-selkies /config/tools/wx-cli sessions
```

## 故障排除

| 问题 | 原因 | 解决 |
|------|------|------|
| `gdb: not found` | 容器重启后 apt 包丢失 | `docker exec wechat-selkies bash /config/setup_env.sh` |
| `Cannot access memory at address` | 微信进程 PID 变化后 base addr 改变 | 重新运行 extract（用当前 PID） |
| `未能捕获 passphrase` | 扫码登录发生在断点设置之前 | 先退到二维码，运行脚本，再扫码 |
| passphrase 捕获到但密钥派生失败 | 微信版本与 wcdb-key-tool 不兼容 | 更新 wcdb-key-tool: `git -C /config/tools/wcdb-key-tool pull` |
| `wx sessions` 返回空 | 微信未登录或 DB 缓存未构建 | 确认微信已登录，稍等重试 |
| Docker Desktop connection refused | WSL2 socket 权限 | 使用 Windows docker.exe 或创建 wsl-desktop context |

## 免责声明与版权声明

> 🚨 **重要声明：** 本项目与腾讯公司 (Tencent) 无任何关联，属于独立的第三方开源项目。

### 版权声明

- **微信®** 是 **腾讯公司** 的注册商标和版权作品
- 本项目中使用的微信相关图标、logo 等视觉元素的版权归腾讯公司所有
- 本项目仅为技术展示和学习目的，不用于商业用途
- 如有版权争议，将立即移除相关内容

### 法律合规

- 本项目严格遵守相关法律法规和用户协议
- 用户使用本项目时应遵守当地法律法规
- 本项目不对用户的使用行为承担法律责任
- 如腾讯公司认为存在侵权行为，请联系我们立即处理

### 使用条款

- 本项目仅供学习、研究和个人使用
- 禁止用于任何商业目的或盈利活动
- 用户应自行承担使用风险和法律责任
- 请遵守微信用户协议和相关服务条款

## 安全

- `all_keys.json` 包含微信数据库 AES 密钥，容器内权限 **600**
- 不将 `config/` 目录提交至版本控制（含敏感密钥和微信数据）
- 密钥仅在容器本地使用，不通过网络传输
- 建议将 `config/.wx-cli/all_keys.json` 加入 `.gitignore`

## 引用项目与许可

本项目整合了以下开源项目，感谢各位作者的贡献：

| 项目 | 许可证 | 说明 |
|------|--------|------|
| [nickrunning/wechat-selkies](https://github.com/nickrunning/wechat-selkies) | MIT | 容器基础镜像 |
| [TANGandXUE/wcdb-key-tool](https://github.com/TANGandXUE/wcdb-key-tool) | MIT | 微信数据库密钥提取工具 |
| [jackwener/wx-cli](https://github.com/jackwener/wx-cli) | Apache-2.0 | 微信数据 CLI 工具 |

本项目本身采用 **MIT 许可证**（见 `LICENSE`），但引用的 wx-cli 为 **Apache-2.0** 许可证。Apache-2.0 要求衍生作品附带许可证副本和署名声明，详见 `NOTICE` 文件。
