# 使用一键脚本安装

## 软件安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/XrayR-project/XrayR-release/master/install.sh)
```

配置文件路径：`/etc/XrayR` 配置文件详见：[配置文件说明](../../xrayr-pei-zhi-wen-jian-shuo-ming/config.md)

## 软件更新

```bash
XrayR update
```

## 搭伪装站（XHTTP + CDN）

套 CDN 的节点可以一键装一个 AList 只读文件站当门面，并把管理入口收进 IP 白名单：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/RyanRaw/XrayR_For_SSpanel-uim/master/install/install.sh) mask \
  --domain ro.example.com --path /steam --upstream 127.0.0.1:21074
```

参数与加固细节见 [AList 伪装站 + 反代加固](../../gong-neng-shuo-ming/alist-mask.md)。

