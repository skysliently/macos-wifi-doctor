# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-11-12

### Added
- 五步快测:链路快照、RSSI 连续采样、网关连通性、公网连通性(含大包探测)、DNS 耗时
- 网关禁 ping 时自动用 ARP 表确认二层连通,避免误报链路故障
- `--mask` SSID 脱敏、`-h/--help`、`-V/--version`
- 子进程 locale 归一化,避免本地化输出破坏解析
- 非 macOS 平台守卫与参数校验
