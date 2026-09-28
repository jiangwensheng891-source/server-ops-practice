# 恢复演练资产清单

## 1. 代码
- /home/ubuntu/dashboard（Flask 应用、docker-compose.yml、deploy.sh、.github/workflows/deploy.yml）
- /home/ubuntu/uptime-kuma/docker-compose.yml
- /home/ubuntu/nginx_cache_stats.sh
- /home/ubuntu/backup.sh
- GitHub 私有仓库：jiangwensheng891-source/monitor-dashboard

## 2. 数据
- MariaDB 数据库 test_db：业务表 server_metrics、nginx_cache_stats
- Uptime Kuma 数据卷 uptime-kuma，挂载 /app/data：监控配置、历史心跳
- /home/ubuntu/backups/ 里的备份产物
- /home/ubuntu/metrics/nginx_cache_latest.json
- /var/log/nginx/dashboard_cache.log（缓存命中统计原始日志）
- /var/cache/nginx/dashboard_cache（缓存文件，可重建，可丢）

## 3. 配置
- /home/ubuntu/dashboard/docker-compose.yml
- /home/ubuntu/uptime-kuma/docker-compose.yml
- /etc/nginx/sites-available/dashboard
- /etc/nginx/sites-available/dashboard-https
- /etc/nginx/sites-available/monitor
- /etc/nginx/conf.d/cache_log.conf
- /etc/ssh/sshd_config
- /root/.ssh/authorized_keys
- root crontab：
  - backup.sh 每天 03:00
  - nginx_cache_stats.sh 每 5 分钟
- UFW 规则、腾讯云安全组
- DNSPod DNS 记录：example.com、monitor.example.com
- Uptime Kuma Monitor #2、#3 配置（包含在 Kuma 数据里）

## 4. 密钥/敏感信息
- /home/ubuntu/dashboard/.env：DB_ROOT_PASSWORD、DB_NAME、DB_HOST、DB_HOST_LOCAL
- /root/.backup_pass：GPG 加密密码
- /etc/letsencrypt/live/example.com/：Let's Encrypt 私钥和证书
- DNSPod API 密钥：dnspod-109.ini，certbot 插件用
- GitHub Secrets：CI SSH key 等
- Server酱 SendKey：Uptime Kuma 通知用
- KUMA_PUSH_URL 里的 push token
- SSH 私钥：个人 key 在本地，CI key 在 GitHub Secrets；服务器上只有公钥
