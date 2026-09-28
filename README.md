# Server Ops Practice

一套完整的自托管服务运维实践项目。

> 学习项目的脱敏展示版，所有 IP、域名、Token 已替换成占位符。

## 项目背景

在一台 2核2G 的云服务器上，从零搭建一个完整的自托管环境，并通过 16 个专题课，逐步把系统从"能跑起来"打磨到"挂了能恢复、出事能知道、平时不操心"。

## 技术栈

- 应用：Flask（Python）
- 反向代理：Nginx（含缓存）
- 数据库：MariaDB
- 容器：Docker + Compose
- 监控：Uptime Kuma + ServerChan（微信推送）
- 证书：Let's Encrypt + certbot（DNSPod DNS 验证）
- CI/CD：GitHub Actions
- 备份：Bash + GPG 加密 + Windows 异地拉取
- 安全：UFW + fail2ban + SSH 加固 + ACL

## 目录结构

showcase/

- scripts/ 运维脚本
  - health_check.sh 开机自检
  - backup.sh 每日备份
  - restore.sh 恢复脚本
  - nginx_cache_stats.sh 缓存命中率统计
- compose/ Docker Compose 样例
  - docker-compose.dashboard.yml
  - docker-compose.kuma.yml
- reports/ 演练与资产文档
  - asset_inventory.md 资产清单
  - restore_report.md 恢复演练报告

## 关键能力

### CI/CD 自动化
GitHub push → SSH 触发 deploy.sh → 容器热更新。

### 三层备份
- 第一层：服务器本地，每日 03:00 自动生成
- 第二层：Windows 电脑异地拉取，每日 04:00
- 第三层：GPG 密码单独抄写到密码管理器

### 灾难恢复
- 恢复脚本一键解包 + 校验
- RTO 秒级
- 做过"整机丢失"演练

### 全链路监控
- 外探：公网入口
- 内探：容器内部健康检查
- 业务指标：Nginx 缓存命中率 → Kuma → 微信告警

### 安全加固
- SSH：禁 root、禁密码登录
- CI key：command= 限制
- 专用备份用户：no-pty + ACL
- HTTPS：Let's Encrypt + 自动续期

### 资源保护
- 所有容器设 mem_limit
- 日志轮转：max-size=10m, max-file=3
- 磁盘 / 内存 / 证书自检告警

## 快速开始

    sudo ./scripts/health_check.sh

6 项检查，2 秒出结果。

## 学习收获

16 个专题课覆盖：应用部署、反向代理、HTTPS、数据库、CI/CD、监控告警、备份恢复、安全加固、资源限制、运维脚本化。

## 许可

MIT