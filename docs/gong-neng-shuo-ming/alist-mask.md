# AList 伪装站 + 反代加固（XHTTP + CDN 专用）

套 CDN 的节点需要一个「看起来正常」的网站当门面：路径命中 xhttp 的交给后端，其余请求落到一个文件站。这个一键脚本就是干这件事的——装 AList（只读）、装 nginx、按路径分流，并把管理入口收起来。

```bash
bash <(curl -Ls https://raw.githubusercontent.com/RyanRaw/XrayR_For_SSpanel-uim/master/install/install.sh) mask \
  --domain ro.example.com --path /steam --upstream 127.0.0.1:21074
```

也可以直接用独立脚本（参数完全相同）：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/RyanRaw/XrayR_For_SSpanel-uim/master/install/alist-mask.sh) --help
```

## 它做了什么

1. 安装 `nginx`、`jq`、`openssl`（按 apt / dnf / yum / apk 自动选择）
2. 安装 **AList**（v3，最新版）到 `/opt/alist`，systemd / OpenRC 服务名 `alist`
3. 把 AList 监听收敛到 `127.0.0.1:5244`（只有 nginx 能访问）
4. 建好只读文件站：`/opt/alist/files` 下放少量示例文件，`guest` 用户启用且 `permission=0`（只能看和下载，不能写）
5. 写 nginx 站点：`<xhttp 路径>` 反代到后端，其余全部给 AList
6. 加固三件套（见下）
7. 自检并打印下一步

## 参数

| 参数 | 默认 | 说明 |
| :--- | :--- | :--- |
| `--domain` | 无（必填） | `server_name`，多个用逗号分隔 |
| `--path` | `/steam` | xhttp 路径前缀，必须和面板节点里 `path` 完全一致 |
| `--upstream` | `127.0.0.1:21074` | 后端 XrayR 的**明文** xhttp 入站地址 |
| `--cert` / `--key` | 无 | 证书 fullchain / 私钥；不给则自签（CDN 用 Full(strict) 必须给真证书） |
| `--admin-ip` | 仅 `127.0.0.1` | 管理入口与 WebDAV 白名单，可多个，逗号分隔 |
| `--alist-port` | `5244` | AList 监听端口（始终绑 127.0.0.1） |
| `--extra-port` | 无 | 额外再听一个 HTTPS 端口，比如 CDN 回源用了自定义端口 |
| `--no-alist` | 关 | 只配 nginx 分流，不装 AList |
| `--force` | 关 | 已装 AList 也重新下载二进制 |
| `-y` / `--yes` | 关 | 跳过二次确认 |

## 加固内容

| 项 | 做法 |
| :--- | :--- |
| 管理入口 | `/@manage`、`/api/admin`、`/dav` 走 IP 白名单，**非白名单直接 404**（不是 403，不暴露后台存在） |
| 真实 IP | 写入 Cloudflare 全段 `set_real_ip_from` + `CF-Connecting-IP`，否则 nginx 看到的全是 CDN 的 IP，白名单形同虚设 |
| 版本号 | `server_tokens off` |
| 来源收敛 | AList 只监听 `127.0.0.1`；`--upstream` 建议也用 `127.0.0.1:<端口>`，让 XrayR 不直接暴露 |
| 默认站点 | Debian 系会清掉 `sites-enabled/default`，避免 IP 直连看到 nginx 欢迎页 |

## 生成的文件

| 路径 | 用途 |
| :--- | :--- |
| `/etc/nginx/sites-available/alist-mask.conf`（或 `conf.d/`、`http.d/`） | 站点配置，已存在会先备份成 `.bak.<时间戳>` |
| `/etc/nginx/conf.d/zz-cdn-realip.conf` | Cloudflare 真实 IP |
| `/etc/nginx/conf.d/zz-upgrade-map.conf` | `$connection_upgrade` |
| `/etc/nginx/conf.d/zz-alist-admin.conf` | 管理入口白名单（改完 `systemctl reload nginx` 生效） |
| `/etc/nginx/ssl/<域名>/` | `fullchain.pem` / `privkey.pem` |
| `/root/alist_admin_password.txt` | AList 管理密码（600） |
| `/opt/alist/files` | 伪装站根目录（可以往里放自己的文件） |

脚本是幂等的：重复执行会复用已有证书、跳过已装的 AList、跳过已存在的挂载 `/`、密码保持不变。

## 和 CDN 的配合

回源端口要按 CDN 的 SSL 模式选：

| CDN SSL 模式 | 回源端口 | 说明 |
| :--- | :--- | :--- |
| Flexible | `80` | CDN→源站明文 |
| Full | `443` | CDN→源站 TLS，自签证书也能过 |
| Full (strict) | `443` | 必须是**可信证书**，自签会直接 521 |

脚本会同时监听 `80` 和 `443`（给了 `--extra-port` 再多一个），所以你在 CDN 后台换模式时源站不用跟着改。**如果切到 Full 之后突然全站 521，先确认源站有没有在听 443。**

## 面板侧怎么填

节点 `custom_config` 里：

* `host` / `xhttp_host` / `sni` = 上面的域名
* `path` = 上面的 `--path`
* `offset_port_node` = `--upstream` 里的端口（建议把该入站绑 `127.0.0.1`）
* `offset_port_user` = `443`（客户端连 CDN 用）

## 验收

```bash
curl -s  -o /dev/null -w '%{http_code}\n' -H 'Host: ro.example.com' http://127.0.0.1/        # 200
curl -sk -o /dev/null -w '%{http_code}\n' -H 'Host: ro.example.com' https://127.0.0.1/       # 200
curl -sk -o /dev/null -w '%{http_code}\n' -H 'Host: ro.example.com' https://127.0.0.1/@manage # 本机 200，外部应 404
```

再经 CDN 验一遍：首页应是伪装站，`<path>` 直连返回 404/400 属正常（那是 xhttp 在等握手，不是故障）。

## 回滚

```bash
rm -f /etc/nginx/sites-enabled/alist-mask.conf
# 或从备份恢复：/etc/nginx/sites-available/alist-mask.conf.bak.*
systemctl stop alist && systemctl disable alist
rm -rf /opt/alist
systemctl reload nginx
```
