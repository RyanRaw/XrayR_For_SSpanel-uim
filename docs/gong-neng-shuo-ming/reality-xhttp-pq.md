---
description: REALITY、XHTTP 与后量子特性（X25519MLKEM768、ML-DSA-65）
---

# REALITY、XHTTP 与后量子特性

本页说明 XrayR 对 REALITY、XHTTP 以及两项后量子特性的支持情况。

## REALITY

支持 `security: reality`（VLESS / Trojan）。服务端参数**可由面板下发**，也支持写在本地 `config.yml` 的 `REALITYConfigs`。

### 取值优先级

REALITY 的每个字段独立取值，前一层没给就往下走：

```
面板 reality-opts → reality-opts.xxx 点号键 → 平铺 snake_case → 平铺 camelCase → 本地 REALITYConfigs → 内置默认值
```

也就是说面板可以只下发它管得住的字段（私钥、SNI、shortId），其余交给节点本地配置，不必每台节点都推全量。

### 字段对照

| 本地 `REALITYConfigs` | 嵌套键 `reality-opts.*` | 平铺键（`custom_config` 顶层） | 类型 |
| :--- | :--- | :--- | :--- |
| `Show` | `show` | `show` | bool |
| `Dest` | `dest` | `dest`（缺失时用 `sni + ":443"`） | string |
| `ProxyProtocolVer` | `proxy_protocol_ver` | `proxyProtocolVer` | uint |
| `ServerNames` | `server_names` | `serverNames` 或单值 `sni` | string[] |
| `PrivateKey` | `private_key` | `privateKey` | string |
| `MinClientVer` | `min_client_ver` | `minClientVer` | string |
| `MaxClientVer` | `max_client_ver` | `maxClientVer` | string |
| `MaxTimeDiff` | `max_time_diff` | `maxTimeDiff` | uint |
| `ShortIds` | `short_ids` | `shortIds` 或单值 `shortId` | string[] |
| `Mldsa65Seed` | `mldsa65Seed` | `mldsa65Seed` | string |
| `LimitFallbackUpload` | `limit_fallback_upload` | `limitFallbackUpload` | object |
| `LimitFallbackDownload` | `limit_fallback_download` | `limitFallbackDownload` | object |

`LimitFallback` 的子字段在两种写法下共用同一套键名：`after_bytes`、`bytes_per_sec`、`burst_bytes_per_sec`。

### 兼容的写法

面板实现不一致时不必先改面板，下面这些写法都能识别：

* `"enable_reality": "true"` —— 字符串写法，等价于布尔 `true`；`"1"` / `"on"` / `1` 同样识别
* `"reality-opts.private_key": "..."` —— 点号平铺键
* `"private_key": "..."` —— 平铺 snake_case

无法识别的布尔写法会降级为 `false`，不会导致整段 `custom_config` 解析失败。

### 内置默认值

| 字段 | 面板与本地都没提供时 |
| :--- | :--- |
| `shortIds` | `["", "0123456789abcdef"]`。xray 要求该项非空，否则报 `empty "shortIds"` 拒绝构建 |
| `dest` | 由 `sni` 推导为 `sni + ":443"` |

`privateKey` **没有默认值**，必须由面板或本地 `config.yml` 提供，且解码后必须是 32 字节。

## XHTTP

支持 `network: xhttp`（等同 `splithttp`），`path`、`host`、`mode` 均可由面板下发。

* `mode` 支持 `auto` / `packet-up` / `stream-up` / `stream-one`，留空时使用 xray 默认的 `auto`；非法取值会被 xray 拒绝启动。
* 服务端 `host` 留空即不校验 Host 头；非空时与请求 Host **精确匹配**（大小写不敏感、忽略端口），不匹配直接拒绝连接。

`host` 的填法：

| 场景 | `host` |
| :--- | :--- |
| xhttp + REALITY | 留空，或与 `sni` 一致 |
| xhttp + TLS | 自己的域名 |
| 前面套 CDN | CDN 回源时携带的域名 |
| 服务端多域名复用 | 该节点对应的域名 |

注意不要带端口，也不支持通配符。

## X25519MLKEM768（后量子密钥交换）

REALITY 的 TLS 1.3 握手支持 X25519MLKEM768 混合后量子密钥交换，用于抗「先存后破」（harvest now, decrypt later）。

* **服务端自动支持，无需任何配置。**
* 是否协商由客户端 ClientHello（uTLS 指纹）决定，服务端跟随。
* 在客户端开启 REALITY 的 `show` 后可确认是否生效，日志会打印：

```
REALITY localAddr: ... is using X25519MLKEM768 for TLS' communication: true
```

## ML-DSA-65（后量子签名）

REALITY 支持用 ML-DSA-65 对服务端证书做额外签名校验，用于抵抗未来量子计算机伪造 REALITY 认证。

* 服务端使用 `mldsa65Seed`，客户端使用配对的 `mldsa65Verify`。
* `mldsa65Seed` 由 `XrayR mldsa65` 生成，为 32 字节 `base64.RawURLEncoding`，且**必须与 `privateKey` 不同**，否则 xray 拒绝启动。
* 客户端未配置 `mldsa65Verify` 时连接仍可建立，只是不做额外校验。
* 在客户端开启 REALITY 的 `show` 后可确认是否生效，日志会打印：

```
REALITY localAddr: ... is using ML-DSA-65 for cert's extra verification: true
```

### 生成密钥对

管理脚本菜单 `14` / `15` 可直接生成，也可用命令行：

```bash
XrayR x25519                 # 生成 x25519 密钥对
XrayR x25519 -i <私钥>       # 由私钥反推公钥
XrayR mldsa65                # 生成 ML-DSA-65 密钥对
XrayR mldsa65 -i <seed>      # 由 seed 反推 Verify
```

生成结果的用途：

| 输出 | 填到哪 |
| :--- | :--- |
| `Private key` | 服务端 `privateKey` / `REALITYConfigs.PrivateKey` |
| `Public key` | 客户端 `pbk` / `publicKey` |
| `Seed` | 服务端 `mldsa65Seed` |
| `Verify` | 客户端 `mldsa65Verify` |
