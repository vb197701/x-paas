# V2ray for PaaS — Xray-core 版

Nginx + WebSocket + VMess / VLESS，跑在 PaaS 容器里，核心换成 Xray-core。
PaaS 在前面做 TLS 终止，所以这里不做 Reality / XTLS-Vision，那是 VPS 部署的路线。

## 版本（2026-11-16 核实）

- 基础镜像：`nginx:1.30.6-alpine`，按 digest 锁定
- 核心：Xray-core `v26.11.9`（2026-11-09 发布），构建时按 SHA-256 校验
- 架构：`linux/amd64`、`linux/arm64`

## 环境变量

| 变量 | 是否必须 | 默认值 | 备注 |
| --- | --- | --- | --- |
| `UUID` | 是 | 无 | 必须自己生成，绝不能用旧 README 里的公开默认值，启动时为空或为默认值会直接报错退出 |
| `PORT` | 否 | `8080` | PaaS 注入的端口，Koyeb / Render / Railway 都会给，填什么就监听什么 |
| `VMESS_WSPATH` | 否 | `/vmess` | 以 `/` 开头 |
| `VLESS_WSPATH` | 否 | `/vless` | 以 `/` 开头，不能和 VMess 相同 |

生成 UUID：

```sh
uuidgen
# 或
python3 -c "import uuid; print(uuid.uuid4())"
```

## 部署

1. 把这 5 个文件放回原仓库对应位置：`Dockerfile`、`entrypoint.sh`、`nginx.conf.template`、`config.json.template`、`.github/workflows/docker.yml`，另外加 `.dockerignore`。
2. 删掉旧的 `.github/workflows/koyeb.yml`，它只手动触发、用的是旧版 Action。
3. 镜像同时推到 GHCR（`ghcr.io/<owner>/<repo>`）和 Docker Hub（`<user>/v2-koyeb`，保持你原来 PaaS 拉取的地址不变）。Docker Hub 需要在仓库 Secrets 里配好 `DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN`，GHCR 用自带的 `GITHUB_TOKEN` 就行，不用额外配。
4. 在 PaaS 上从镜像部署，填好 `UUID`，健康检查用 `/health`。

## 客户端

- 地址：PaaS 给你的域名
- 端口：443
- 传输：WebSocket + TLS，路径填你设的 `/vmess` 或 `/vless`
- VMess：UUID + alterId 0；VLESS：UUID，encryption none

## 相对旧版改了什么

- 核心从 V2Ray 换成 Xray-core，VMess / VLESS 配置兼容，客户端不用重配。
- 基础镜像从没锁版本的 `nginx:latest`（Debian）换成锁 digest 的 `nginx:1.30.6-alpine`，镜像更小。
- 核心不再构建时抓 latest，改为固定版本 + SHA-256 校验。
- 启动时强制校验 UUID、端口和路径，配置先过 `nginx -t` 和 `xray run -test` 再启动。
- 不再用 base64 藏配置，改成明文模板，方便检查。
- 删掉了运行时拉取哪吒探针安装脚本的做法。如需探针，请单独部署或在构建期固定版本接入，不要在启动时拉远程脚本。
- 工作流改为 push 到 main / 打 tag 自动构建，多架构、多标签、带缓存、 provenance 和 SBOM。
- 入口不再随机改名核心二进制，保留 `/usr/local/bin/xray`，方便排障。

## Xray 的弃用提示

用 Xray-core v26.11.9 实测 `xray run -test`，配置能通过，但会有两条警告：WebSocket 传输和 VMess 都被标记为已弃用，上游建议尽快迁移到 XHTTP 和 VLESS Encryption。

这里先保留 WS + VMess / VLESS，是为了兼容现有客户端。等你的客户端都支持 XHTTP 后，可以把 `streamSettings.network` 从 `ws` 换成 `xhttp`，这是下一步的迁移方向，不是现在必须改的。

## 注意

- Koyeb 免费 Starter 自 2026 年 2 月起已不对新用户开放，新账号要走付费计划，老账号保留原待遇。换平台前先确认你的账号状态。
- 免费 PaaS 实例一般会休眠，长时间没流量首次访问会慢，这是平台限制，不是镜像问题。
