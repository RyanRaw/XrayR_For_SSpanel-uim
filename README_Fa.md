# XrayR — نسخه سازگار با SSPanel-UIM

[![](https://img.shields.io/badge/TgChat-@XrayR讨论-blue.svg)](https://t.me/XrayR_project)
[![](https://img.shields.io/badge/Channel-@XrayR通知-blue.svg)](https://t.me/XrayR_channel)
![](https://img.shields.io/github/stars/RyanRaw/XrayR_For_SSpanel-uim)
![](https://img.shields.io/github/forks/RyanRaw/XrayR_For_SSpanel-uim)
![](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/actions/workflows/release.yml/badge.svg)
![](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/actions/workflows/docker.yml/badge.svg)
[![Github All Releases](https://img.shields.io/github/downloads/RyanRaw/XrayR_For_SSpanel-uim/total.svg)]()

[English(en) README](README-en.md) | [Vietnamese(vi) README](README-vi.md) | [Chinese(zh) README](README.md)

یک فریمورک بک اند مبتنی بر xray که از چند از پنل پشتیبانی می کند

یک چارچوب بک‌اند مبتنی بر Xray که از پروتکل‌های V2ay، Trojan و Shadowsocks پشتیبانی می‌کند، به راحتی قابل گسترش است و از اتصال چند پنل پشتیبانی می‌کند.

**این پروژه یک فورک از [XrayR-project/XrayR](https://github.com/XrayR-project/XrayR) است که عمدتاً برای SSPanel-UIM تطبیق داده شده است.**

اگر این پروژه را دوست دارید، می توانید با کلیک بر روی ستاره+ساعت در گوشه بالا سمت راست به ادامه روند پیشرفت این پروژه توجه کنید.

آموزش：[اموزش با جزئیات](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/wiki)

## سلب مسئولیت

این پروژه فقط مطالعه، توسعه و نگهداری شخصی من است. من هیچ گونه قابلیت استفاده را تضمین نمی کنم و مسئولیتی در قبال عواقب ناشی از استفاده از این نرم افزار ندارم.
## امکانات

* منبع باز دائمی و رایگان
* پشتیبانی از چندین پروتکل V2ray، Trojan، Shadowsocks.
* پشتیبانی از ویژگی های جدید مانند Vless و XTLS.
* پشتیبانی از اتصال یک نمونه چند پانل، چند گره، بدون نیاز به شروع مکرر.
* پشتیبانی محدود IP آنلاین
* پشتیبانی از سطح پورت گره، محدودیت سرعت سطح کاربر.
* پیکربندی ساده و سرراست است.
* پیکربندی را تغییر دهید تا نمونه به طور خودکار راه اندازی مجدد شود.
* کامپایل و ارتقاء آن آسان است و می تواند به سرعت نسخه اصلی را به روز کند و از ویژگی های جدید Xray-core پشتیبانی می کند.

## امکانات

| امکانات        | v2ray | trojan | shadowsocks |
|-----------|-------|--------|-------------|
| اطلاعات گره را دریافت کنید    | √     | √      | √           |
| دریافت اطلاعات کاربر    | √     | √      | √           |
| آمار ترافیک کاربران    | √     | √      | √           |
| گزارش اطلاعات سرور   | √     | √      | √           |
| به طور خودکار برای گواهی tls درخواست دهید | √     | √      | √           |
| تمدید خودکار گواهی tls | √     | √      | √           |
| آمار آنلاین    | √     | √      | √           |
| محدودیت کاربر آنلاین    | √     | √      | √           |
| قوانین حسابرسی      | √     | √      | √           |
| محدودیت سرعت پورت گره    | √     | √      | √           |
| محدودیت سرعت بر اساس کاربر    | √     | √      | √           |
| DNS سفارشی    | √     | √      | √           |

## پشتیبانی از قسمت فرانت

| قسمت فرانت                                                     | v2ray | trojan | shadowsocks             |
|--------------------------------------------------------|-------|--------|-------------------------|
| sspanel-uim                                            | √     | √      | √ (تک پورت چند کاربره و V2ray-Plugin) |
| v2board                                                | √     | √      | √                       |
| [PMPanel](https://github.com/ByteInternetHK/PMPanel)   | √     | √      | √                       |
| [ProxyPanel](https://github.com/ProxyPanel/ProxyPanel) | √     | √      | √                       |
| [WHMCS (V2RaySocks)](https://v2raysocks.doxtex.com/)   | √     | √      | √                       |
| [BunPanel](https://github.com/pennyMorant/bunpanel-release)   | √     | √      | √                       |

## نصب نرم افزار

### نصب بصورت یکپارچه

```
bash <(curl -Ls https://raw.githubusercontent.com/RyanRaw/XrayR_For_SSpanel-uim/master/install/install.sh)
```

### استقرار نرم افزار با استفاده از Docker

[آموزش استقرار داکر](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/wiki)

### نصب دستی

[آموزش نصب دستی](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/wiki)

## فایل های پیکربندی و آموزش های با جرئیات

[آموزش مفصل](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/wiki)

## Thanks

* [Project X](https://github.com/XTLS/)
* [V2Fly](https://github.com/v2fly)
* [VNet-V2ray](https://github.com/ProxyPanel/VNet-V2ray)
* [Air-Universe](https://github.com/crossfw/Air-Universe)
* [XrayR-project/XrayR](https://github.com/XrayR-project/XrayR) — پروژه بالادستی

## Licence

[Mozilla Public License Version 2.0](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/blob/master/LICENSE)

## Telgram

[بحث در مورد XrayR Backend](https://t.me/XrayR_project)

[کانال اعلان در مورد XrayR](https://t.me/XrayR_channel)

## Stargazers over time

[![Stargazers over time](https://starchart.cc/XrayR-project/XrayR.svg)](https://starchart.cc/XrayR-project/XrayR)
