# EM7565 官方 AT 命令总览（41111748 Rev.2）

> English version: [lte-at-commands.en.md](lte-at-commands.en.md)

> 来源：*AirPrime EM75xx AT Command Reference* Rev.2（Jan.2019，140 页）。
> Sierra 私有命令（`AT!...`）在手册第 3–11 章有完整语法；3GPP 标准命令在第 12 章只给支持矩阵。
> 大部分 `AT!` 命令需要先 `AT!ENTERCND="A710"`。

## 1. Sierra 私有命令

### 1.1 密码 / 状态 / 定制（第 3 章）

| 命令 | 说明 | 页 |
| --- | --- | --- |
| `!ENTERCND` | 进入密码保护命令 | 16 |
| `!SETCND` | 设置 AT 密码 | 17 |
| `!ANTSEL` | 外部天线选择配置 | 20 |
| `!BAND` | 设置/查询频段集 | 22 |
| `!BOOTHOLD` | 复位并停在 bootloader | 24 |
| `!CUSTOM` | 定制项（见下表） | 25 |
| `!DATALOOPBACK` | 回环测试 | 28 |
| `!GCFEN` | GCF 测试模式 | 29 |
| `!GETBAND` | 当前激活频段 | 29 |
| `!GSTATUS` | 运行状态（频段/信道/TAC/ECI/RSRP/RSRQ/SINR） | 30 |
| `!HWID` | 硬件版本 | 30 |
| `!IMPREF` | 镜像/固件偏好 | 31 |
| `!LTECA` | LTE CA 能力（启停/组合表） | 33 |
| `!LTEINFO` | LTE 小区信息 + 邻区 | 35 |
| `!NVENCRYPTIMEI` | 写明文 IMEI | 37 |
| `!NVPLMN` | PLMN 锁定列表 | 38 |
| `!PCINFO` | 电源控制状态 | 39 |
| `!PCOFFEN` | Power Off Enable | 40 |
| `!PCTEMP` | 模块温度 | 40 |
| `!PCTEMPLIMITS` | 温度门限 | 41 |
| `!PCVOLT` | 供电电压 | 42 |
| `!PCVOLTLIMITS` | 电压门限 | 43 |
| `!PRIID` | PRI 版本 | 44 |
| `!RESET` | 复位模组 | 44 |
| `!SCACT` | PDN 连接激活/查询 | 45 |
| `!TMSTATUS` | 热缓解状态 | 46 |
| `!USBCOMP` | USB 接口组合 | 47 |
| `!USBINFO` | USB 描述符信息 | 48 |
| `!USBPID` | USB PID | 49 |
| `!USBSPEED` | USB 速率 | 50 |
| `&V` | 当前配置参数 | 51 |

### 1.2 `!CUSTOM` 子项（第 25–28 页）

| 子项 | 说明 |
| --- | --- |
| `CFUNPERSISTEN` | +CFUN 设置是否跨断电保持 |
| `CSVOICEREJECT` | 忽略语音寻呼 |
| `FASTENUMEN` | 快速枚举 |
| `GPIOSARENABLE` | SAR 由 GPIO 控制 |
| `GPSENABLE` | GPS 开关 |
| `GPSLPM` | 低功耗下 GPS |
| `GPSREFLOC` | GPS 位置上报 |
| `GPSSEL` | GPS 天线类型 |
| `IPV6ENABLE` | IPv6 开关 |
| `NETWORKNAMEFMT` | MBIM 运营商名格式 |
| `PCSCDISABLE` | PCSC 功能 |
| `QMIDETACHEN` | QMI NAS 开关 |
| `REL8FASTDORMDIS` | Rel-8 快速休眠 |
| `RRCREL7CAPDIS` | RRC Rel-7 能力 |
| `SIMHOTSWAPDIS` | SIM 热插拔检测（本机需设为 1） |
| `SIMLPM` | SIM 低功耗状态 |
| `SINGLEAPNSWITCH` | 单 APN 切换行为 |
| `SKUID` | SKU ID |
| `UIM2ENABLE` | 第二 SIM 接口 |
| `USBSERIALENABLE` | 用 IMEI 作 USB 序列号 |
| `WAKEHOSTEN` | 主机唤醒方式 |

### 1.3 诊断命令（第 4 章）

| 命令 | 说明 | 页 |
| --- | --- | --- |
| `!BCFWUPDATESTATUS` | 上次固件升级状态 | 53 |
| `!ERR` | 诊断信息 | 54 |
| `!GCCLR` | 清除崩溃转储 | 54 |
| `!GCDUMP` | 显示崩溃转储 | 55 |
| `!LTERXCONTROL` | CA 下 LTE 接收分集控制 | 56 |
| `!RXDEN` | 接收分集开关 | 57 |

### 1.4 测试命令（第 5 章，需 `AT!DAFTMACT`）

| 命令 | 说明 | 页 |
| --- | --- | --- |
| `!DACGPSCTON` | GPS CtoN/频偏测量 | 60 |
| `!DACGPSMASKON` | CGPS IQ log mask | 60 |
| `!DACGPSSTANDALONE` | 进入/退出 SA RF 模式 | 61 |
| `!DACGPSTESTMODE` | CGPS 诊断任务 | 61 |
| `!DAFTMACT` | 进入工厂测试模式 | 62 |
| `!DAFTMDEACT` | 退出工厂测试模式 | 62 |
| `!DAGFTMRXAGC` | FTM Rx AGC | 63 |
| `!DALGRXAGC` | LTE Rx AGC | 64 |
| `!DALGTXAGC` | LTE Tx AGC/发射参数 | 65 |
| `!DALTXCONTROL` | LTE Tx 参数配置 | 67 |
| `!DAOFFLINE` | 离线 | 68 |
| `!DARCONFIG` | 设置频段/信道 | 69 |
| `!DARCONFIGDROP` | 丢弃无线配置 | 70 |
| `!DAWTXCONTROL` | WCDMA Tx 功率 | 70 |

### 1.5 存储管理（第 6 章）

| 命令 | 说明 | 页 |
| --- | --- | --- |
| `!NVBACKUP` | 备份设备配置 | 72 |
| `!RMARESET` | 恢复设备配置 | 74 |

### 1.6 GNSS 命令（第 7 章）

| 命令 | 说明 | 页 |
| --- | --- | --- |
| `!GPSAUTOSTART` | GPS 自动启动 | 76 |
| `!GPSCLRASSIST` | 清除辅助数据 | 78 |
| `!GPSCOLDSTART` | 冷启动 | 79 |
| `!GPSEND` | 结束会话 | 79 |
| `!GPSFIX` | 发起定位 | 80 |
| `!GPSLBSAPN` | GPS LBS APN | 81 |
| `!GPSLOC` | 最近位置 | 83 |
| `!GPSMOMETHOD` | GPS MO 方式 | 84 |
| `!GPSNMEACONFIG` | NMEA 输出速率 | 85 |
| `!GPSNMEASENTENCE` | NMEA 语句类型 | 86 |
| `!GPSPORTID` | TCP/IP 端口 ID | 87 |
| `!GPSSATINFO` | 卫星信息 | 88 |
| `!GPSSTATUS` | 定位会话状态 | 89 |
| `!GPSSUPLURL` | SUPL 服务器 URL | 90 |
| `!GPSSUPLVER` | SUPL 版本 | 91 |
| `!GPSTRACK` | 连续跟踪定位 | 92 |
| `+WANT` | GNSS 天线供电 | 93 |

### 1.7 SIM / OMA-DM / SAR / AirVantage（第 8–11 章）

| 命令 | 说明 | 页 |
| --- | --- | --- |
| `+UIMS` | 选择活动 SIM 接口 | 97 |
| `!HOSTDEVINFO` | 主机设备信息 | 99 |
| `!IMSTESTMODE` | IMS 测试模式 | 100 |
| `!OSINFO` | 主机 OS 信息 | 101 |
| `!MAXPWR` | 最大发射功率 | 103 |
| `!SARBACKOFF` | SAR 回退偏移 | 104 |
| `!SARINTGPIOMODE` | SAR GPIO 模式 | 105 |
| `!SARSTATE` | SAR 回退状态 | 106 |
| `!SARSTATEDFLT` | 默认 SAR 状态 | 107 |
| `+WDSC` | AirVantage 配置 | 109 |
| `+WDSE` | AirVantage 错误 | 111 |
| `+WDSG` | AirVantage 状态 | 112 |
| `+WDSI` | AirVantage 通知开关 | 113 |
| `+WDSR` | 回复 AirVantage 请求 | 116 |

## 2. 3GPP 标准命令（第 12 章）

手册只给"是否支持"矩阵，语法按 3GPP TS 27.007 / 27.005 / V.250。

### 2.1 ITU-T V.250（43 条）

| 命令 | 支持 | 说明 |
| --- | --- | --- |
| `&D` | ✅ | Set Data Terminal Ready function mode |
| `&F` | ✅ | Set all current parameters to manufacturer’s defaults |
| `&S` | ✅ | Set DSR signal |
| `&T` | ❌ | Auto tests |
| `&V` | ✅ | Return operating mode AT configuration parameters |
| `&W` | ✅ | Store current parameter to user-defined profile |
| `+DR` | ✅ | V42bis data compression report |
| `+DS` | ✅ | V42bis data compression |
| `+GCAP` | ✅ | Request complete TA capabilities list |
| `+GMI` | ✅ | Request manufacturer identification |
| `+GMM` | ✅ | Request TA model identification |
| `+GMR` | ✅ | Request TA revision identification |
| `+GOI` | ❌ | Request global object identification |
| `+GSN` | ✅ | Request TA serial number identification |
| `+ICF` | ✅ | Set TE-TA control character framing |
| `+IFC` | ✅ | Set TE-TA local data flow control |
| `+ILRR` | ❌ | Set TE-TA local rate reporting mode |
| `+IPR` | ✅ | Set fixed local rate |
| `A` | ✅ | Answer incoming call |
| `D` | ✅ | Dial |
| `D><MEM><N>` | ❌ | Originate call to phone number in memory <MEM> |
| `D><N>` | ✅ | Originate call to phone number in current memory |
| `DL` | ❌ | Redial last telephone number used |
| `E` | ✅ | Set command echo mode |
| `H` | ✅ | Disconnect existing connections |
| `I` | ✅ | Display product identification information |
| `L` | ❌ | Set monitor speaker loudness |
| `M` | ❌ | Set monitor speaker mode |
| `O` | ✅ | Switch from command mode to data mode |
| `P` | ❌ | Select pulse dialing |
| `Q` | ✅ | Set Result code presentation mode |
| `S0` | ✅ | Set number of rings before automatically answering the call |
| `S10` | ✅ | Set disconnect delay after indicating the absence of data carrier |
| `S3` | ✅ | Set command line termination character |
| `S4` | ✅ | Set response formatting character |
| `S5` | ✅ | Set command line editing character |
| `S6` | ✅ | Set pause before blind dialing |
| `S7` | ✅ | Set number of seconds to wait for connection completion |
| `S8` | ✅ | Set number of seconds to wait when comma dial modifier used |
| `T` | ✅ | Select tone dialing |
| `V` | ✅ | Set result code format mode |
| `X` | ✅ | Set connect result code format and call monitoring |
| `Z` | ✅ | Set all current parameters to user-defined profile |

### 2.2 3GPP TS 27.005（SMS，25 条）

| 命令 | 支持 | 说明 |
| --- | --- | --- |
| `+CBM` | ✅ | Cell broadcast message directly displayed |
| `+CDS` | ✅ | SMS status report after sending a SMS |
| `+CDSI` | ✅ | Incoming SMS status report |
| `+CMGC` | ✅ | Send command |
| `+CMGD` | ✅ | Delete message |
| `+CMGF` | ✅ | Message format |
| `+CMGL` | ✅ | List messages |
| `+CMGR` | ✅ | Read message |
| `+CMGS` | ✅ | Send message |
| `+CMGW` | ✅ | Write message to memory |
| `+CMMS` | ✅ | More messages to send |
| `+CMNA` | ✅ | New message acknowledgement to ME/TA |
| `+CMS ERROR` | ✅ | error (mobile or network error) |
| `+CMSS` | ✅ | Send message from storage |
| `+CMT` | ✅ | Incoming message directly displayed |
| `+CNMA` | ✅ | New message acknowledgement to mobile equipment |
| `+CNMI` | ✅ | New message indications to TE |
| `+CPMS` | ✅ | Preferred message storage |
| `+CRES` | ❌ | Restore settings |
| `+CSAS` | ❌ | Save settings |
| `+CSCA` | ✅ | Service center address |
| `+CSCB` | ✅ | Select cell broadcast message types |
| `+CSDH` | ✅ | Show text mode parameters |
| `+CSMP` | ✅ | Set text mode parameters |
| `+CSMS` | ✅ | Select message service |

### 2.3 3GPP TS 27.007（106 条）

| 命令 | 支持 | 说明 |
| --- | --- | --- |
| `+CACM` | ❌ | Accumulated call meter |
| `+CAEMLPP` | ❌ | eMLPP Priority Registration and Interrogation |
| `+CALM` | ❌ | Alert sound mode |
| `+CAMM` | ❌ | Accumulated call meter maximum |
| `+CANCHEV` | ❌ | NCH Support Indication |
| `+CAOC` | ❌ | Advice of Charge |
| `+CBC` | ✅ | Battery charge |
| `+CBST` | ✅ | Select bearer service type |
| `+CCCM` | ❌ | Current call meter value |
| `+CCFC` | ✅ | Call forwarding number and conditions |
| `+CCHC` | ✅ | Close logical channel |
| `+CCHO` | ✅ | Open logical channel |
| `+CCUG` | ✅ | Closed user group |
| `+CCWA` | ✅ | Call waiting |
| `+CCWE` | ❌ | Call Meter maximum event |
| `+CDIP` | ❌ | Called line identification presentation |
| `+CDIS` | ❌ | Display control |
| `+CEER` | ❌ | Extended error report |
| `+CGACT` | ✅ | PDP context activate or deactivate |
| `+CGANS` | ❌ | Manual response to a network request for PDP context activation |
| `+CGATT` | ✅ | PS attach or detach |
| `+CGCLASS` | ✅ | GPRS mobile station class |
| `+CGCLOSP` | ❌ | Configure local octet stream PAD parameters |
| `+CGCMOD` | ❌ | PDP Context Modify |
| `+CGDATA` | ✅ | Enter data state |
| `+CGDCONT` | ✅ | Define PDP Context |
| `+CGDSCONT` | ✅ | Define Secondary PDP Context |
| `+CGEQMIN` | ✅ | 3G Quality of Service Profile (Minimum acceptable) |
| `+CGEQNEG` | ✅ | 3G Quality of Service Profile (Negotiated) |
| `+CGEQREQ` | ✅ | 3G Quality of Service Profile (Requested) |
| `+CGEREP` | ✅ | Packet Domain event reporting |
| `+CGEV` | ✅ | GPRS network event indication |
| `+CGLA` | ✅ | Generic UICC logical channel access |
| `+CGMI` | ✅ | Request manufacturer identification |
| `+CGMM` | ✅ | Request model identification |
| `+CGMR` | ✅ | Request revision identification |
| `+CGPADDR` | ✅ | Show PDP address |
| `+CGQMIN` | ✅ | Quality of Service Profile (Minimum acceptable) |
| `+CGQREQ` | ✅ | Quality of Service Profile (Requested) |
| `+CGREG` | ✅ | GPRS network registration status |
| `+CGSMS` | ✅ | Select service for MO SMS messages |
| `+CGSN` | ✅ | Request product serial number identification |
| `+CGTFT` | ✅ | Traffic Flow Template |
| `+CHLD` | ✅ | Call related supplementary services |
| `+CHUP` | ✅ | Hangup call |
| `+CIEV` | ✅ | Indicator event |
| `+CIMI` | ✅ | Request international mobile subscriber identity |
| `+CIND` | ✅ | Indicator control |
| `+CKEV` | ❌ | Key press or release event |
| `+CKPD` | ❌ | Keypad control |
| `+CLAC` | ❌ | List all available AT commands |
| `+CLAE` | ❌ | Language Event |
| `+CLAN` | ❌ | Set Language |
| `+CLCC` | ✅ | List current calls |
| `+CLCK` | ✅ | Facility lock |
| `+CLIP` | ✅ | Calling line identification presentation |
| `+CLIR` | ✅ | Calling line identification restriction |
| `+CLVL` | ✅ | Set/return internal loudspeaker volume |
| `+CMAR` | ❌ | Master Reset |
| `+CME ERROR` | ✅ | Termination error result code |
| `+CMEC` | ❌ | Mobile Termination control mode |
| `+CMEE` | ✅ | Report Mobile Termination error |
| `+CMER` | ✅ | Mobile Termination event reporting |
| `+CMOD` | ✅ | Call mode |
| `+CMUT` | ✅ | Enable/disable uplink voice muting |
| `+CMUX` | ✅ | Multiplexing mode |
| `+CNUM` | ✅ | Subscriber number |
| `+COLP` | ✅ | Connected line identification presentation |
| `+COPN` | ✅ | Read operator names |
| `+COPS` | ✅ | Operator selection |
| `+CPAS` | ✅ | Phone activity status |
| `+CPBF` | ✅ | Find phonebook entries |
| `+CPBR` | ✅ | Read phonebook entries |
| `+CPBS` | ✅ | Select phonebook memory storage |
| `+CPBW` | ✅ | Write phonebook entry |
| `+CPIN` | ✅ | Enter PIN |
| `+CPINR` | ✅ | Remaining PIN retries |
| `+CPLS` | ✅ | Preferred PLMN list selection |
| `+CPOL` | ✅ | Preferred operator list |
| `+CPROT` | ❌ | Enter protocol mode |
| `+CPUC` | ✅ | Price per unit and currency table |
| `+CPWC` | ❌ | Power class |
| `+CPWD` | ✅ | Change password |
| `+CR` | ✅ | Service reporting control |
| `+CRC` | ✅ | Cellular result codes |
| `+CREG` | ✅ | Network registration |
| `+CRING` | ✅ | Incoming call type |
| `+CRLP` | ✅ | Radio link protocol |
| `+CRSM` | ✅ | Restricted SIM access |
| `+CSCC` | ❌ | Secure control command |
| `+CSCS` | ✅ | Select TE character set |
| `+CSIM` | ✅ | Generic SIM access |
| `+CSNS` | ❌ | Single numbering scheme |
| `+CSQ` | ✅ | Signal quality |
| `+CSSN` | ✅ | Supplementary service notifications |
| `+CSTA` | ✅ | Select type of address |
| `+CSTF` | ✅ | Settings time format |
| `+CSVM` | ❌ | Set Voice Mail Number |
| `+CTFR` | ✅ | Call deflection |
| `+CTZU` | ❌ | Automatic Time Zone Update |
| `+CUSD` | ✅ | Unstructured supplementary service data |
| `+CV120` | ❌ | V.120 rate adaptation protocol |
| `+CVHU` | ❌ | Voice Hangup Control |
| `+VTD` | ✅ | Tone duration |
| `+VTS` | ✅ | DTMF and arbitrary tone generation |
| `+WS46` | ❌ | PCCA STD 101 [17] select wireless network |

## 3. 常用命令速查

| 用途 | 命令 |
| --- | --- |
| 模组信息 | `ATI`、`AT+CGMI/CGMM/CGMR/CGSN` |
| 注册/小区 | `AT+CEREG?`、`AT+COPS?`、`AT!GSTATUS?`、`AT!LTEINFO?` |
| 信号 | `AT+CSQ`、`AT!LTEINFO?`、`AT!GSTATUS?` |
| 频段 | `AT!BAND?`、`AT!GETBAND?`（不可靠） |
| SIM | `AT+CPIN?`、`AT+CIMI`、`AT+CCID`、`AT!UIMS` |
| APN/PDN | `AT+CGDCONT?`、`AT+CGACT?`、`AT+CGCONTRDP` |
| 温度/电压 | `AT!PCTEMP?`、`AT!PCVOLT?`、`AT!TMSTATUS?` |
| CA | `AT!LTECA?`（能力）、`AT!GSTATUS?`（状态） |

> 注意：本机固件（SWI9X50C_01.11.00.00）实测 `AT!GETBAND?` 会误报频段；
> `AT!CQI?`/`AT!MCS?` 等命令不存在；AMBR 类参数无法通过 AT/QMI 读取。
> 详见 [lte-cell-info.md](lte-cell-info.md)。
