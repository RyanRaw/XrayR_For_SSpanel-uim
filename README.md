# XrayR — SSPanel-UIM 适配版

[![](https://img.shields.io/badge/TgChat-@XrayR讨论-blue.svg)](https://t.me/XrayR_project)
[![](https://img.shields.io/badge/Channel-@XrayR通知-blue.svg)](https://t.me/XrayR_channel)
![](https://img.shields.io/github/stars/RyanRaw/XrayR_For_SSpanel-uim)
![](https://img.shields.io/github/forks/RyanRaw/XrayR_For_SSpanel-uim)
![](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/actions/workflows/release.yml/badge.svg)
![](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/actions/workflows/docker.yml/badge.svg)
[![Github All Releases](https://img.shields.io/github/downloads/RyanRaw/XrayR_For_SSpanel-uim/total.svg)]()

[English](README-en.md) | [Iranian](README_Fa.md) | [Vietnamese](README-vi.md)

A Xray backend framework that can easily support many panels.

一个基于Xray的后端框架，支持V2ay,Trojan,Shadowsocks协议，极易扩展，支持多面板对接。

**本项目基于 [XrayR-project/XrayR](https://github.com/XrayR-project/XrayR) 二次开发，主要适配 SSPanel-UIM 前端。**

如果您喜欢本项目，可以右上角点个star+watch，持续关注本项目的进展。

使用教程：[详细使用教程](https://ryanraw.github.io/XrayR_For_SSpanel-uim/)
## 免责声明

本项目只是本人个人学习开发并维护，本人不保证任何可用性，也不对使用本软件造成的任何后果负责。

## 特点

* 永久开源且免费。
* 支持V2ray，Trojan， Shadowsocks多种协议。
* 支持Vless和XTLS等新特性。
* 支持单实例对接多面板、多节点，无需重复启动。
* 支持限制在线IP
* 支持节点端口级别、用户级别限速。
* 配置简单明了。
* 修改配置自动重启实例。
* 方便编译和升级，可以快速更新核心版本， 支持Xray-core新特性。
* 支持 REALITY、XHTTP，以及后量子特性（X25519MLKEM768、ML-DSA-65）。

## 传输与加密特性

### REALITY

* 支持 `security: reality`（VLESS / Trojan）。服务端参数**可由面板下发**，也支持写在本地 `config.yml` 的 `REALITYConfigs`。
* 取值优先级：面板 `reality-opts` → `reality-opts.xxx` 点号键 → 平铺 `snake_case` → 平铺 `camelCase` → 本地 `REALITYConfigs` → 内置默认值。面板只下发部分字段时，其余自动回退。
* 兼容各面板不一致的写法，例如 `"enable_reality": "true"`（字符串）、`"reality-opts.private_key"`（点号键）、`private_key`（平铺 snake_case）。
* `privateKey` 解码后须为 32 字节；`dest` 未下发时用 `sni + ":443"`；`shortIds` 未下发时使用内置默认值 `["", "0123456789abcdef"]`（xray 要求该项非空）。

### XHTTP

* 支持 `network: xhttp`（等同 `splithttp`），`path`、`host`、`mode` 均可由面板下发。
* `mode` 支持 `auto` / `packet-up` / `stream-up` / `stream-one`，留空时使用 xray 默认的 `auto`。
* 服务端 `host` 留空即不校验 Host 头；非空时与请求 Host 精确匹配（大小写不敏感、忽略端口）。REALITY 场景建议留空或与 SNI 一致。

### X25519MLKEM768（后量子密钥交换）

* REALITY 的 TLS 1.3 握手支持 X25519MLKEM768 混合后量子密钥交换，用于抗「先存后破」（harvest now, decrypt later）。
* **服务端自动支持，无需任何配置**；是否协商由客户端 ClientHello（uTLS 指纹）决定，服务端跟随。
* 在客户端开启 REALITY 的 `show` 可确认是否生效，日志会打印：
  `REALITY localAddr: ... is using X25519MLKEM768 for TLS' communication: true`

### ML-DSA-65（后量子签名）

* REALITY 支持用 ML-DSA-65 对服务端证书做额外签名校验，用于抵抗未来量子计算机伪造 REALITY 认证。
* 服务端使用 `mldsa65Seed`，客户端使用配对的 `mldsa65Verify`。
* `mldsa65Seed` 由 `XrayR mldsa65` 生成（32 字节 `base64.RawURLEncoding`），且**必须与 `privateKey` 不同**，否则 xray 拒绝启动。
* 客户端未配置 `mldsa65Verify` 时连接仍可建立，只是不做额外校验。
* 在客户端开启 REALITY 的 `show` 可确认是否生效，日志会打印：
  `REALITY localAddr: ... is using ML-DSA-65 for cert's extra verification: true`
* 管理脚本菜单 `14` / `15` 可直接生成 x25519 与 ML-DSA-65 密钥对（回车随机生成，或粘贴已有私钥 / seed 反推另一半）。

## 功能介绍

| 功能        | v2ray | trojan | shadowsocks |
|-----------|-------|--------|-------------|
| 获取节点信息    | √     | √      | √           |
| 获取用户信息    | √     | √      | √           |
| 用户流量统计    | √     | √      | √           |
| 服务器信息上报   | √     | √      | √           |
| 自动申请tls证书 | √     | √      | √           |
| 自动续签tls证书 | √     | √      | √           |
| 在线人数统计    | √     | √      | √           |
| 在线用户限制    | √     | √      | √           |
| 审计规则      | √     | √      | √           |
| 节点端口限速    | √     | √      | √           |
| 按照用户限速    | √     | √      | √           |
| 自定义DNS    | √     | √      | √           |

## 支持前端

| 前端                                                     | v2ray | trojan | shadowsocks             |
|--------------------------------------------------------|-------|--------|-------------------------|
| sspanel-uim                                            | √     | √      | √ (单端口多用户和V2ray-Plugin) |

## 软件安装

### 一键安装

```bash
bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/install.sh)
```

### 使用Docker部署软件

[Docker部署教程](https://ryanraw.github.io/XrayR_For_SSpanel-uim/xrayr-xia-zai-he-an-zhuang/install/docker)

### 手动安装

[手动安装教程](https://ryanraw.github.io/XrayR_For_SSpanel-uim/xrayr-xia-zai-he-an-zhuang/install/manual)

## 配置文件及详细使用教程

[详细使用教程](https://ryanraw.github.io/XrayR_For_SSpanel-uim/)

## Thanks

* [Project X](https://github.com/XTLS/)
* [V2Fly](https://github.com/v2fly)
* [VNet-V2ray](https://github.com/ProxyPanel/VNet-V2ray)
* [Air-Universe](https://github.com/crossfw/Air-Universe)
* [XrayR-project/XrayR](https://github.com/XrayR-project/XrayR) — 上游项目

## Licence

[Mozilla Public License Version 2.0](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/blob/master/LICENSE)

## Telgram

[XrayR后端讨论](https://t.me/XrayR_project)

[XrayR通知](https://t.me/XrayR_channel)

## Stargazers over time

[![Stargazers over time](https://starchart.cc/XrayR-project/XrayR.svg)](https://starchart.cc/XrayR-project/XrayR)
