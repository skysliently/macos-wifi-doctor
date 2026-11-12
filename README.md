# macos-wifi-doctor

> macOS Wi-Fi 信号质量快测工具 —— 只读、无 sudo、单文件 bash 脚本,全程约 1.5 分钟出结论。

macos-wifi-doctor 按四级链路层次诊断当前 Wi-Fi 连接质量,直接给出「信号差 / 干扰重 / 链路层问题 / 出口带宽问题」的结论,而不是甩给你一堆原始数据。

```
射频层(RSSI/SNR/信道/干扰) → 链路层(波动/掉值) → 网络层(丢包/延迟/DNS) → 结论与建议
```

## 特性

- **零依赖**:只用 macOS 自带的 `system_profiler` / `ping` / `dig` / `awk`,不需要 sudo,不需要 Homebrew
- **五步快测**:链路快照、RSSI 连续采样、网关连通性、公网连通性、DNS 耗时,一次跑完
- **懂行的判断**:
  - 网关禁 ping(不响应 ICMP)时自动改用 ARP 表确认二层连通,不会误报「链路故障」
  - 网关与公网结果对照,区分「WiFi 的问题」还是「运营商的问题」
  - 大包(1200B)探测,更容易暴露无线层丢包
- **隐私友好**:`--mask` 一键隐藏 SSID,贴 issue / 分享截图不泄露网络名
- **实测环境**:macOS 26 (darwin 25, Apple Silicon);老版 macOS 的 `system_profiler` 输出字段历史上稳定,但以实测版本为准

## 快速开始

```bash
git clone https://github.com/skysliently/macos-wifi-doctor.git
cd macos-wifi-doctor
bash macos-wifi-doctor.sh
```

或直接下载 [macos-wifi-doctor.sh](macos-wifi-doctor.sh) 单文件使用。

## 用法

```
bash macos-wifi-doctor.sh [--mask] [-h|--help] [-V|--version] [采样次数] [每项ping次数] [公网目标]
```

| 参数 | 默认 | 说明 |
|---|---|---|
| 采样次数 | 10 | RSSI 连续采样次数,每 2 秒一次 |
| 每项ping次数 | 20 | ping 网关与公网的次数 |
| 公网目标 | 223.5.5.5 | 海外用户建议传 `1.1.1.1` |
| `--mask` | — | 输出中隐藏 SSID |

示例:

```bash
bash macos-wifi-doctor.sh                 # 全默认,约 1.5 分钟
bash macos-wifi-doctor.sh 20 50 1.1.1.1   # 采样 20 次、ping 50 次、目标 1.1.1.1
bash macos-wifi-doctor.sh --mask          # 隐藏 SSID
```

## 示例输出

```text
macos-wifi-doctor v1.0.0 —— Wi-Fi 信号质量快测  2026-11-12 10:00:00
----------------------------------------------------------------
[1/5] 链路快照(system_profiler,几秒钟)…
SSID / 信道 / PHY        HomeWiFi | ch36 | 802.11ax
RSSI(信号强度)         -38 dBm —— 优秀
Noise(底噪)              -92 dBm
SNR(信噪比)             54 dB —— 优秀
协商速率 / MCS         1200 Mbps | MCS 11
周边可见 AP            共 15 个,同信道(ch36) 1 个 

[2/5] RSSI 连续采样 × 10(每 2 秒一次,勿移动电脑)…
..........
RSSI 采样(均值/最差) -37.7 dBm / -41 dBm —— 稳定

[3/5] ping 网关 × 20(网关: 192.168.85.232)…
网关丢包/延迟        丢包 100.0%(网关不响应 ICMP)—— 网关禁 ping(ARP 表有网关 MAC,二层连通正常),以公网结果为准

[4/5] ping 公网 × 20(223.5.5.5,含大包 ×15)…
公网丢包/延迟        丢包 0.0% | 平均 28.357ms / 最大 76.629ms / 抖动 10.521ms —— 正常
大包(1200B)丢包        0.0% —— 正常

[5/5] DNS 解析耗时…
DNS 平均解析           0 ms —— 优秀

----------------------------------------------------------------
结论与建议:
- 信号水平: RSSI -38 dBm / SNR 54 dB → 优秀
- 无线本地段: 网关禁 ping(ARP 表有网关 MAC,二层连通正常),以公网结果为准
- 出口网络: 正常(公网平均 28.357 ms)
- 提示: 实际吞吐测试需局域网 iperf3(真实 Wi-Fi 能力);更详细诊断可用 sudo wdutil info
```

## 判读基准

### RSSI(信号强度,越接近 0 越强)

| RSSI | SNR(RSSI − Noise) | 评价 |
|---|---|---|
| ≥ −50 dBm | ≥ 40 dB | 优秀,可跑满高带宽 |
| −51 ~ −67 dBm | 25 ~ 40 dB | 良好 |
| −68 ~ −75 dBm | < 25 dB | 一般,高吞吐会受损 |
| < −75 dBm | — | 差,建议挪近路由器 |

### 网络层

| 指标 | 优秀 | 可接受 | 有问题 |
|---|---|---|---|
| 网关/公网丢包 | 0% | < 1%(偶发) | ≥ 2% |
| 网关平均延迟 | ≤ 5 ms | ≤ 20 ms | > 30 ms 或抖动大 |
| DNS 解析 | ≤ 20 ms | ≤ 50 ms | > 50 ms |

### 稳定性

- RSSI 采样极差(最大−最小)≥ 8 dB → 波动明显,检查走动、遮挡与干扰源
- 采样出现 < −70 dBm 的掉值 → 位置边缘化
- 协商速率明显低于路由器能力(MCS 低)→ 信号或干扰拖了后腿

## 工作原理

1. **链路快照**:`system_profiler SPAirPortDataType` 读取当前网络的 RSSI/Noise/信道/MCS 与周边 AP 列表(旧版 macOS 的 `airport -I` 命令在 macOS 15+ 已移除,本工具不依赖它)
2. **连续采样**:循环抓取 RSSI,统计均值/极差/掉值——快照值会骗人,波动才暴露问题
3. **ping 网关**:只经过「本机 ↔ 路由器」无线段,是纯 WiFi 质量;若网关 100% 不回 ping,用 `arp -n` 确认二层连通(很多路由器禁 ICMP)
4. **ping 公网 + 大包探测**:与网关结果对照定位问题在无线段还是出口;1200 字节大包更容易暴露无线层丢包
5. **DNS 解析**:三个域名取平均

## FAQ

**网关 ping 100% 丢包,是不是 WiFi 坏了?**
不一定。很多路由器默认不响应 ICMP。脚本会查 ARP 表:有网关 MAC 说明二层连通正常,此时以公网结果为准;ARP 都没有才是真的链路问题。

**怎么测真实吞吐?**
本工具不含吞吐测试(需要第二台设备)。局域网跑 `iperf3 -s`,本机跑 `iperf3 -c <IP> -t 10`;实际吞吐达到协商速率(TX Rate)的 50~60% 以上算正常。

**想看更底层的诊断?**
`sudo wdutil info`(RSSI、信道带宽、漫游记录)或按住 Option 点击菜单栏 Wi-Fi 图标。

** VPN / 有线网络下能用吗?**
能跑,但 ping 网关一步可能取不到默认网关(VPN 接管路由),脚本会标注跳过;有线主用时测的是有线而非 WiFi,解读时注意。

## 已知边界 / Roadmap

- [ ] 不含吞吐测试(见 FAQ,依赖局域网 iperf3 服务端)
- [ ] JSON 输出(便于脚本化采集)
- [ ] 多 Wi-Fi 接口支持(目前取系统默认)
- [ ] 持续监测模式(如每 30 分钟记录一次)

欢迎 PR。提 issue 时请用 `--mask` 运行并附完整输出。

## License

[MIT](LICENSE)
