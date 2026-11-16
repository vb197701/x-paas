# V2ray for PaaS — Xray-core 版

Nginx + XHTTP + VMess / VLESS，跑在 PaaS 容器里，核心换成 Xray-core。
PaaS 在前面做 TLS 终止，所以这里不做 Reality / XTLS-Vision，那是 VPS 部署的路线。

## 版本（2026-11-16 核实）

- 基础镜像：`nginx:1.30.6-alpine`，按 digest 锁定
- 核心：Xray-core `v26.11.9`（2026-11-09 发布），构建时按 SHA-256 校验
- 架构：`linux/amd64`、`linux/arm64`

## 环境变量

| 变量 | 是否必须 | 默认值 | 备注 |
| --- | --- | --- | --- |
| `UUID` | 是 | 无 | 必须自己生成，绝不能用旧 README 里的公开默认值，启动时为空或为默认值会直接报错退出 |
| `PORT` | 否 | `80` | PaaS 注入的端口就听那个；没注入时默认 80，和原仓库一致。注意：PaaS 服务上配置的端口必须和这里一致，Koyeb 默认就是 80，Render / Railway 会自己注入 `$PORT` 覆盖这个默认值 |
| `VMESS_WSPATH` | 否 | `/vmess` | 现在是 XHTTP 路径，以 `/` 开头；变量名没改，PaaS 上已填的值不用动 |
| `VLESS_WSPATH` | 否 | `/vless` | 现在是 XHTTP 路径，以 `/` 开头，不能和 VMess 相同 |

生成 UUID：

```sh
uuidgen
# 或
python3 -c "import uuid; print(uuid.uuid4())"
```

## 自动更新 Xray 版本

不用手动盯着 Xray 发版，有两个工作流配合：

- `check-xray.yml`：每周一 03:00 UTC（北京时间 11:00）检查一次，也可以在 Actions 页手动点 `Run workflow` 立即测一次。它用 GitHub API 查 Xray-core 的最新正式版（不含预发布版），和 `xray.version` 里的当前版本比对。
- 没新版：什么都不做，不提交、不构建。
- 有新版：自动拉新版两个架构的 `.dgst` 文件取 SHA-256，用 `.github/scripts/update-xray.py` 同步改 `xray.version`、`Dockerfile` 里的版本号和两个 SHA、以及 README 里的版本号，然后提交推送。这一推会触发 `docker.yml` 自动构建。

构建出来的镜像会多两个带 Xray 版本的 tag，一眼就能看出里面是哪个核心：

- `ghcr.io/<owner>/<repo>:xray-v26.11.9`
- `ghcr.io/<owner>/<repo>:v26.11.9`
- Docker Hub 同理：`<user>/v2-koyeb:xray-v26.11.9`

另外还保留 `latest` 和短 commit SHA 的 tag。PaaS 上想固定用某个 Xray 版本，就选 `xray-v26.11.9` 这种 tag，别用 `latest`。

注意：定时任务只在默认分支上跑，而且 GitHub 可能会延迟执行；想立即验证就手动跑一次 `check-xray.yml`。现在最新就是 `v26.11.9`，跑一次应该是什么都不做。

## 部署

1. 把这些文件放回原仓库对应位置：`Dockerfile`、`entrypoint.sh`、`nginx.conf.template`、`config.json.template`、`xray.version`、`.github/workflows/docker.yml`、`.github/workflows/check-xray.yml`、`.github/scripts/update-xray.py`，另外加 `.dockerignore`。
2. 删掉旧的 `.github/workflows/koyeb.yml`，它只手动触发、用的是旧版 Action。
3. 镜像同时推到 GHCR（`ghcr.io/<owner>/<repo>`）和 Docker Hub（`<user>/v2-koyeb`，保持你原来 PaaS 拉取的地址不变）。Docker Hub 需要在仓库 Secrets 里配好 `DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN`，GHCR 用自带的 `GITHUB_TOKEN` 就行，不用额外配。
4. 在 PaaS 上从镜像部署，填好 `UUID`，健康检查用 `/health`。

## 客户端

- 地址：PaaS 给你的域名
- 端口：443
- 传输：XHTTP + TLS，`mode` 选 `auto`，路径填你设的 `/vmess` 或 `/vless`，必须和服务端一致
- VMess：UUID + alterId 0；VLESS：UUID，encryption none
- 客户端必须支持 XHTTP：v2rayN、v2rayNG、sing-box 都支持；Clash / mihomo 系截至 2026 年 5 月还不支持 XHTTP，用这类客户端要保留一条 WS 备用通道，不要全切过来

## 相对旧版改了什么

- 核心从 V2Ray 换成 Xray-core，VMess / VLESS 配置兼容，客户端不用重配。
- 基础镜像从没锁版本的 `nginx:latest`（Debian）换成锁 digest 的 `nginx:1.30.6-alpine`，镜像更小。
- 核心不再构建时抓 latest，改为固定版本 + SHA-256 校验。
- 启动时强制校验 UUID、端口和路径，配置先过 `nginx -t` 和 `xray run -test` 再启动。
- 不再用 base64 藏配置，改成明文模板，方便检查。
- 删掉了运行时拉取哪吒探针安装脚本的做法。如需探针，请单独部署或在构建期固定版本接入，不要在启动时拉远程脚本。
- 工作流改为 push 到 main / 打 tag 自动构建，多架构、多标签、带缓存、 provenance 和 SBOM。
- 入口不再随机改名核心二进制，保留 `/usr/local/bin/xray`，方便排障。

## 改成 XHTTP 后还剩什么

这次只改了传输层：`network` 从 `ws` 改成 `xhttp`，`wsSettings` 改成 `xhttpSettings`，只填 `path` 和 `mode: auto`，其他 XHTTP 高级选项一律不填，让服务端 `auto` 自己协商。

用 Xray-core v26.11.9 实测 `xray run -test`，配置能通过，WebSocket 的弃用警告已经没了，只剩 VMess 那一条。VMess 本身仍被标记为已弃用，上游建议迁到 VLESS Encryption；想彻底去掉警告就删掉 VMess 那条入站、只留 VLESS，需要的话再说。

**服务端和客户端必须一起改，只改一边连不上。** 路径、mode、TLS 都要对得上。先拿一个支持 XHTTP 的客户端（v2rayNG / sing-box）测通，再把其他客户端逐个切过来。

## 注意

- Koyeb 免费 Starter 自 2026 年 2 月起已不对新用户开放，新账号要走付费计划，老账号保留原待遇。换平台前先确认你的账号状态。
- 免费 PaaS 实例一般会休眠，长时间没流量首次访问会慢，这是平台限制，不是镜像问题。
