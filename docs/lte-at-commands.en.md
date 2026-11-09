# EM7565 official AT command reference (41111748 Rev.2)

> Chinese version: [lte-at-commands.md](lte-at-commands.md)

> Source: *AirPrime EM75xx AT Command Reference* Rev.2 (Jan. 2019, 140 pages).
> Sierra proprietary commands (`AT!...`) are documented in chapters 3–11;
> chapter 12 only gives a support matrix for the 3GPP commands.
> Most `AT!` commands require `AT!ENTERCND="A710"` first.

## 1. Sierra proprietary commands

### 1.1 Password / status / customization (chapter 3)

| Command | Description | Page |
| --- | --- | --- |
| `!ENTERCND` | Enable access to password-protected commands | 16 |
| `!SETCND` | Set the AT command password | 17 |
| `!ANTSEL` | Set/query external antenna select configuration | 20 |
| `!BAND` | Select/return frequency band set | 22 |
| `!BOOTHOLD` | Reset modem and wait in bootloader for firmware download | 24 |
| `!CUSTOM` | Set/return customization settings (see below) | 25 |
| `!DATALOOPBACK` | Enable/disable and configure loopback mode | 28 |
| `!GCFEN` | Enable/disable GCF test mode | 29 |
| `!GETBAND` | Return the current active band | 29 |
| `!GSTATUS` | Return operational status (band/channel/TAC/ECI/RSRP/RSRQ/SINR) | 30 |
| `!HWID` | Display hardware version | 30 |
| `!IMPREF` | Query/set Image Management preferences | 31 |
| `!LTECA` | Enable/disable LTE CA or display supported CA pairs | 33 |
| `!LTEINFO` | Display LTE network information (serving cell + neighbours) | 35 |
| `!NVENCRYPTIMEI` | Write unencrypted IMEI to the modem | 37 |
| `!NVPLMN` | Provision/display the PLMN list for network personalization locking | 38 |
| `!PCINFO` | Return power control status information | 39 |
| `!PCOFFEN` | Set/return Power Off Enable state | 40 |
| `!PCTEMP` | Return current temperature information | 40 |
| `!PCTEMPLIMITS` | Set/report temperature state limit values | 41 |
| `!PCVOLT` | Return current power supply voltage information | 42 |
| `!PCVOLTLIMITS` | Set/report voltage state limit values | 43 |
| `!PRIID` | Set/report module PRI part number and revision | 44 |
| `!RESET` | Reset modem | 44 |
| `!SCACT` | Activate/deactivate data connection | 45 |
| `!TMSTATUS` | Report Thermal Mitigation Status | 46 |
| `!USBCOMP` | Set/report USB interface configuration | 47 |
| `!USBINFO` | Return information from the active USB descriptor | 48 |
| `!USBPID` | Set/report product ID in the USB descriptor | 49 |
| `!USBSPEED` | Set/report USB speed | 50 |
| `&V` | Return operating mode AT configuration parameters | 51 |

### 1.2 `!CUSTOM` sub-options (pages 25–28)

| Sub-option | Description |
| --- | --- |
| `CFUNPERSISTEN` | Whether +CFUN persists across power cycles |
| `CSVOICEREJECT` | Ignore incoming voice pages |
| `FASTENUMEN` | Fast USB enumeration |
| `GPIOSARENABLE` | SAR backoff controlled by GPIOs |
| `GPSENABLE` | GPS on/off |
| `GPSLPM` | GPS in low-power mode |
| `GPSREFLOC` | GPS location reporting |
| `GPSSEL` | GPS antenna type |
| `IPV6ENABLE` | IPv6 on/off |
| `NETWORKNAMEFMT` | MBIM provider name format |
| `PCSCDISABLE` | PCSC functionality |
| `QMIDETACHEN` | QMI NAS on/off |
| `REL8FASTDORMDIS` | Release 8 fast dormancy |
| `RRCREL7CAPDIS` | RRC Release 7 capability |
| `SIMHOTSWAPDIS` | SIM hot-swap detection (must be 1 on this board) |
| `SIMLPM` | Default low-power SIM state |
| `SINGLEAPNSWITCH` | Behavior when APN details change |
| `SKUID` | SKU ID |
| `UIM2ENABLE` | Second SIM interface |
| `USBSERIALENABLE` | Use the IMEI as the USB serial number |
| `WAKEHOSTEN` | Host wake-up method |

### 1.3 Diagnostic commands (chapter 4)

| Command | Description | Page |
| --- | --- | --- |
| `!BCFWUPDATESTATUS` | Report status of the most recent firmware update attempt | 53 |
| `!ERR` | Display diagnostic information | 54 |
| `!GCCLR` | Clear crash dump data | 54 |
| `!GCDUMP` | Display crash dump data | 55 |
| `!LTERXCONTROL` | Enable/disable LTE Rx diversity during Carrier Aggregation | 56 |
| `!RXDEN` | Enable/disable WCDMA/LTE/TD-SCDMA Rx diversity | 57 |

### 1.4 Test commands (chapter 5, requires `AT!DAFTMACT`)

| Command | Description | Page |
| --- | --- | --- |
| `!DACGPSCTON` | Return GPS CtoN and frequency measurement | 60 |
| `!DACGPSMASKON` | Set CGPS IQ log mask | 60 |
| `!DACGPSSTANDALONE` | Enter/exit StandAlone (SA) RF mode | 61 |
| `!DACGPSTESTMODE` | Start/stop the CGPS diagnostic task | 61 |
| `!DAFTMACT` | Put modem into Factory Test Mode | 62 |
| `!DAFTMDEACT` | Return to online mode from Factory Test Mode | 62 |
| `!DAGFTMRXAGC` | Get FTM Rx AGC | 63 |
| `!DALGRXAGC` | Return Rx AGC value (LTE only) | 64 |
| `!DALGTXAGC` | Return Tx AGC value and transmitter parameters (LTE only) | 65 |
| `!DALTXCONTROL` | Configure LTE Tx parameters (LTE only) | 67 |
| `!DAOFFLINE` | Place modem offline | 68 |
| `!DARCONFIG` | Set band and channel | 69 |
| `!DARCONFIGDROP` | Drop radio configurations | 70 |
| `!DAWTXCONTROL` | Configure WCDMA Tx parameters | 70 |

### 1.5 Memory management (chapter 6)

| Command | Description | Page |
| --- | --- | --- |
| `!NVBACKUP` | Back up device configuration | 72 |
| `!RMARESET` | Restore device configuration | 74 |

### 1.6 GNSS commands (chapter 7)

| Command | Description | Page |
| --- | --- | --- |
| `!GPSAUTOSTART` | Configure GPS auto-start features | 76 |
| `!GPSCLRASSIST` | Clear specific GPS assistance data | 78 |
| `!GPSCOLDSTART` | Clear all GNSS assistance data | 79 |
| `!GPSEND` | End an active session | 79 |
| `!GPSFIX` | Initiate a GPS position fix | 80 |
| `!GPSLBSAPN` | Set GPS LBS APNs | 81 |
| `!GPSLOC` | Return the last known location of the modem | 83 |
| `!GPSMOMETHOD` | Set/report the GPS MO method | 84 |
| `!GPSNMEACONFIG` | Enable and set the NMEA data output rate | 85 |
| `!GPSNMEASENTENCE` | Set/report the NMEA sentence type | 86 |
| `!GPSPORTID` | Set/report the port ID to use over TCP/IP | 87 |
| `!GPSSATINFO` | Request satellite information | 88 |
| `!GPSSTATUS` | Request the current status of a position fix session | 89 |
| `!GPSSUPLURL` | Set/report the SUPL server URL | 90 |
| `!GPSSUPLVER` | Set/report the SUPL server version | 91 |
| `!GPSTRACK` | Initiate a local tracking (multiple fix) session | 92 |
| `+WANT` | Enable/disable GNSS antenna power | 93 |

### 1.7 SIM / OMA-DM / SAR / AirVantage (chapters 8–11)

| Command | Description | Page |
| --- | --- | --- |
| `+UIMS` | Select the active SIM interface | 97 |
| `!HOSTDEVINFO` | Configure host device details | 99 |
| `!IMSTESTMODE` | Enable/disable IMS test mode | 100 |
| `!OSINFO` | Configure host device OS information | 101 |
| `!MAXPWR` | Set/report maximum Tx power | 103 |
| `!SARBACKOFF` | Set/report the offset from maximum Tx power | 104 |
| `!SARINTGPIOMODE` | Set/report the default pull mode for SAR interrupt GPIOs | 105 |
| `!SARSTATE` | Set/report the SAR backoff state | 106 |
| `!SARSTATEDFLT` | Set/report the default SAR backoff state | 107 |
| `+WDSC` | Configure AirVantage Management Services | 109 |
| `+WDSE` | Display the most recent AirVantage error | 111 |
| `+WDSG` | Display AirVantage status information | 112 |
| `+WDSI` | Activate/deactivate AirVantage unsolicited notifications | 113 |
| `+WDSR` | Reply to an AirVantage server request | 116 |

## 2. 3GPP standard commands (chapter 12)

The manual only provides a support matrix; syntax follows 3GPP TS 27.007 / 27.005 / V.250.

### 2.1 ITU-T V.250 (43 commands)

| Command | Supported | Description |
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

### 2.2 3GPP TS 27.005 (SMS, 25 commands)

| Command | Supported | Description |
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

### 2.3 3GPP TS 27.007 (106 commands)

| Command | Supported | Description |
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

## 3. Common commands

| Purpose | Commands |
| --- | --- |
| Module info | `ATI`, `AT+CGMI/CGMM/CGMR/CGSN` |
| Registration / cell | `AT+CEREG?`, `AT+COPS?`, `AT!GSTATUS?`, `AT!LTEINFO?` |
| Signal | `AT+CSQ`, `AT!LTEINFO?`, `AT!GSTATUS?` |
| Bands | `AT!BAND?`, `AT!GETBAND?` (unreliable) |
| SIM | `AT+CPIN?`, `AT+CIMI`, `AT+CCID`, `AT!UIMS` |
| APN/PDN | `AT+CGDCONT?`, `AT+CGACT?`, `AT+CGCONTRDP` |
| Temperature / voltage | `AT!PCTEMP?`, `AT!PCVOLT?`, `AT!TMSTATUS?` |
| CA | `AT!LTECA?` (capability), `AT!GSTATUS?` (state) |

> Note: on this firmware (`SWI9X50C_01.11.00.00`) `AT!GETBAND?` misreports the band;
> `AT!CQI?`/`AT!MCS?` do not exist; AMBR parameters cannot be read via AT or QMI.
> See [lte-cell-info.en.md](lte-cell-info.en.md).
