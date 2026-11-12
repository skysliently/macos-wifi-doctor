#!/usr/bin/env bash
# macos-wifi-doctor —— macOS Wi-Fi 信号质量快测工具
# 只读诊断:无 sudo、不修改系统设置、不向网络写入任何数据。
# 实测环境:macOS 26 (darwin 25, Apple Silicon);依赖系统自带 bash 3.2+。
# 许可:MIT,详见 LICENSE。

set -u

VERSION="1.0.0"
WAN_DEFAULT="223.5.5.5"   # 默认公网目标(国内可达的公共 DNS);海外用户建议传 1.1.1.1
SAMPLE_INTERVAL=2         # RSSI 采样间隔(秒)

usage() {
cat <<EOF
macos-wifi-doctor v${VERSION} —— macOS Wi-Fi 信号质量快测(只读、无需 sudo)

用法:
  bash macos-wifi-doctor.sh [选项] [采样次数] [每项ping次数] [公网目标]

位置参数(均可省略):
  采样次数       RSSI 连续采样次数,默认 10(每 ${SAMPLE_INTERVAL} 秒一次)
  每项ping次数   ping 网关与公网的次数,默认 20
  公网目标       ping 的公网地址,默认 ${WAN_DEFAULT}(海外用户建议 1.1.1.1)

选项:
  --mask         在输出中隐藏 SSID(贴 issue / 分享截图时使用)
  -h, --help     显示本帮助
  -V, --version  显示版本号

示例:
  bash macos-wifi-doctor.sh                 # 默认参数,全程约 1.5 分钟
  bash macos-wifi-doctor.sh 20 50 1.1.1.1   # 采样 20 次、ping 50 次、公网目标 1.1.1.1
  bash macos-wifi-doctor.sh --mask          # 隐藏 SSID

判读基准(RSSI/SNR/丢包/延迟阈值)见 README.md。
EOF
}

# ---------- 前置检查 ----------
if [ "$(uname -s)" != "Darwin" ]; then
  echo "错误: macos-wifi-doctor 仅支持 macOS(依赖 system_profiler SPAirPortDataType 与 BSD ping)" >&2
  exit 1
fi

# 归一化子进程输出语言,避免部分系统 locale 下 ping 等输出被本地化导致解析失败
export LC_ALL=en_US.UTF-8

# ---------- 参数解析 ----------
MASK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --mask)        MASK=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    -V|--version)  echo "macos-wifi-doctor v${VERSION}"; exit 0 ;;
    --)            shift; break ;;
    -*)            echo "未知选项: $1(用 -h 查看帮助)"; exit 2 ;;
    *)             break ;;
  esac
done

SAMPLES=${1:-10}
PINGN=${2:-20}
WAN=${3:-$WAN_DEFAULT}

case "$SAMPLES" in ''|*[!0-9]*) echo "错误: 采样次数须为正整数" >&2; exit 2 ;; esac
case "$PINGN"   in ''|*[!0-9]*) echo "错误: ping 次数须为正整数"   >&2; exit 2 ;; esac

hr() { printf '%s\n' "----------------------------------------------------------------"; }
fmt() { printf '%-26s %s\n' "$1" "$2"; }

echo "macos-wifi-doctor v${VERSION} —— Wi-Fi 信号质量快测  $(date '+%Y-%m-%d %H:%M:%S')"
hr

# ---------- 1. 链路快照 ----------
echo "[1/5] 链路快照(system_profiler,几秒钟)…"
INFO=$(system_profiler SPAirPortDataType 2>/dev/null)
CUR=$(printf '%s\n' "$INFO" | awk '/Current Network Information:/{f=1;next} /Other Local Wi-Fi Networks:/{f=0} f')
SSID=$(printf '%s\n' "$CUR" | head -n1 | sed -E 's/^ *//; s/:$//')
PHY=$(printf '%s\n' "$CUR" | awk -F': *' '/PHY Mode/{print $2; exit}')
CHN=$(printf '%s\n' "$CUR" | awk '/^ *Channel:/{print $2; exit}')
SIG=$(printf '%s\n' "$CUR" | awk '/Signal \/ Noise:/{print $4; exit}')
NOISE=$(printf '%s\n' "$CUR" | awk '/Signal \/ Noise:/{print $7; exit}')
TXR=$(printf '%s\n' "$CUR" | awk '/Transmit Rate:/{print $NF; exit}')
MCS=$(printf '%s\n' "$CUR" | awk '/MCS Index:/{print $NF; exit}')

NEIGH=$(printf '%s\n' "$INFO" | awk '/Other Local Wi-Fi Networks:/{f=1;next} f' | sed -nE 's/.*Channel: *([0-9]+).*/\1/p')
NTOT=$(printf '%s\n' "$NEIGH" | grep -c . )
NSAME=$( [ -n "$CHN" ] && printf '%s\n' "$NEIGH" | grep -cx "$CHN" )

if [ -z "${SIG:-}" ]; then
  echo "✗ 未读到信号数据。请确认 Wi-Fi 已开启;若已开启,可能是 system_profiler 输出格式变化,"
  echo "  可改用手动方式: sudo wdutil info(或按住 Option 点击菜单栏 Wi-Fi 图标)"
  exit 1
fi
SNR=$((SIG - NOISE))

grade_rssi() {
  [ "$1" -ge -50 ] && { echo "优秀"; return; }
  [ "$1" -ge -67 ] && { echo "良好"; return; }
  [ "$1" -ge -75 ] && { echo "一般(高吞吐会受损)"; return; }
  echo "差(建议挪近路由器)"
}
grade_snr() {
  [ "$1" -ge 40 ] && { echo "优秀"; return; }
  [ "$1" -ge 25 ] && { echo "良好"; return; }
  echo "受干扰"
}

SHOW_SSID="$SSID"
[ "$MASK" = 1 ] && SHOW_SSID="***"
fmt "SSID / 信道 / PHY" "$SHOW_SSID | ch$CHN | $PHY"
fmt "RSSI(信号强度)" "$SIG dBm —— $(grade_rssi "$SIG")"
fmt "Noise(底噪)" "$NOISE dBm"
fmt "SNR(信噪比)" "$SNR dB —— $(grade_snr "$SNR")"
fmt "协商速率 / MCS" "$TXR Mbps | MCS ${MCS:-N/A}"
SAME_NOTE=""
[ "${NSAME:-0}" -ge 3 ] && SAME_NOTE="(同信道干扰明显,建议路由器换信道)"
fmt "周边可见 AP" "共 ${NTOT:-0} 个,同信道(ch$CHN) ${NSAME:-0} 个 ${SAME_NOTE}"

# ---------- 2. 连续采样 ----------
echo
echo "[2/5] RSSI 连续采样 × $SAMPLES(每 ${SAMPLE_INTERVAL} 秒一次,勿移动电脑)…"
vals=""
i=0
while [ "$i" -lt "$SAMPLES" ]; do
  out=$(system_profiler SPAirPortDataType 2>/dev/null)
  s=$(printf '%s\n' "$out" | awk '/Signal \/ Noise:/{print $4; exit}')
  vals="${vals}${s}\n"
  printf '.'
  i=$((i + 1))
  [ "$i" -lt "$SAMPLES" ] && sleep "$SAMPLE_INTERVAL"
done
echo
RSTAT=$(printf '%b' "$vals" | awk 'NF{n++;a[n]=$1; if(n==1){mn=$1;mx=$1} if($1<mn)mn=$1; if($1>mx)mx=$1; sum+=$1; if($1<-70)bad++} END{ if(n==0){print "NA NA NA NA 0"; exit} printf "%.1f %d %d %.1f %d", sum/n, mn, mx, mx-mn, bad+0}')
RMEAN=$(echo "$RSTAT" | awk '{print $1}')
RMIN=$(echo "$RSTAT" | awk '{print $2}')
RRANGE=$(echo "$RSTAT" | awk '{print $4}')
RBAD=$(echo "$RSTAT" | awk '{print $5}')

WOB="稳定"
if [ "$RMEAN" != "NA" ]; then
  awk -v r="$RRANGE" 'BEGIN{exit !(r+0>=8)}' && WOB="波动明显(极差 ${RRANGE} dB)"
  [ "${RBAD}" -gt 0 ] && WOB="出现 <-70dBm 掉值 ×$RBAD"
fi
fmt "RSSI 采样(均值/最差)" "$RMEAN dBm / $RMIN dBm —— $WOB"

# ---------- 3. ping 网关(纯无线段) ----------
GW=$(route -n get default 2>/dev/null | awk '/gateway/{print $2; exit}')
echo
echo "[3/5] ping 网关 × $PINGN(网关: ${GW:-未获取到})…"
WIRE_VERDICT="未知"
if [ -z "$GW" ]; then
  WIRE_VERDICT="未获取到默认网关(VPN/代理环境),跳过"
  fmt "网关连通性" "$WIRE_VERDICT"
else
  out=$(ping -c "$PINGN" -t 8 "$GW" 2>&1)
  loss=$(printf '%s\n' "$out" | sed -nE 's/.* ([0-9.]+)% packet loss.*/\1/p')
  rt=$(printf '%s\n' "$out" | sed -nE 's#.*= ([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+) ms.*#\1 \2 \3 \4#p')
  LAVG="—"; LMAX="—"; LJIT="—"
  if [ -n "$rt" ]; then
    LAVG=$(echo "$rt" | awk '{print $2}'); LMAX=$(echo "$rt" | awk '{print $3}'); LJIT=$(echo "$rt" | awk '{print $4}')
  fi
  lossnum=${loss:-100}
  if awk -v l="$lossnum" 'BEGIN{exit !(l+0>=99.9)}'; then
    # 网关不回 ping,用 ARP 表确认二层连通性
    gwmac=$(arp -n "$GW" 2>/dev/null | sed -nE 's/.* at ([^ ]+) on .*/\1/p' | head -n1)
    if [ -n "$gwmac" ] && [ "$gwmac" != "(incomplete)" ]; then
      WIRE_VERDICT="网关禁 ping(ARP 表有网关 MAC,二层连通正常),以公网结果为准"
    else
      WIRE_VERDICT="网关完全不可达,链路层有问题"
    fi
    fmt "网关丢包/延迟" "丢包 ${loss:-NA}%(网关不响应 ICMP)—— $WIRE_VERDICT"
  else
    LV=$(echo "$loss" | awk '{print ($1+0>2)?"异常(丢包)":($1+0>0)?"偶发丢包":"正常"}')
    if [ "$LV" = "正常" ] && [ "$LAVG" != "—" ]; then
      LV="$LV,延迟$(awk -v a="$LAVG" 'BEGIN{print (a<=5?"优秀":(a<=20?"正常":"偏高"))}')"
    fi
    WIRE_VERDICT="$LV"
    fmt "网关丢包/延迟" "丢包 ${loss:-NA}% | 平均 ${LAVG}ms / 最大 ${LMAX}ms / 抖动 ${LJIT}ms —— $LV"
  fi
fi

# ---------- 4. ping 公网(出口段) ----------
echo
echo "[4/5] ping 公网 × $PINGN($WAN,含大包 ×15)…"
out=$(ping -c "$PINGN" "$WAN" 2>&1)
loss=$(printf '%s\n' "$out" | sed -nE 's/.* ([0-9.]+)% packet loss.*/\1/p')
rt=$(printf '%s\n' "$out" | sed -nE 's#.*= ([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+) ms.*#\1 \2 \3 \4#p')
WAVG="—"; WMAX="—"; WJIT="—"
[ -n "$rt" ] && WAVG=$(echo "$rt" | awk '{print $2}') && WMAX=$(echo "$rt" | awk '{print $3}') && WJIT=$(echo "$rt" | awk '{print $4}')
WV=$(echo "${loss:-100}" | awk '{v=($1+0>2)?"异常(丢包)":($1+0>0)?"偶发丢包":"正常"; print v}')
fmt "公网丢包/延迟" "丢包 ${loss:-NA}% | 平均 ${WAVG}ms / 最大 ${WMAX}ms —— $WV"
big=$(ping -c 15 -s 1200 "$WAN" 2>&1)
bloss=$(printf '%s\n' "$big" | sed -nE 's/.* ([0-9.]+)% packet loss.*/\1/p')
BV=$(echo "${bloss:-100}" | awk '{v=($1+0>2)?"异常":($1+0>0)?"偶发丢包":"正常"; print v}')
fmt "大包(1200B)丢包" "${bloss:-NA}% —— $BV"

# ---------- 5. DNS ----------
echo
echo "[5/5] DNS 解析耗时…"
DT=0; DCNT=0
for h in www.baidu.com www.qq.com www.apple.com; do
  qt=$(dig +time=2 +tries=1 "$h" 2>/dev/null | awk -F'Query time: ' '/Query time/{split($2,a," "); print a[1]; exit}')
  [ -n "$qt" ] && { DT=$((DT+qt)); DCNT=$((DCNT+1)); }
done
[ "$DCNT" -gt 0 ] && DNSAVG=$((DT/DCNT)) || DNSAVG="N/A"
if [ "$DNSAVG" = "N/A" ]; then DV="未测得"; else DV=$(awk -v a="$DNSAVG" 'BEGIN{print (a<=20?"优秀":(a<=50?"正常":"偏慢"))}'); fi
fmt "DNS 平均解析" "${DNSAVG} ms —— $DV"

# ---------- 结论 ----------
echo; hr; echo "结论与建议:"
echo "- 信号水平: RSSI $SIG dBm / SNR $SNR dB → $(grade_rssi "$SIG")"
[ "${NSAME:-0}" -ge 3 ] && echo "- 干扰: 周边同信道 AP ${NSAME} 个 → 建议路由器端换信道(优先 5GHz 低占用信道)"
[ "$RMEAN" != "NA" ] && awk -v r="${RRANGE}" 'BEGIN{exit !(r+0>=8)}' && echo "- 稳定性: RSSI 极差 ${RRANGE} dB,波动明显"
[ "${RBAD:-0}" -gt 0 ] && echo "- 稳定性: 采样中出现 ${RBAD} 次 <-70dBm,注意位置/遮挡"
echo "- 无线本地段: $WIRE_VERDICT"
echo "- 出口网络: ${WV}(公网平均 ${WAVG} ms)"
echo "- 提示: 实际吞吐测试需局域网 iperf3(真实 Wi-Fi 能力);更详细诊断可用 sudo wdutil info"
