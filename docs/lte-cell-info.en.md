# EM7565 cell/network parameters — quick reference (measured)

> Chinese version: [lte-cell-info.md](lte-cell-info.md)

> Test environment: Sierra Wireless **EM7565** on the Edge 610
> (`SWI9X50C_01.11.00.00`, 2019-06-28), OpenWrt 25.12.6.
> AT port `/dev/ttyUSB2` (option driver), QMI port `/dev/cdc-wdm0` (`uqmi`).
> Data comes from the 41111748 Rev.2 AT reference plus live tests on this unit.

## 1. Parameter → source

| Parameter | AT command | QMI (uqmi) | Notes |
| --- | --- | --- | --- |
| PCI (serving cell) | `AT!LTEINFO?` | `--get-cell-location-info` | `serving_cell_id` |
| ECGI (eNB + Cell ID) | `AT+CEREG?` + `AT!LTEINFO?` | `--get-cell-location-info` | see §2.2 |
| TAC | `AT+CEREG?` / `AT!LTEINFO?` | same | |
| EARFCN / band / bandwidth | `AT!GSTATUS?` / `AT!LTEINFO?` | same | |
| RSRP / RSRQ / RSSI / SINR | `AT!GSTATUS?` / `AT!LTEINFO?` | `--get-signal-info`, `--get-tx-rx-info lte` | per RX chain |
| Neighbours (intra/inter-freq) | `AT!LTEINFO=2?` | `--get-cell-location-info` | |
| CA active state | `AT!GSTATUS?` (SSC1–4) | `--get-lte-cphy-ca-info` | no CA on this unit |
| CA capability | `AT!LTECA?` | — | hardware/firmware support table |
| APN / IP / gateway / DNS | `AT+CGCONTRDP` | `--get-current-settings` | |
| **APN-AMBR / UE-AMBR** | ❌ | ❌ | not implemented by the firmware, see §4 |
| **CQI / MCS / RI / PMI** | ❌ | ❌ | DIAG/QXDM only |
| **Negotiated rate / throughput** | ❌ | qmicli WDS (not installed) | use `wwan0` counters |

## 2. AT commands (measured output)

### 2.1 `AT!GSTATUS?` — one-stop status

```
!GSTATUS:
Current Time:  724		Temperature: 38
Reset Counter: 20		Mode:        ONLINE
System mode:   LTE        	PS state:    Attached
LTE band:      B8     		LTE bw:      10 MHz
LTE Rx chan:   3590		LTE Tx chan: 21590
LTE SSC1 state:NOT ASSIGNED     <- CA secondary carrier state
EMM state:     Registered     	Normal Service
RRC state:     RRC Idle
PCC RxM RSSI:  -50		PCC RxM RSRP:  -76
PCC RxD RSSI:  -99		PCC RxD RSRP:  -130
Tx Power:      --		TAC:         73c5 (29637)
RSRQ (dB):     -9.3		Cell ID:     084ad848 (139122760)
SINR (dB):      9.6
```

- `LTE Rx chan` = downlink EARFCN; `Cell ID` = 28-bit ECI (hex).
- **Note**: `!GSTATUS` reports RSRP in dBm; `!LTEINFO` reports RSRP as **dBm×10** — do not share a scale factor.

### 2.2 `AT!LTEINFO?` — cell identity + neighbours

```
!LTEINFO:
Serving:   EARFCN MCC MNC   TAC      CID Bd D U SNR PCI  RSRQ   RSRP   RSSI RXLV
             3590 460  00 29637 084AD848  8 3 3   8 400  -9.5  -76.2  -49.0  43

IntraFreq:                                          PCI  RSRQ   RSRP   RSSI RXLV
                                                    400  -9.5  -76.2  -49.0  43
                                                     84 -13.3  -87.7  -65.4  43
                                                    373 -19.5  -90.7  -62.2  43
```

- **ECGI composition**: `ECGI = MCC|MNC|ECI`, where `ECI = eNB<<8 | cell`.
  Measured `CID 084AD848` → eNB `543448`, cell `0x48 = 72`;
  `AT+CEREG?` also returns `+CEREG: 2,1,"73C5","42","84AD848",7` (TAC + CI + AcT).
- Inter-frequency neighbours: `AT!LTEINFO=2?` / `AT!LTEINFO=3?` (the InterFreq list of the basic query may be empty).

### 2.3 Band / CA / temperature

```
AT!BAND?      -> 00, All bands          (configured band mask)
AT!GETBAND?   -> !GETBAND: B7           !! does not match the serving band B8, unreliable
AT!LTECA?     -> Hardware / Permitted Bands / Prune_ca_combos   (CA capability, not state)
AT!PCTEMP?    -> Temperature: 38.00 C
AT!PCVOLT?    -> Power supply voltage: 3316 mV
```

### 2.4 APN / PDN

```
AT+CGDCONT?    -> +CGDCONT: 1,"IP","cbnet","0.0.0.0",0,0,0,0
AT+CGCONTRDP   -> +CGCONTRDP: 1,5,cbnet,10.52.202.158,,43.239.172.1,43.239.172.2
AT+CGPADDR=1   -> +CGPADDR: 1,10.52.202.158
AT+CGACT?      -> +CGACT: 1,1
```

`+CGCONTRDP` fields: `<cid>,<bearer_id>,<apn>,<local_ip>,[mask],<gw>,<dns1>,<dns2>`
— **there are no QCI/GBR/MBR/AMBR fields**.

## 3. QMI (uqmi) — finer cell information

The image ships `uqmi` (`/sbin/uqmi`). The QMI service occasionally returns
`Failed to connect to service`; just retry.

### 3.1 `--get-cell-location-info` (measured)

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

This is the **only** interface that gives eNB ID + Cell ID (to build the ECGI), the serving PCI,
and intra/inter-frequency neighbour measurements at the same time.

### 3.2 Others

| Command | Content |
| --- | --- |
| `uqmi --get-serving-system` | registration state, PLMN, roaming |
| `uqmi --get-system-info` | LTE service state, TAC, Cell ID |
| `uqmi --get-signal-info` | RSSI/RSRQ/RSRP/SNR |
| `uqmi --get-tx-rx-info lte` | per-RX-chain RSSI/RSRQ/RSRP + TX state (note: uqmi prints the rsrp sign wrong; the real value is negative) |
| `uqmi --get-lte-cphy-ca-info` | per-carrier PCI/EARFCN/bandwidth/state (`Information unavailable` without CA) |
| `uqmi --get-current-settings` | APN, PDP type, IP, DNS, MTU |

## 4. Parameters that cannot be obtained (firmware limits)

| Parameter | Verdict | Evidence |
| --- | --- | --- |
| **APN-AMBR / UE-AMBR** | Not available | `AT+CGEQOSRDP=1` returns only `OK` (unimplemented); `+CGCONTRDP` has no AMBR field; no AMBR TLV in any libqmi service JSON; UE-AMBR is not in TS 27.007 |
| **CQI / MCS / RI / PMI / BLER** | Not available | `AT!CQI?`/`AT!MCS?` return ERROR; the manual has no such commands; no matching QMI TLV (DIAG/QXDM only) |
| **Negotiated rate / live throughput** | No AT command | `!GSTATUS` has no counters; use `/sys/class/net/wwan0/statistics/*` deltas, or qmicli `--wds-get-packet-statistics` |
| **Per-SCC PCI/bandwidth** | No AT command | `!CAINFO/!PCCINFO/!SCCINFO` do not exist; only QMI `--get-lte-cphy-ca-info` |
| **TA (Timing Advance)** | No AT command | QMI `--get-cell-location-info` TLV (not returned by this firmware) |

## 5. Caveats

1. **The option driver must match only the AT interfaces** (`ff/00/00`, interfaces 2/3).
   Matching all interfaces with `USB_DEVICE(0x1199,0x9091)` steals QMI interface 8, so
   `qmi_wwan` cannot bind and there is no `wwan0`.
2. The band reported by `AT!GETBAND?` is unreliable (it reported B7 while the serving band was B8);
   trust `!GSTATUS?`/`!LTEINFO?` instead.
3. `<rsrp>/<rssi>` in `!LTEINFO` are **dBm×10**; `!GSTATUS` is dBm.
4. `AT+CEREG?` has an extra vendor field: `+CEREG: 2,1,"73C5","42","84AD848",7`
   (TAC, vendor field, CI, AcT) — do not parse it by the TS 27.007 positions.
5. `AT+CREG?` returning `0,3` (CS domain denied) during a data-only attach is normal.
