# 板载 LTE 模组（EM7565）实测

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
| AT 口 | USB 接口 1.3（`/dev/ttyUSB2`），115200 8N1 |
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

设备侧关键：**qmi_wwan 接口必须切 raw-ip**，否则 TX 有包、RX 永远为 0：

```bash
echo 1 > /sys/class/net/wwan0/qmi/raw_ip
ip addr add <IP>/32 dev wwan0
ip link set wwan0 up
ip route add <网关>/32 dev wwan0
ping -I <IP> 223.5.5.5
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

## 当前镜像缺什么

内核 `CONFIG_USB_SERIAL` 未开启，模组在默认镜像里不可用。要支持需要：

| 包 | 作用 |
| --- | --- |
| `kmod-usb-serial` + `kmod-usb-serial-wwan` + `kmod-usb-serial-option` | AT 口 |
| option 驱动补丁（`option.c` 表加 `{ USB_DEVICE(0x1199, 0x9091) }`） | 识别 EM7565 |
| `kmod-usb-wdm` + `kmod-usb-net-qmi-wwan` | QMI 数据接口 |
| `uqmi` | 拨号 |
| 开机脚本 | 上面 4 条 AT 配置 + `raw_ip=1` |
