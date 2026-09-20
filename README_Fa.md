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

آموزش：[اموزش با جزئیات](https://ryanraw.github.io/XrayR_For_SSpanel-uim/)

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
* پشتیبانی از REALITY، XHTTP و ویژگی‌های پساکوانتومی (X25519MLKEM768، ML-DSA-65).

## پروتکل‌های انتقال و رمزنگاری

### REALITY

* پشتیبانی از `security: reality` (VLESS / Trojan). پارامترهای سمت سرور **می‌توانند توسط پنل ارسال شوند** یا به‌صورت محلی در `REALITYConfigs` فایل `config.yml` نوشته شوند.
* ترتیب اولویت: `reality-opts` پنل → کلیدهای نقطه‌ای `reality-opts.xxx` → `snake_case` مسطح → `camelCase` مسطح → `REALITYConfigs` محلی → مقادیر پیش‌فرض داخلی. فیلدهایی که پنل ارسال نکند به‌صورت خودکار جایگزین می‌شوند.
* سازگار با نوشتارهای مختلف پنل، مثلاً `"enable_reality": "true"` (رشته)، `"reality-opts.private_key"` (کلید نقطه‌ای)، `private_key` (snake_case مسطح).
* `privateKey` باید پس از رمزگشایی ۳۲ بایت باشد؛ اگر `dest` ارسال نشود از `sni + ":443"` استفاده می‌شود؛ اگر `shortIds` ارسال نشود مقدار پیش‌فرض داخلی `["", "0123456789abcdef"]` به کار می‌رود (xray خالی بودن آن را نمی‌پذیرد).

### XHTTP

* پشتیبانی از `network: xhttp` (معادل `splithttp`)؛ `path`، `host` و `mode` همگی می‌توانند توسط پنل ارسال شوند.
* مقدار `mode` می‌تواند `auto` / `packet-up` / `stream-up` / `stream-one` باشد؛ در صورت خالی بودن مقدار پیش‌فرض `auto` در xray استفاده می‌شود.
* اگر `host` سمت سرور خالی باشد، هدر Host بررسی نمی‌شود؛ در غیر این صورت باید دقیقاً با Host درخواست مطابقت داشته باشد (بدون حساسیت به بزرگی و کوچکی حروف، بدون در نظر گرفتن پورت). برای REALITY بهتر است خالی یا برابر SNI باشد.

### X25519MLKEM768 (تبادل کلید پساکوانتومی)

* دست‌دادن TLS 1.3 در REALITY از تبادل کلید پساکوانتومی ترکیبی X25519MLKEM768 پشتیبانی می‌کند و در برابر حمله «ابتدا ذخیره، بعداً رمزگشایی» مقاوم است.
* **سرور به‌صورت خودکار پشتیبانی می‌کند و نیازی به تنظیمات نیست**؛ اینکه از آن استفاده شود یا نه به ClientHello کلاینت (اثر انگشت uTLS) بستگی دارد و سرور تبعیت می‌کند.
* برای اطمینان، `show` را در سمت کلاینت فعال کنید؛ لاگ چاپ می‌کند:
  `REALITY localAddr: ... is using X25519MLKEM768 for TLS' communication: true`

### ML-DSA-65 (امضای پساکوانتومی)

* REALITY می‌تواند با ML-DSA-65 یک بررسی امضای اضافی روی گواهی سرور انجام دهد تا در برابر جعل احراز هویت REALITY توسط رایانه‌های کوانتومی آینده مقاوم باشد.
* سرور از `mldsa65Seed` و کلاینت از `mldsa65Verify` متناظر استفاده می‌کند.
* `mldsa65Seed` با `XrayR mldsa65` تولید می‌شود (۳۲ بایت، `base64.RawURLEncoding`) و **باید با `privateKey` متفاوت باشد**، در غیر این صورت xray از راه‌اندازی خودداری می‌کند.
* اگر کلاینت `mldsa65Verify` را تنظیم نکرده باشد، اتصال همچنان برقرار می‌شود و فقط بررسی اضافی انجام نمی‌شود.
* برای اطمینان، `show` را در سمت کلاینت فعال کنید؛ لاگ چاپ می‌کند:
  `REALITY localAddr: ... is using ML-DSA-65 for cert's extra verification: true`
* منوی اسکریپت مدیریت `14` / `15` جفت کلید x25519 و ML-DSA-65 را تولید می‌کند (Enter برای تولید تصادفی، یا چسباندن کلید خصوصی / seed موجود برای استخراج نیمه دیگر).

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

## نصب نرم افزار

### نصب بصورت یکپارچه

```
bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/install.sh)
```

### استقرار نرم افزار با استفاده از Docker

[آموزش استقرار داکر](https://ryanraw.github.io/XrayR_For_SSpanel-uim/xrayr-xia-zai-he-an-zhuang/install/docker)

### نصب دستی

[آموزش نصب دستی](https://ryanraw.github.io/XrayR_For_SSpanel-uim/xrayr-xia-zai-he-an-zhuang/install/manual)

## فایل های پیکربندی و آموزش های با جرئیات

[آموزش مفصل](https://ryanraw.github.io/XrayR_For_SSpanel-uim/)

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
