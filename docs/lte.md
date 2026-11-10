# 板载 LTE 模组（EM7565）实测

> English version: [lte.en.md](lte.en.md)

> 本机 DMI：`EDGE610VWL`（Verizon LTE 版），板载 Sierra Wireless EM7565。
> 实测日期 2026-11-09，OpenWrt 25.12.6，内核 6.12.112。

## 硬件

| 项目 | 值 |
| --- | --- |
| 模组 | Sierra Wireless **EM7565**（USB `1199:9091`，SN `UF04360020011048`） |
| 固件 | `SWI9X50C_01.11.00.00` GENERIC（2019-06-28） |
| IMEI | `353533101712019` |
| SIM 槽 | 两个 micro-SIM，**只有上方 SIM1 接到模组**（官方 QSG："Only use the upper SIM1 slot"） |
| 天线 | MAIN / AUX = LTE 主/副天线；**GPS = GNSS 天线**（QSG：GPS 天线可选） |
| AT 口 | USB 接口 1.3（`option` 驱动），115200 8N1；枚举顺序不固定，实测出现过 `ttyUSB1` 与 `ttyUSB2`，`modem-at` 自动探测 |
| QMI | USB 接口 1.8（`qmi_wwan` → `/dev/cdc-wdm0` + `wwan0`） |

USB 接口组成：1.0 = DM，1.2 = AT，1.3 = AT，1.8 = QMI（无 NMEA 接口）。

## 频段（官方 spec Table 1-1）

| 类型 | 支持频段 |
| --- | --- |
| LTE FDD | B1, B2, B3, B4, B5, B7, B8, B9, B12, B13, B18, B19, B20, B26, B28, B29(仅下行), B30(仅下行), B32, B66 |
| LTE TDD | **B41, B42, B43, B46, B48** |
| UMTS | B1, B2, B4, B5, B8 |
| GNSS | GPS, GLONASS, BeiDou, Galileo, QZSS |

**不支持 B38 / B39 / B40** —— 中国移动 TD-LTE 主力频段。

## 实测结果

| 卡 | 结果 |
| --- | --- |
| 中国联通（B1/B3） | ✅ 注册 LTE **B3 / 20 MHz**，PDP 建立，`ping 223.5.5.5` 通（32 ms） |
| 中国电信（B1/B3/B5） | 未实测，频段支持 |
| 中国移动 | ❌ 无法注册：B38/B39/B40 不支持；B8 能收到但极弱（RSSI -107 dBm）；扫描只能看到联通/电信 |

> 移动卡实测：SIM 能识别（IMSI `460022735937397`），能驻留 B3，但 `EMM: Deregistered / PLMN Search`，`AT+COPS=?` 扫描结果里没有 `CHN-MOBILE`。

## 必须做的 AT 配置

```text
AT!ENTERCND="A710"
AT!CUSTOM="SIMHOTSWAPDIS",1    # 关键：板的 SIM_DET 未接模组，不关热插拔会永远报 SIM not inserted
AT!CUSTOM="UIM2ENABLE",1       # 允许第二 SIM（配合 AT!UIMS 切换）
AT!UIMS=0                      # 使用 SIM1（上方槽）
AT!SELRAT=06                   # 锁 LTE；自动模式会在 WCDMA/LTE 之间反复横跳、不驻留
AT!RESET
```

换卡后必须 `AT!RESET` 重新读卡（热插拔检测已关闭）。

## 数据链路

```text
AT+CGDCONT=1,"IP","3gnet"      # 联通 3gnet / 电信 ctnet / 移动 cmnet
AT+CGACT=1,1
AT+CGPADDR=1                   # 返回运营商分配的 IP
```

设备侧关键：qmi_wwan 的帧格式必须和模组一致。**默认是 802.3**（`raw_ip=0`），
直接配置 IP 就能通；只有模组被切到 raw-ip（`uqmi --wda-set-data-format raw-ip`）时
才需要 `echo 1 > /sys/class/net/wwan0/qmi/raw_ip`。

镜像里的 `proto qmi`（`/lib/netifd/proto/qmi.sh`）会自动设置 802.3 并在必要时切 raw_ip，
所以用 LuCI/uci 建 qmi 接口时不用手动处理。

```bash
# 手动测试（802.3 默认模式，无需 raw_ip）
ip addr add <IP>/32 dev wwan0
ip link set wwan0 up
ip route add <网关>/32 dev wwan0
ip route add 223.5.5.5/32 via <网关> dev wwan0 src <IP>
ping -c 3 223.5.5.5
```

实测（联通卡）：

```
+CGCONTRDP: 1,5,3gnet,10.60.121.13,,58.20.127.238,58.20.159.152
PING 223.5.5.5: 4 packets transmitted, 4 received, 0% packet loss, time 32 ms
```

## 频段锁定

自定义频段集（Extended 格式：`Index,"Name",GWmask,L1,L2,TDS,L3,L4`）：

```text
AT!BAND=0B,"B8",0,0000000000000080,0,0,0,0     # 只锁 B8
AT!BAND=0B
AT!RESET
```

掩码位：bit0 = B1 … bit7 = B8（B8 = `0x80`），L Band Mask 2 的 bit1 = B66。
恢复全频段：`AT!BAND=00`。

实测：B8-only 时无小区可驻留（本地 B8 小区极弱）；B3+B8（`0x84`）时驻留 B3，
`AT!LTEINFO?` 的 InterFreq 列表里能看到 EARFCN 3740（B8）RSRP -134。

## LuCI 页面

「状态 → Modem」下有五个标签页（旧链接 `/modem/signal` 保留 302 重定向到状态页）：

| 标签 | 内容 |
| --- | --- |
| 状态 | 首屏四格 KPI（链路 / 信号 / 流量 / 模组）+ 连接、身份、模组状态、数据连接四张卡；信号条、服务小区、同频/异频邻区也在这一页 |
| 设置 | SIM 槽、制式、锁频、APN / PDP 类型 / 鉴权（写的是 `network.wwan`，拨号读它）、网络扫描与锁网、复位模组 |
| GPS | 启停定位，`AT!GPSSTATUS?` / `AT!GPSLOC?` / `AT!GPSSATINFO?` 原始回显 |
| SMS | 收件箱（PDU 解析，长短信按 UDH 合并，可逐条删）、发送（中文走 PDU）、已发送记录（可删） |
| AT | 原始 AT 调试：快捷命令、超时选择、输出复制；**无命令白名单**，有 LuCI 权限即可执行任意 AT |

## 镜像支持状态

从 `ec39bbf` 起构建已内置 LTE 支持：

| 组件 | 状态 |
| --- | --- |
| `kmod-usb-serial` / `-wwan` / `-option` | ✅ 内置（option 驱动带 EM7565 表项，`patches/openwrt/0002-…patch`） |
| `kmod-usb-wdm` + `kmod-usb-net-qmi-wwan` | ✅ 内置（`wwan0` / `cdc-wdm0`，自动加载） |
| `uqmi` + `proto qmi` | ✅ 内置；`network.wwan` 由 `zzz99-edge610-network-modem` 首次启动时自动创建 |
| qmi_wwan 帧格式 | `proto qmi` 自动设 802.3（必要时切 raw-ip），无需手动处理 |
| AT 配置（SIMHOTSWAPDIS/UIMS/SELRAT） | 已写入模组 NVRAM，换镜像后仍保留 |

## 刷完新镜像怎么配

镜像本身已经把模组相关内容装齐（驱动、`uqmi`、`proto qmi`、LuCI 的 `luci-proto-qmi`、状态页、
`modem-at`、`modem-wan-watch`），首次启动时 `zzz99-edge610-network-modem` 还会把数据接口建好。
所以刷完只需要确认三件事：

| 项 | 刷机后状态 | 要做什么 |
| --- | --- | --- |
| 驱动 / QMI / 页面 | 镜像自带 | 无（不需要再手补 `qmi.js` / `qmi.sh`，也不需要 `/root/kmods`） |
| `network.wwan` 接口 | `zzz99-edge610-network-modem` 建好：`proto qmi`、`/dev/cdc-wdm0`、`apn cmnet`、`pdptype ipv4v6`、`metric 100`、`auto 1` | APN 不是 cmnet 就在「设置」页改（写的是 `network.wwan.apn`，拨号读的就是它） |
| 防火墙 | `wwan` 自动加进 `wan` zone | 无需手动加 |
| SIM 槽 / 制式 / 锁频 | 模组 NVRAM（`SIMHOTSWAPDIS=1`、`UIMS=0`、`SELRAT=06`） | 刷机不动 NVRAM，保持原样 |
| 中文界面 | 默认 `auto` | 系统 → 语言，或 `uci set luci.main.lang=zh_cn` |

已经刷过、但版本早于 `zzz99-edge610-network-modem` 的机器，手动补一次即可：

```sh
uci set network.wwan=interface
uci set network.wwan.proto='qmi'
uci set network.wwan.device='/dev/cdc-wdm0'
uci set network.wwan.apn='cmnet'
uci set network.wwan.pdptype='ipv4v6'
uci set network.wwan.metric='100'
uci set network.wwan.auto='1'
uci commit network
uci add_list firewall.@zone[1].network='wwan'   # zone[1] 是 wan
uci commit firewall
ifup wwan
```

**不要**再把 `/root/kmods` 的 `insmod` 写进 `rc.local`：镜像自带这些模块，重复加载只会
报 `File exists`。SIM 卡必须插**上槽**（槽 2 在硬件上没接，`AT!UIMS=1` 指向它，选了就没卡）。

`modem-wan-watch` 现在除了校正 PDP 地址漂移，还看卡：连续两次读到 `present` 以外
（`absent` / `error: possibly-removed`）就 `ifdown wwan` 清掉死地址，并按 10 分钟节流
发一次 `AT+CFUN=1,1`。检测线被 `SIMHOTSWAPDIS` 屏蔽，所以插回卡后模组不会自己重新识别，
必须复位——这段看门狗就是替你做这件事。
