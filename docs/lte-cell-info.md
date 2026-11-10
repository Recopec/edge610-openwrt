# EM7565 小区/网络参数速查（实测）

> English version: [lte-cell-info.en.md](lte-cell-info.en.md)

> 实测环境：Edge 610 板载 Sierra Wireless **EM7565**（`SWI9X50C_01.11.00.00`，2019-06-28），
> OpenWrt 25.12.6。AT 口是 `ttyUSB*` 里响应 AT 的那个（枚举顺序不固定，`modem-at` 自动探测），QMI 口 `/dev/cdc-wdm0`（`uqmi`）。
> 数据来自 41111748 Rev.2 AT 参考手册 + 本机实测。

## 1. 参数 → 来源一览

| 参数 | AT 命令 | QMI（uqmi） | 备注 |
| --- | --- | --- | --- |
| PCI（服务小区） | `AT!LTEINFO?` | `--get-cell-location-info` | `serving_cell_id` |
| ECGI（eNB + Cell ID） | `AT+CEREG?` + `AT!LTEINFO?` | `--get-cell-location-info` | 见 §2.2 |
| TAC | `AT+CEREG?` / `AT!LTEINFO?` | 同上 | |
| EARFCN / 频段 / 带宽 | `AT!GSTATUS?` / `AT!LTEINFO?` | 同上 | |
| RSRP / RSRQ / RSSI / SINR | `AT!GSTATUS?` / `AT!LTEINFO?` | `--get-signal-info`、`--get-tx-rx-info lte` | 每 RX 链 |
| 邻区（同频/异频） | `AT!LTEINFO=2?` | `--get-cell-location-info` | |
| CA 活动状态 | `AT!GSTATUS?`（SSC1–4） | `--get-lte-cphy-ca-info` | 本机无 CA |
| CA 能力 | `AT!LTECA?` | — | 硬件/固件支持表 |
| APN / IP / 网关 / DNS | `AT+CGCONTRDP` | `--get-current-settings` | |
| **APN-AMBR / UE-AMBR** | ❌ | ❌ | 固件不实现，见 §4 |
| **CQI / MCS / RI / PMI** | ❌ | ❌ | 仅 DIAG/QXDM |
| **协商速率 / 吞吐** | ❌ | qmicli WDS（未装） | 用 `wwan0` 计数 |

## 2. AT 命令（实测输出）

### 2.1 `AT!GSTATUS?` —— 一站式状态

```
!GSTATUS:
Current Time:  724		Temperature: 38
Reset Counter: 20		Mode:        ONLINE
System mode:   LTE        	PS state:    Attached
LTE band:      B8     		LTE bw:      10 MHz
LTE Rx chan:   3590		LTE Tx chan: 21590
LTE SSC1 state:NOT ASSIGNED     ← CA 从属载波状态
EMM state:     Registered     	Normal Service
RRC state:     RRC Idle
PCC RxM RSSI:  -50		PCC RxM RSRP:  -76
PCC RxD RSSI:  -99		PCC RxD RSRP:  -130
Tx Power:      --		TAC:         73c5 (29637)
RSRQ (dB):     -9.3		Cell ID:     084ad848 (139122760)
SINR (dB):      9.6
```

- `LTE Rx chan` = 下行 EARFCN；`Cell ID` = 28 位 ECI（hex）。
- **注意**：`!GSTATUS` 的 RSRP 单位是 dBm；`!LTEINFO` 的 RSRP 是 **dBm×10**，解析别共用比例。

### 2.2 `AT!LTEINFO?` —— 小区身份 + 邻区

```
!LTEINFO:
Serving:   EARFCN MCC MNC   TAC      CID Bd D U SNR PCI  RSRQ   RSRP   RSSI RXLV
             3590 460  00 29637 084AD848  8 3 3   8 400  -9.5  -76.2  -49.0  43

IntraFreq:                                          PCI  RSRQ   RSRP   RSSI RXLV
                                                    400  -9.5  -76.2  -49.0  43
                                                     84 -13.3  -87.7  -65.4  43
                                                    373 -19.5  -90.7  -62.2  43
```

- **ECGI 拼法**：`ECGI = MCC|MNC|ECI`，其中 `ECI = eNB<<8 | cell`。
  实测 `CID 084AD848` → eNB `543448`、cell `0x48 = 72`；
  `AT+CEREG?` 也会给出 `+CEREG: 2,1,"73C5","42","84AD848",7`（TAC + CI + AcT）。
- 异频邻区：`AT!LTEINFO=2?` / `AT!LTEINFO=3?`（基础查询的 InterFreq 可能为空）。

### 2.3 频段 / CA / 温度

```
AT!BAND?      → 00, All bands          （配置的频段掩码）
AT!GETBAND?   → !GETBAND: B7           ⚠ 与实际服务频段 B8 不符，不可靠
AT!LTECA?     → Hardware / Permitted Bands / Prune_ca_combos   （CA 能力，非活动状态）
AT!PCTEMP?    → Temperature: 38.00 C
AT!PCVOLT?    → Power supply voltage: 3316 mV
```

### 2.4 APN / PDN

```
AT+CGDCONT?    → +CGDCONT: 1,"IP","cbnet","0.0.0.0",0,0,0,0
AT+CGCONTRDP   → +CGCONTRDP: 1,5,cbnet,10.52.202.158,,43.239.172.1,43.239.172.2
AT+CGPADDR=1   → +CGPADDR: 1,10.52.202.158
AT+CGACT?      → +CGACT: 1,1
```

`+CGCONTRDP` 字段：`<cid>,<bearer_id>,<apn>,<local_ip>,[mask],<gw>,<dns1>,<dns2>`
—— **没有 QCI/GBR/MBR/AMBR 字段**。

## 3. QMI（uqmi）—— 更细的小区信息

镜像自带 `uqmi`（`/sbin/uqmi`）。QMI 服务偶发 `Failed to connect to service`，重试即可。

### 3.1 `--get-cell-location-info`（实测）

```json
{
  "intrafrequency_lte_info": {
    "tracking_area_code": 29637,
    "enodeb_id": 543448,
    "cell_id": 72,
    "channel": 3590,
    "band": 8,
    "frequency": 900,
    "duplex": "FDD",
    "serving_cell_id": 400,
    "cell_reselection_priority": 2,
    ...
    "cells": [
      { "physical_cell_id": 400, "rsrq": -8.3, "rsrp": -80.1, "rssi": -54.7, "cell_selection_rx_level": 39 },
      { "physical_cell_id": 3,   "rsrq": -14.5, "rsrp": -90.1, "rssi": -66.7, "cell_selection_rx_level": 33 }
    ]
  },
  "interfrequency_lte_info": { "channel": 1300, "band": 3, "cells": [ ... ] }
}
```

这是**唯一能同时拿到 eNB ID + Cell ID（拼 ECGI）、服务 PCI、同频/异频邻区测量值**的接口。

### 3.2 其他

| 命令 | 内容 |
| --- | --- |
| `uqmi --get-serving-system` | 注册状态、PLMN、漫游 |
| `uqmi --get-system-info` | LTE 服务状态、TAC、Cell ID |
| `uqmi --get-signal-info` | RSSI/RSRQ/RSRP/SNR |
| `uqmi --get-tx-rx-info lte` | 每 RX 链 RSSI/RSRQ/RSRP + TX 状态（注意 uqmi 输出的 rsrp 符号有 bug，实际为负） |
| `uqmi --get-lte-cphy-ca-info` | 每载波 PCI/EARFCN/带宽/状态（无 CA 时返回 `Information unavailable`） |
| `uqmi --get-current-settings` | APN、PDP 类型、IP、DNS、MTU |

## 4. 拿不到的参数（固件限制）

| 参数 | 结论 | 依据 |
| --- | --- | --- |
| **APN-AMBR / UE-AMBR** | 不可得 | `AT+CGEQOSRDP=1` 只回 `OK`（未实现）；`+CGCONTRDP` 无 AMBR 字段；libqmi 全部服务 JSON 无 AMBR TLV；UE-AMBR 不在 TS 27.007 |
| **CQI / MCS / RI / PMI / BLER** | 不可得 | `AT!CQI?`/`AT!MCS?` 报 ERROR；手册无这些命令；QMI 无对应 TLV（仅 DIAG/QXDM） |
| **协商速率 / 实时吞吐** | AT 无 | `!GSTATUS` 无计数器；用 `/sys/class/net/wwan0/statistics/*` 差分，或 qmicli `--wds-get-packet-statistics` |
| **每 SCC 的 PCI/带宽** | AT 无 | `!CAINFO/!PCCINFO/!SCCINFO` 不存在；仅 QMI `--get-lte-cphy-ca-info` |
| **TA（Timing Advance）** | AT 无 | QMI `--get-cell-location-info` 的 TLV（本固件未返回） |

## 5. 注意事项

1. **option 驱动只能匹配 AT 接口**（`ff/00/00`，接口 2/3）。若用 `USB_DEVICE(0x1199,0x9091)` 匹配所有接口，会把 QMI 接口 8 抢走，`qmi_wwan` 无法绑定、没有 `wwan0`。
2. `AT!GETBAND?` 报的频段不可靠（实测报 B7，实际 B8），以 `!GSTATUS?`/`!LTEINFO?` 为准。
3. `!LTEINFO` 的 `<rsrp>/<rssi>` 是 **dBm×10**；`!GSTATUS` 是 dBm。
4. `AT+CEREG?` 的响应多一个字段：`+CEREG: 2,1,"73C5","42","84AD848",7`（TAC、厂商字段、CI、AcT），别按 27.007 的位置硬解析。
5. `AT+CREG?` 在纯数据附着时返回 `0,3`（CS 域 denied）属正常。
