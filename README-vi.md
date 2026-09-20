# XrayR — Phiên bản tương thích SSPanel-UIM

[![](https://img.shields.io/badge/TgChat-@XrayR讨论-blue.svg)](https://t.me/XrayR_project)
[![](https://img.shields.io/badge/Channel-@XrayR通知-blue.svg)](https://t.me/XrayR_channel)
![](https://img.shields.io/github/stars/RyanRaw/XrayR_For_SSpanel-uim)
![](https://img.shields.io/github/forks/RyanRaw/XrayR_For_SSpanel-uim)
![](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/actions/workflows/release.yml/badge.svg)
![](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/actions/workflows/docker.yml/badge.svg)
[![Github All Releases](https://img.shields.io/github/downloads/RyanRaw/XrayR_For_SSpanel-uim/total.svg)]()

[Iranian(farsi) README](README_Fa.md) | [English(en) README](README-en.md) | [Chinese(zh) README](README.md)

A Xray backend framework that can easily support many panels.

Khung trở lại dựa trên XRay hỗ trợ các giao thức V2ay, Trojan, Shadowsocks, dễ dàng mở rộng và hỗ trợ kết nối nhiều người.

**Dự án này là một fork của [XrayR-project/XrayR](https://github.com/XrayR-project/XrayR), được điều chỉnh chủ yếu cho SSPanel-UIM.**

Nếu bạn thích dự án này, bạn có thể nhấp vào Star+Watch ở góc trên bên phải để tiếp tục chú ý đến tiến trình của dự án này.

## Tài liệu
Sử dụng hướng dẫn: [Hướng dẫn chi tiết](https://ryanraw.github.io/XrayR_For_SSpanel-uim/) ( Tiếng Trung )

## Tuyên bố miễn trừ

Dự án này chỉ là học tập và phát triển và bảo trì cá nhân của tôi. Tôi không đảm bảo bất kỳ sự sẵn có nào và không chịu trách nhiệm cho bất kỳ hậu quả nào do việc sử dụng phần mềm này.

## Đặt điểm nổi bật

* Nguồn mở vĩnh viễn và miễn phí.
* Hỗ trợ V2Ray, Trojan, Shadowsocks nhiều giao thức.
* Hỗ trợ các tính năng mới như Vless và XTL.
* Hỗ trợ trường hợp đơn lẻ kết nối Multi -Panel và Multi -Node, không cần phải bắt đầu nhiều lần.
* Hỗ trợ hạn chế IP trực tuyến
* Hỗ trợ cấp cổng nút và giới hạn tốc độ cấp người dùng.
* Cấu hình đơn giản và rõ ràng.
* Sửa đổi phiên bản khởi động lại tự động.
* Dễ dàng biên dịch và nâng cấp, bạn có thể nhanh chóng cập nhật phiên bản cốt lõi và hỗ trợ các tính năng mới của Xray-Core.
* Hỗ trợ REALITY, XHTTP và các tính năng hậu lượng tử (X25519MLKEM768, ML-DSA-65).

## Giao thức truyền tải và mã hóa

### REALITY

* Hỗ trợ `security: reality` (VLESS / Trojan). Các tham số phía máy chủ **có thể được panel gửi xuống**, hoặc ghi cục bộ trong `REALITYConfigs` của `config.yml`.
* Thứ tự ưu tiên: panel `reality-opts` → khóa dạng chấm `reality-opts.xxx` → `snake_case` phẳng → `camelCase` phẳng → `REALITYConfigs` cục bộ → giá trị mặc định có sẵn. Trường nào panel không gửi sẽ tự động được thay thế.
* Tương thích với nhiều cách viết khác nhau của panel, ví dụ `"enable_reality": "true"` (chuỗi), `"reality-opts.private_key"` (khóa dạng chấm), `private_key` (snake_case phẳng).
* `privateKey` phải giải mã thành 32 byte; nếu không có `dest` sẽ dùng `sni + ":443"`; nếu không có `shortIds` sẽ dùng giá trị mặc định `["", "0123456789abcdef"]` (xray yêu cầu trường này không được rỗng).

### XHTTP

* Hỗ trợ `network: xhttp` (tương đương `splithttp`); `path`, `host`, `mode` đều có thể do panel gửi xuống.
* `mode` hỗ trợ `auto` / `packet-up` / `stream-up` / `stream-one`; nếu để trống sẽ dùng mặc định `auto` của xray.
* `host` phía máy chủ để trống thì không kiểm tra Host header; nếu có giá trị thì phải khớp chính xác với Host của request (không phân biệt hoa thường, bỏ qua cổng). Với REALITY nên để trống hoặc bằng SNI.

### X25519MLKEM768 (trao đổi khóa hậu lượng tử)

* Bắt tay TLS 1.3 của REALITY hỗ trợ trao đổi khóa hậu lượng tử lai X25519MLKEM768, chống lại kiểu tấn công "thu thập trước, giải mã sau".
* **Máy chủ hỗ trợ tự động, không cần cấu hình**; việc có thương lượng hay không do ClientHello (vân tay uTLS) của client quyết định, máy chủ đi theo.
* Bật `show` ở phía client để xác nhận — log sẽ in:
  `REALITY localAddr: ... is using X25519MLKEM768 for TLS' communication: true`

### ML-DSA-65 (chữ ký hậu lượng tử)

* REALITY có thể dùng ML-DSA-65 để kiểm tra chữ ký bổ sung cho chứng chỉ máy chủ, chống lại việc máy tính lượng tử trong tương lai giả mạo xác thực REALITY.
* Máy chủ dùng `mldsa65Seed`, client dùng `mldsa65Verify` tương ứng.
* `mldsa65Seed` được tạo bằng `XrayR mldsa65` (32 byte, `base64.RawURLEncoding`) và **phải khác `privateKey`**, nếu không xray sẽ từ chối khởi động.
* Nếu client không cấu hình `mldsa65Verify` thì kết nối vẫn thiết lập được, chỉ là không có kiểm tra bổ sung.
* Bật `show` ở phía client để xác nhận — log sẽ in:
  `REALITY localAddr: ... is using ML-DSA-65 for cert's extra verification: true`
* Menu script quản lý `14` / `15` tạo trực tiếp cặp khóa x25519 và ML-DSA-65 (nhấn Enter để tạo ngẫu nhiên, hoặc dán khóa riêng / seed có sẵn để suy ra nửa còn lại).

## Chức năng

| Chức năng        | v2ray | trojan | shadowsocks |
|-----------|-------|--------|-------------|
| Nhận thông tin Node    | √     | √      | √           |
| Nhận thông tin người dùng    | √     | √      | √           |
| Thống kê lưu lượng người dùng    | √     | √      | √           |
| Báo cáo thông tin máy chủ   | √     | √      | √           |
| Tự động đăng ký chứng chỉ TLS | √     | √      | √           |
| Chứng chỉ TLS gia hạn tự động | √     | √      | √           |
| Số người trực tuyến    | √     | √      | √           |
| Hạn chế người dùng trực tuyến    | √     | √      | √           |
| Quy tắc kiểm toán      | √     | √      | √           |
| Giới hạn tốc độ cổng nút    | √     | √      | √           |
| Theo giới hạn tốc độ người dùng    | √     | √      | √           |
| DNS tùy chỉnh    | √     | √      | √           |

## Hỗ trợ Panel 

| Panel                                                     | v2ray | trojan | shadowsocks             |
|--------------------------------------------------------|-------|--------|-------------------------|
| sspanel-uim                                            | √     | √      | √ (Nhiều người dùng cuối và v2ray-plugin) |

## Cài đặt phần mềm

### Một cài đặt chính

```bash
bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/install.sh)
```

### Sử dụng phần mềm triển khai Docker

[Hướng dẫn cài đặt thông qua Docker](https://ryanraw.github.io/XrayR_For_SSpanel-uim/xrayr-xia-zai-he-an-zhuang/install/docker)

### Hướng dẫn cài đặt

[Hướng dẫn cài đặt thủ công](https://ryanraw.github.io/XrayR_For_SSpanel-uim/xrayr-xia-zai-he-an-zhuang/install/manual)

## Tệp cấu hình và hướng dẫn sử dụng chi tiết

[Hướng dẫn chi tiết](https://ryanraw.github.io/XrayR_For_SSpanel-uim/)

## Thanks

* [Project X](https://github.com/XTLS/)
* [V2Fly](https://github.com/v2fly)
* [VNet-V2ray](https://github.com/ProxyPanel/VNet-V2ray)
* [Air-Universe](https://github.com/crossfw/Air-Universe)
* [XrayR-project/XrayR](https://github.com/XrayR-project/XrayR) — dự án thượng nguồn

## Licence

[Mozilla Public License Version 2.0](https://github.com/RyanRaw/XrayR_For_SSpanel-uim/blob/master/LICENSE)

## Telgram

[Xrayr Back-end Thảo luận](https://t.me/XrayR_project)

[Thông báo Xrayr](https://t.me/XrayR_channel)

## Stargazers over time

[![Stargazers over time](https://starchart.cc/XrayR-project/XrayR.svg)](https://starchart.cc/XrayR-project/XrayR)
