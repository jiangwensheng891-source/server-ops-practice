# 恢复演练报告（第12课）

## 一、演练基本信息
- 演练时间：2026-09-26
- 演练人：ubuntu
- 演练类型：临时目录恢复（不动生产）
- 恢复目标目录：/home/ubuntu/restore_drill/restored/

## 二、使用的备份
- 业务包：business_20260923_181103.tar.gz
- secrets 包：secrets_20260923_181103.tar.gz.gpg
- 备份生成时间：2026-09-23 18:11

## 三、RTO 记录
- 解包 + 解密 + 校验耗时：见下方“RTO 实测”
- RTO 实测：0 秒（日志起止：2026-09-26 10:49:09 → 2026-09-26 10:49:09）
- RTO 目标：≤ 30 分钟（首次演练只统计，不设硬性门槛）

## 四、恢复内容清单
### 业务包内含
- dashboard/（Flask 应用、docker-compose.yml、deploy.sh、workflow）
- nginx/（nginx.conf、sites-available、sites-enabled）
- db_test_db_20260923_181103.sql（MariaDB dump）
- uptime-kuma-data.tar.gz（Kuma 数据卷）

### secrets 包内含
- dashboard.env
- dnspod-109.ini
- letsencrypt.tar.gz

## 五、校验结果
- 关键文件校验：全部 OK / 有 MISS（填实际）
- 数据库 dump：非空
- secrets 解密：成功

## 六、发现的问题（缺口）
### 备份侧缺口
1. /root/.backup_pass 未纳入备份（最严重）
2. /etc/nginx/conf.d/cache_log.conf 未备份
3. /home/ubuntu/uptime-kuma/docker-compose.yml 未备份
4. /home/ubuntu/nginx_cache_stats.sh 未备份
5. /home/ubuntu/backup.sh 未备份
6. /etc/ssh/sshd_config、/root/.ssh/authorized_keys 未备份
7. root crontab 未备份（含 KUMA_PUSH_URL）
8. /home/ubuntu/metrics/nginx_cache_latest.json 未备份
9. /var/log/nginx/dashboard_cache.log 未备份
10. UFW 规则、腾讯云安全组、DNSPod DNS 记录未备份

### 备份机制问题
- /home/ubuntu/backups/ 里只有 2026-09-23 18:11 一份，说明每日 03:00 自动备份可能未生效

## 七、结论
- 核心数据（数据库、Kuma 数据、dashboard 代码、nginx 站点配置、证书、dashboard.env、dnspod-109.ini）可以恢复。
- 但恢复后无法做到“整机一键还原”，需要手工补齐配置类和密钥类缺口。
- 下一步：修 backup.sh，把缺口补进去；同时排查 crontab 为什么没每天跑。

---

# 第13课修补记录（backup.sh 缺口补齐）

## 一、crontab 排查结论
- root crontab 里 `0 3 * * * /home/ubuntu/backup.sh` 是 **2026-09-26 10:21** 才安装的。
- Sep 24 / 25 / 26 的 03:00 没有记录，是因为那行还不存在，属正常。
- cron 服务 active + enabled，时区 Asia/Shanghai (+0800)，手动模拟执行退出码 0。
- **结论：不是 bug，是“闹钟刚设好，还没到第一次响”。下一次 Sep 27 03:00 起每天自动跑。**

## 二、backup.sh 新增备份内容
### 业务包新增
- /etc/nginx/conf.d/cache_log.conf
- /home/ubuntu/uptime-kuma/docker-compose.yml
- /home/ubuntu/nginx_cache_stats.sh
- /home/ubuntu/backup.sh
- /etc/ssh/sshd_config
- /root/.ssh/authorized_keys
- /home/ubuntu/metrics/nginx_cache_latest.json

### secrets 包新增
- /root/.backup_pass（GPG 密码本身）
- root crontab 导出（含 KUMA Push token，属敏感）

## 三、验证结果
- 新 backup.sh 语法 OK，权限 755，手动执行退出码 0。
- 最新业务包：business_20260926_105639.tar.gz（208K）
- 最新 secrets 包：secrets_20260926_105639.tar.gz.gpg（16K）
- 业务包 12 个关键条目全在，secrets 包 5 个关键条目全在。

## 四、仍未覆盖的缺口（留待下一课）
1. **异地备份**：备份包和原件同机，整机丢失就全丢。
2. **/root/.backup_pass 的异地副本**：目前只存在服务器上，且已进 secrets 包，但 secrets 包本身也在这台机器上。
3. **/var/log/nginx/dashboard_cache.log**：原始日志未备份（属可重建数据，优先级低）。
4. **UFW / 腾讯云安全组 / DNSPod DNS 记录**：未自动化导出，恢复时需手工重建。

## 五、旧稿保留
- /home/ubuntu/backup.sh.bak.20260926_105432
- /home/ubuntu/backup.sh.bak.20260926_105527
- /home/ubuntu/restore_drill/root_crontab_export.txt

---

# 第14课：异地备份（Windows 拉取）

## 一、方案
- 方向：Windows 主动拉，不是服务器推（家里不常开机）
- 目标目录：C:\Users\12709\backups_offsite
- 每日任务：PullBackupFromServer，每天 04:00 自动跑

## 二、服务器侧
- 新建专用用户 backup_pull
- authorized_keys 加限制：no-pty,no-port-forwarding,no-X11-forwarding,no-agent-forwarding
- ACL：setfacl -m u:backup_pull:x /home/ubuntu（只许穿过，不许列目录）
- 公钥：ssh-ed25519 AAAAC3Nza...SdRN backup-pull-from-windows
- 私钥：只在 Windows，C:\Users\12709\.ssh\backup_pull_ed25519

## 三、Windows 侧
- 私钥：C:\Users\12709\.ssh\backup_pull_ed25519
- 取件脚本：C:\Users\12709\backups_offsite\pull_backup.ps1
- 密码文件：C:\Users\12709\backups_offsite\backup_pass.txt（注意：末尾不能有 CRLF）
- 定时任务：PullBackupFromServer，每天 04:00，运行账户为本机用户
- 保留最近 7 份

## 四、演练结果
- 11:19 服务器新版 backup.sh 生成的 secrets 包已含 root_crontab.txt
- Windows 拉取成功：business_20260926_111929.tar.gz + secrets_20260926_111929.tar.gz.gpg
- Windows gpg 解密成功，CRLF 问题修复后，5 个 secrets 文件全在
- 业务包 8 个条目全在（sites-enabled 软链接 Windows 跳过，正常）
- 结论：整机丢失，只靠 Windows 本地包 + 密码，可完整恢复核心资产

## 五、遗留项
1. sites-enabled/ 三个软链接恢复时需手工重建
2. UFW / 腾讯云安全组 / DNSPod DNS 记录未自动化，恢复时手工重建
3. GPG 密码在对话中泄露，需轮换（见下一节）

---


---

# 第14课补充：GPG 密码轮换

## 原因
- 旧密码在排障过程中被明文贴入对话，视为已泄露。

## 操作
- 旧密码：已从密码管理器删除
- 新密码：openssl rand -base64 32 生成，写入 /root/.backup_pass
- 文件权限：root:root 600
- 文件大小：44 字节，结尾无 0a
- 重跑 backup.sh，新 secrets 包用新密码解密成功，5 样齐全
- Windows 端 backup_pass.txt 已用 WriteAllText 更新，结尾无 0D 0A
- Windows 端拉取新 secrets 包，gpg 解密成功，5 样齐全

## 旧 secrets 包处理
- 服务器与 Windows 上仍保留旧密码加密的 secrets 包
- 计划：新密码稳定运行 7 天后删除旧包
- 删除前命令（先看列表）：
  sudo find /home/ubuntu/backups -name 'secrets_*.tar.gz.gpg' ! -newermt '2026-09-26 11:25' -print

---

# 第15课：Uptime Kuma 深度使用 + Docker 资源限制

## 一、Kuma 现状盘点
- 版本：1.23.17
- 监控 3 个：
  - #1 姜问生（http）→ https://example.com:8443
  - #2 生产环境-监控大屏（http）→ http://172.20.0.1:8081/api/health
  - #3 Nginx Cache HIT Ratio（push）→ push_token=YOUR_PUSH_TOKEN
- 通知 1 个：ServerChan 通知（1），active
- 状态页：无

## 二、第一刀：通知绑定
- 修前：monitor_notification 0 行，3 个监控全没绑通知
- 修后：3 个监控全绑 notification#1
- 验证：Kuma Test Notification，微信收到

## 三、第二刀：报警敏感度 + URL
- #1 姜问生 maxretries：0 → 2
- #1 URL：http://YOUR_SERVER_IP → https://example.com:8443
- 理由：外探真入口，与内探 #2 形成双保险

## 四、第三刀：心跳保留
- keepDataPeriodDays：180 → 30

## 五、第四刀：状态页
- 跳过（用户决定）

## 六、第五刀：Docker 资源限制 + 日志轮转
### 补丁1：adminer 加内存限制
- docker-compose.yml 中 adminer 段加 mem_limit: 128m
- 验证：docker stats 显示 LIMIT=128MiB

### 补丁2：daemon.json 加全局日志限制
- log-driver: json-file
- log-opts: max-size=10m, max-file=3
- 验证：新容器自动继承

### 当前所有容器限制
| 容器 | 内存 | 日志 |
|---|---|---|
| dashboard_a | 256M | 10m×3 |
| dashboard_b | 256M | 10m×3 |
| uptime-kuma | 256M | 10m×3 |
| my-mariadb | 512M | 10m×3 |
| my-adminer | 128M | 10m×3 |

## 七、遗留项
1. 通知渠道密钥待定期轮换（安全最佳实践）
2. 状态页未建
3. CPU 限制未设（优先级低）

---

# 第16课：开机自检脚本

## 一、背景
- 服务器是学习环境，开开关关
- 每次开机后需要快速知道环境状态
- 所以做一个 2 秒能跑完的自检脚本，而不是 24h 监控

## 二、脚本
- 路径：/home/ubuntu/health_check.sh（755）
- 用法：sudo /home/ubuntu/health_check.sh
- 6 节检查：
  1. 5 个容器状态（running + health）
  2. 7 个端口监听（22/80/8443/8081/3001/3306/8080）
  3. 2 个 HTTPS 入口（dashboard + Kuma）
  4. 证书有效期（≥30 绿，7-30 黄，<7 红）
  5. 磁盘 / 内存（<70% 绿，70-85 黄，≥85 红）
  6. 最近备份（<26h 绿，26-72h 黄，>72h 红）

## 三、附带修正
- UFW 里多余的 443 规则已收回
- 现有规则：22 / 80 / 8443 / 8081(容器网段)

## 四、当前自检结果
- 全部 ✅，环境健康
- 磁盘 19%，内存 42%
- 证书剩余 87 天
- 最新备份 0 小时前
