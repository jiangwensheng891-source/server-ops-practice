# 快速开始

## 环境要求

- Ubuntu 22.04 / 24.04
- Docker + Docker Compose
- Nginx
- Python 3（用于自检脚本）

## 脚本用法

### health_check.sh

开机自检，检查 6 项：容器状态、端口监听、HTTPS 入口、证书有效期、磁盘内存、最近备份。

    sudo ./scripts/health_check.sh

### backup.sh

每日备份，生成业务包 + GPG 加密的 secrets 包。

    sudo ./scripts/backup.sh

### restore.sh

从备份包恢复环境，并记录 RTO。

    sudo ./scripts/restore.sh <business.tar.gz> <secrets.tar.gz.gpg>

### nginx_cache_stats.sh

统计 Nginx 缓存命中率，写入 MariaDB 并推送到 Uptime Kuma。由 crontab 每 5 分钟自动调用。

## 备份策略

- 服务器本地：每日 03:00 自动生成
- 异地拉取：Windows 电脑每日 04:00 拉取
- GPG 密码：单独保存到密码管理器

## 许可

MIT
