module("luci.controller.modem", package.seeall)

local ID_CACHE = "/tmp/.modem-id"
-- The status page polls this; a short server-side cache keeps several open
-- tabs (or a refresh click) from queueing on the AT port.
local DATA_CACHE = "/tmp/.modem-data"
local DATA_TTL = 5

local function at(cmd)
	local sys = require "luci.sys"
	return sys.exec("/usr/bin/modem-at '" .. cmd .. "' 2>/dev/null") or ""
end

local function lines(s)
	local t = {}
	for l in s:gmatch("[^\r\n]+") do
		l = l:gsub("^%s+", ""):gsub("%s+$", "")
		if #l > 0 then t[#t + 1] = l end
	end
	return t
end

local function trim(s)
	if not s then return nil end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split(s)
	local t = {}
	for x in s:gmatch("%S+") do t[#t + 1] = x end
	return t
end

local function tonum(v)
	return tonumber(v)
end

local function unquote(s)
	if not s then return nil end
	return (s:gsub('"', ''))
end

local function parse_cereg(line)
	if not line then return {} end
	local f = split(line:gsub(",", " "))
	return {
		stat = tonum(f[2]),
		tac = unquote(f[3]),
		-- Sierra reports six fields: <n>,<stat>,<tac>,<rac>,<ci>,<act>
		ci = unquote(f[5] or f[4]),
		act = tonum(f[#f]),
	}
end

-- Identity changes only when the SIM or firmware does; cache it.
local function identity()
	local t = os.time()
	local f = io.open(ID_CACHE, "r")
	if f then
		local s = f:read("*a") or ""
		f:close()
		local ts, man, mod, rev, imei, sv, fsn, imsi, iccid, pripn, prirev, pricus =
			s:match("^(%d+)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)$")
		if ts and t - tonum(ts) < 120 and (mod ~= "" or imei ~= "") then
			return {
				manufacturer = man ~= "" and man or nil,
				model = mod ~= "" and mod or nil,
				revision = rev ~= "" and rev or nil,
				imei = imei ~= "" and imei or nil,
				imei_sv = sv ~= "" and sv or nil,
				fsn = fsn ~= "" and fsn or nil,
				imsi = imsi ~= "" and imsi or nil,
				iccid = iccid ~= "" and iccid or nil,
				pri_pn = pripn ~= "" and pripn or nil,
				pri_rev = prirev ~= "" and prirev or nil,
				pri_customer = pricus ~= "" and pricus or nil,
			}
		end
	end

	local o = at("ATI;+CIMI;+ICCID")
	local sys = require "luci.sys"
	local pri = sys.exec("/usr/bin/modem-at -p 'AT!PRIID?' 2>/dev/null") or ""
	local res = {
		manufacturer = o:match("Manufacturer:%s*([^\r\n]+)"),
		model = o:match("Model:%s*([^\r\n]+)"),
		revision = o:match("Revision:%s*([^\r\n]+)"),
		imei = o:match("IMEI:%s*(%d+)"),
		imei_sv = o:match("IMEI SV:%s*(%d+)"),
		fsn = o:match("FSN:%s*(%w+)"),
		imsi = (function()
			for _, l in ipairs(lines(o)) do
				if l:match("^%d+$") and #l >= 14 and #l <= 16 then return l end
			end
		end)(),
		iccid = o:match("ICCID:%s*([%w]+)"),
		pri_pn = pri:match("PRI Part Number:%s*(%w+)"),
		pri_rev = pri:match("Revision:%s*([%w%.]+)"),
		pri_customer = trim(pri:match("Customer:%s*([^\r\n]+)")),
	}
	local w = (res.model or res.imei) and io.open(ID_CACHE, "w")
	if w then
		w:write(string.format("%d|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s", t,
			res.manufacturer or "", res.model or "", res.revision or "",
			res.imei or "", res.imei_sv or "", res.fsn or "",
			res.imsi or "", res.iccid or "",
			res.pri_pn or "", res.pri_rev or "", res.pri_customer or ""))
		w:close()
	end
	return res
end

-- The name a phone shows is the EONS/PNN name sent by the network
-- (MM Information), not the SIM SPN that AT+COPS reports.  Only the QMI
-- NAS "get PLMN name" message exposes it; qmicli ships with qmi-utils.
local NAME_CACHE = "/tmp/.modem-name"

local function net_name(plmn)
	if not plmn or plmn == "" then return {} end
	local t = os.time()
	local f = io.open(NAME_CACHE, "r")
	if f then
		local s = f:read("*a") or ""
		f:close()
		local ts, key, long, short, local_ = s:match("^(%d+)|(.-)|(.-)|(.-)|(.-)$")
		if ts and key == plmn and t - tonum(ts) < 600 then
			return {
				long = long ~= "" and long or nil,
				short = short ~= "" and short or nil,
				local_name = local_ ~= "" and local_ or nil,
			}
		end
	end
	local nixio = require "nixio.fs"
	if not nixio.access("/usr/bin/qmicli") then return {} end
	local sys = require "luci.sys"
	local o = sys.exec("timeout -k 2 6 /usr/bin/qmicli -d /dev/cdc-wdm0 --nas-get-plmn-name=" .. plmn .. " 2>/dev/null") or ""
	local res = {
		long = trim(o:match("Long Name:%s*'([^']*)'")),
		short = trim(o:match("Short Name:%s*'([^']*)'")),
		local_name = trim(o:match("'([^']*)'%s*%)%s*Country:%s*'zh%-simp'"))
			or trim(o:match("'([^']*)'%s*%)%s*Country:%s*'zh")),
	}
	if res.long then
		local w = io.open(NAME_CACHE, "w")
		if w then
			w:write(string.format("%d|%s|%s|%s|%s", t, plmn, res.long, res.short or "", res.local_name or ""))
			w:close()
		end
	end
	return res
end

local function wan_state()
	local res = {}
	local f = io.open("/sys/class/net/wwan0/operstate", "r")
	if f then
		res.operstate = trim(f:read("*l"))
		f:close()
	end
	for _, k in ipairs({ "rx_bytes", "tx_bytes" }) do
		local g = io.open("/sys/class/net/wwan0/statistics/" .. k, "r")
		if g then
			res[k:gsub("_bytes", "")] = tonum(g:read("*l"))
			g:close()
		end
	end
	local sys = require "luci.sys"
	local o = sys.exec("ip -4 -o addr show dev wwan0 2>/dev/null")
	res.ip = o and o:match("inet%s+([%d%.]+)")
	-- Session age: operstate is always "unknown" for qmi_wwan, so netifd's
	-- uptime is the only useful freshness signal for the mobile link.
	local u = sys.exec("ubus -S call network.interface.wwan status 2>/dev/null")
	res.uptime = u and tonum(u:match('"uptime":(%d+)'))
	return res
end

function data()
	local http = require "luci.http"

	local now = os.time()
	local cf = io.open(DATA_CACHE, "r")
	if cf then
		local s = cf:read("*a") or ""
		cf:close()
		local ts, body = s:match("^(%d+)\n([%s%S]*)$")
		if ts and now - tonum(ts) <= DATA_TTL and #body > 64 then
			http.prepare_content("application/json")
			http.write(body)
			return
		end
	end

	local res = {
		sim = {}, net = {}, sig = {}, cell = {}, modem = {},
		neigh = { intra = {}, inter = {} },
		wan = wan_state(),
	}

	res.modem = identity()

	-- SIM / registration / operator / CSQ / radio / extras ----------------
	-- One modem-at line for everything that is read-only: three separate calls
	-- cost ~5.3 s of serial time, the merged line ~2.5 s. AT!SELRAT? must stay
	-- on a line of its own, chaining it makes the modem answer garbage.
	local all = at("AT+CPIN?;+CSQ;+COPS=3,0;+COPS?;+COPS=3,2;+COPS?;+CEREG?;"
		.. "!GSTATUS?;!LTEINFO?;!BAND?;!UIMS?;+CGDCONT?;!PCTEMP?;+CCLK?;+CGATT?;+CGACT?;+CGPADDR=1")
	local basic, radio, extra = all, all, all
	local bandblk = all:match("Index, Name[%s%S]-!UIMS:") or ""
	-- A missing/unreadable SIM answers "+CME ERROR: SIM failure" instead of
	-- "+CPIN: READY"; without the fallback the page just showed an empty row.
	res.sim.state = basic:match("+CPIN:%s*([%a ]+)") or basic:match("%+CME ERROR:%s*([%a ]+)")
	res.sig.csq = tonum(basic:match("+CSQ:%s*(%d+)"))
	res.sig.ber = tonum(basic:match("+CSQ:%s*%d+,(%d+)"))
	res.net.operator = basic:match('+COPS:%s*%d+,0,"([^"]*)"')
	res.net.plmn = basic:match('+COPS:%s*%d+,2,"([^"]*)"')
	res.net.act = tonum(basic:match('+COPS:%s*%d+,2,"[^"]*",(%d+)'))
	if res.net.operator == "????" then
		res.net.operator = nil
	end
	-- A leftover AT+CSCS="UCS2" makes the modem answer +COPS in hex.
	if res.net.operator and res.net.operator:match("^%x+$") then
		res.net.operator = nil
	end
	local nm = net_name(res.net.plmn)
	res.net.name_long = nm.long
	res.net.name_short = nm.short
	res.net.name_local = nm.local_name
	local cereg = parse_cereg(basic:match("+CEREG:%s*([^\r\n]+)"))
	res.net.reg = cereg.stat
	res.net.act = res.net.act or cereg.act
	res.cell.tac = cereg.tac
	res.cell.ci = cereg.ci

	-- Radio + neighbour cells ----------------------------------------------
	res.sig.temp = tonum(radio:match("Temperature:%s*(%d+)"))
	res.modem.uptime = tonum(radio:match("Current Time:%s*(%d+)"))
	res.modem.reset_count = tonum(radio:match("Reset Counter:%s*(%d+)"))
	res.net.mode = trim(radio:match("Mode:%s*([%a ]+)"))
	res.net.sysmode = trim(radio:match("System mode:%s*(%a+)"))
	res.net.ps = trim(radio:match("PS state:%s*([%a ]+)"))
	res.net.emm = trim(radio:match("EMM state:%s*([%a ]+)"))
	res.net.rrc = trim(radio:match("RRC state:%s*([%a ]+)"))
	res.net.ims = trim(radio:match("IMS reg state:%s*([%a ]+)"))
	res.sig.txpower = tonum(radio:match("Tx Power:%s*(-?%d+)"))
	res.sig.rssi_rxd = tonum(radio:match("PCC RxD RSSI:%s*(-?%d+)"))
	res.sig.rsrp_rxd = tonum(radio:match("PCC RxD RSRP:%s*(-?%d+)"))
	res.cell.band = radio:match("LTE band:%s*(%w+)")
	res.cell.bw = tonum(radio:match("LTE bw:%s*(%d+)"))
	res.cell.earfcn_dl = tonum(radio:match("LTE Rx chan:%s*(%d+)"))
	res.cell.earfcn_ul = tonum(radio:match("LTE Tx chan:%s*(%d+)"))
	res.sig.rssi = tonum(radio:match("PCC RxM RSSI:%s*(-?%d+)"))
	res.sig.rsrp = tonum(radio:match("PCC RxM RSRP:%s*(-?%d+)"))
	res.sig.rsrq = tonum(radio:match("RSRQ %(dB%):%s*(-?[%d%.]+)"))
	res.sig.sinr = tonum(radio:match("SINR %(dB%):%s*(-?[%d%.]+)"))

	-- carrier aggregation (secondary cells)
	local scc = {}
	for n, state in radio:gmatch("LTE SSC(%d) state:%s*([^\r\n]+)") do
		if not state:match("NOT ASSIGNED") then
			scc[#scc + 1] = {
				n = tonum(n), state = trim(state),
				band = radio:match("LTE SSC" .. n .. " band:%s*(%w+)"),
				bw = tonum(radio:match("LTE SSC" .. n .. " bw:%s*(%d+)")),
				earfcn_dl = tonum(radio:match("LTE SSC" .. n .. " Rx chan:%s*(%d+)")),
			}
		end
	end
	if #scc > 0 then res.cell.scc = scc end

	-- Serving row + intra/inter neighbours
	local mode
	for _, l in ipairs(lines(radio)) do
		if l:match("^Serving:") then
			mode = "serving"
		elseif l:match("^IntraFreq:") then
			mode = "intra"
		elseif l:match("^InterFreq:") then
			mode = "inter"
		elseif l:match("^WCDMA:") then
			mode = "wcdma"
		elseif mode == "serving" and l:match("^%d") then
			local f = split(l)
			-- EARFCN MCC MNC TAC CID Bd D U SNR PCI RSRQ RSRP RSSI RXLV
			res.cell.mcc = f[2]
			res.cell.mnc = f[3]
			res.cell.tac = res.cell.tac or f[4]
			res.cell.ci = res.cell.ci or f[5]
			res.cell.dl_mod = f[7]
			res.cell.ul_mod = f[8]
			res.cell.snr = tonum(f[9])
			res.cell.pci = tonum(f[10])
			res.cell.rxlev = tonum(f[14])
			if not res.cell.band and f[6] then
				res.cell.band = "B" .. f[6]
			end
		elseif mode == "intra" then
			local pci, rsrq, rsrp, rssi, rxlev =
				l:match("^(%d+)%s+(-?[%d%.]+)%s+(-?[%d%.]+)%s+(-?[%d%.]+)%s+(-?%d+)$")
			if pci then
				res.neigh.intra[#res.neigh.intra + 1] = {
					pci = tonum(pci), rsrq = tonum(rsrq), rsrp = tonum(rsrp),
					rssi = tonum(rssi), rxlev = tonum(rxlev),
				}
			end
		elseif mode == "inter" then
			local earfcn, tlow, thigh, prio, pci, rsrq, rsrp, rssi, rxlev =
				l:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(-?[%d%.]+)%s+(-?[%d%.]+)%s+(-?[%d%.]+)%s+(-?%d+)$")
			if earfcn then
				res.neigh.inter[#res.neigh.inter + 1] = {
					earfcn = tonum(earfcn), tlow = tonum(tlow), thigh = tonum(thigh),
					prio = tonum(prio), pci = tonum(pci),
					rsrq = tonum(rsrq), rsrp = tonum(rsrp), rssi = tonum(rssi),
					rxlev = tonum(rxlev),
				}
			end
		end
	end

	-- Settings + data-connection state -------------------------------------
	res.net.bandlock = trim(bandblk:match("%d%d,%s*([%a][%a ]*)"))
	-- !SELRAT? has to be its own command line: chained with ';' x'after !BAND?
	-- the modem answers "Unknown RAT mode. Use AT!SELRAT to set band." instead
	-- of the stored mode, in any position.
	local selraw = at("AT!SELRAT?"):match("!SELRAT:%s*([^\r\n]+)")
	local selname = { ["00"] = "Automatic", ["06"] = "LTE Only" }
	local code = selraw and trim(selraw):match("^(%d%d),")
	if code and selname[code] then
		res.net.selrat = selname[code]
	else
		-- The modem intermittently answers the "Unknown RAT mode" complaint even
		-- for a plain query; the mode we wrote is the better answer then.
		local uci = require("luci.model.uci").cursor()
		res.net.selrat = selname[uci:get("modem", "main", "rat") or ""] or "?"
	end
	res.net.uims = tonum(extra:match("!UIMS:%s*(%d+)"))
	res.net.apn = extra:match('+CGDCONT:%s*%d+,"[%w]+","([^"]*)"')
	res.sig.temp_state = trim(extra:match("Temp state:%s*([%a ]+)"))
	res.modem.clock = extra:match("+CCLK:%s*\"([^\"]+)\"")
	local cy, cmo, cd, ch, cmi, cs, ctz =
		(res.modem.clock or ""):match("(%d+)/(%d+)/(%d+),(%d+):(%d+):(%d+)([+-]?%d+)")
	if cy then
		local off = tonum(ctz) * 900
		res.modem.clock_epoch = os.time({
			year = 2000 + tonum(cy), month = tonum(cmo), day = tonum(cd),
			hour = tonum(ch), min = tonum(cmi), sec = tonum(cs),
		}) - off
		res.modem.clock_tz = off
	end
	res.wan.attach = tonum(extra:match("+CGATT:%s*(%d+)"))
	local cid, act = extra:match("+CGACT:%s*(%d+),(%d+)")
	res.wan.cid = tonum(cid)
	res.wan.context = tonum(act)
	res.wan.ip_modem = extra:match("+CGPADDR:%s*%d+,%s*([%d%.]+)")

	local body = require("luci.jsonc").stringify(res)
	local wf = io.open(DATA_CACHE, "w")
	if wf then
		wf:write(now .. "\n" .. body)
		wf:close()
	end
	http.prepare_content("application/json")
	http.write(body)
end

-- Enable or disable the mobile data connection (PS attach + PDP context).
function setdata()
	local http = require "luci.http"
	local sys = require "luci.sys"

	-- When the modem is bound as a WAN interface, let netifd own the call:
	-- an AT-activated context fights uqmi --start-network and the interface
	-- ends up without an address.
	local bound = (sys.exec("ubus -S list network.interface.wwan 2>/dev/null") or "") ~= ""

	if http.formvalue("enable") == "1" then
		sys.exec("/usr/bin/modem-at 'AT+CGATT=1' >/dev/null 2>&1")
		if bound then
			sys.exec("ifup wwan >/dev/null 2>&1")
		else
			sys.exec("/usr/bin/modem-at 'AT+CGACT=1,1' >/dev/null 2>&1")
		end
	else
		if bound then
			sys.exec("ifdown wwan >/dev/null 2>&1")
		end
		sys.exec("/usr/bin/modem-at 'AT+CGACT=0,1' >/dev/null 2>&1")
		sys.exec("/usr/bin/modem-at 'AT+CGATT=0' >/dev/null 2>&1")
	end

	http.prepare_content("application/json")
	http.write_json({ ok = true })
end

-- Network scan (AT+COPS=? blocks for up to a minute, so run it detached).
function scan()
	local http = require "luci.http"
	local sys = require "luci.sys"

	local f = io.open("/tmp/.modem-scan", "r")
	if f then
		local s = f:read("*a") or ""
		f:close()
		local list = {}
		for st, name, plmn, act in s:gmatch('%((%d),"([^"]*)","[^"]*","(%d+)",(%d+)%)') do
			list[#list + 1] = { status = tonum(st), name = name, plmn = plmn, act = tonum(act) }
		end
		if #list > 0 then
			http.prepare_content("application/json")
			http.write_json({ operators = list })
			return
		end
		local started = tonum(s:match("^(%d+)"))
		if started and os.time() - started < 90 then
			http.prepare_content("application/json")
			http.write_json({ running = true })
			return
		end
	end

	os.remove("/tmp/.modem-scan")
	sys.exec("nohup sh -c 'printf \"%d\\n\" $(date +%s); /usr/bin/modem-at -t 90 \"AT+COPS=?\" 2>&1' > /tmp/.modem-scan 2>&1 &")
	http.prepare_content("application/json")
	http.write_json({ running = true })
end

-- Automatic or manual network selection.
function setnet()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local plmn = http.formvalue("plmn")
	if plmn and plmn:match("^%d+$") then
		sys.exec("/usr/bin/modem-at 'AT+COPS=1,2,\"" .. plmn .. "\"' >/dev/null 2>&1")
	else
		sys.exec("/usr/bin/modem-at 'AT+COPS=0' >/dev/null 2>&1")
	end
	http.prepare_content("application/json")
	http.write_json({ ok = true })
end

-- SMS list (text mode) and delete.
-- UCS2 hex (what the modem returns for non-GSM text) -> UTF-8
local function ucs2(s)
	if #s >= 4 and #s % 4 == 0 and s:match("^[0-9A-Fa-f]+$") then
		local out = {}
		for i = 1, #s, 4 do
			local cp = tonumber(s:sub(i, i + 3), 16)
			if cp < 0x80 then
				out[#out + 1] = string.char(cp)
			elseif cp < 0x800 then
				out[#out + 1] = string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
			else
				out[#out + 1] = string.char(0xE0 + math.floor(cp / 0x1000),
					0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
			end
		end
		return table.concat(out)
	end
	return s
end

local function utf8chars(s)
	local t, i = {}, 1
	while i <= #s do
		local c = s:byte(i)
		local n = 1
		if c >= 0xF0 then
			n = 4
		elseif c >= 0xE0 then
			n = 3
		elseif c >= 0xC0 then
			n = 2
		end
		t[#t + 1] = s:sub(i, i + n - 1)
		i = i + n
	end
	return t
end

local GSM7 = utf8chars("@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ\27ÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà")
local GSM7EXT = { [0x0A] = "\f", [0x14] = "^", [0x28] = "{", [0x29] = "}", [0x2F] = "\\", [0x3C] = "[", [0x3D] = "~", [0x3E] = "]", [0x40] = "|", [0x65] = "€" }

-- GSM 03.38 septet unpacking; skip is the number of leading septets to drop
local function unpack7(hex, skip)
	local bytes = {}
	for i = 1, #hex, 2 do
		bytes[#bytes + 1] = tonumber(hex:sub(i, i + 1), 16) or 0
	end
	local sept = {}
	local acc, bits = 0, 0
	for i = 1, #bytes do
		acc = acc + bytes[i] * 2 ^ bits
		bits = bits + 8
		while bits >= 7 do
			sept[#sept + 1] = acc % 128
			acc = math.floor(acc / 128)
			bits = bits - 7
		end
	end
	local out, esc = {}, false
	for i = (skip or 0) + 1, #sept do
		local c = sept[i]
		if esc then
			out[#out + 1] = GSM7EXT[c] or "?"
			esc = false
		elseif c == 0x1B then
			esc = true
		else
			out[#out + 1] = GSM7[c + 1] or "?"
		end
	end
	return table.concat(out)
end

local function bcd_num(hex, len, toa)
	local d = {}
	for i = 1, #hex, 2 do
		local b = tonumber(hex:sub(i, i + 1), 16) or 0
		d[#d + 1] = b % 16
		local hi = math.floor(b / 16)
		if hi ~= 15 then
			d[#d + 1] = hi
		end
	end
	local out = table.concat(d):sub(1, len)
	if toa == 0x91 then
		out = "+" .. out
	end
	return out
end

local function scts_str(h)
	local function pair(p)
		return (tonumber(p:sub(2, 2), 16) or 0) * 10 + (tonumber(p:sub(1, 1), 16) or 0)
	end
	local tz = tonumber(h:sub(13, 14), 16) or 0
	local sign = (tz % 16) >= 8 and "-" or "+"
	local q = (tz % 8) * 10 + math.floor(tz / 16)
	return string.format("%02d/%02d/%02d,%02d:%02d:%02d%s%d",
		pair(h:sub(1, 2)), pair(h:sub(3, 4)), pair(h:sub(5, 6)),
		pair(h:sub(7, 8)), pair(h:sub(9, 10)), pair(h:sub(11, 12)),
		sign, math.floor(q / 4))
end

-- returns from, scts, text, ref, total, seq for a SMS-DELIVER PDU
local function pdu_parse(hex)
	local i = 1
	local smsc_len = tonumber(hex:sub(i, i + 1), 16) or 0
	i = i + 2 + smsc_len * 2
	local fo = tonumber(hex:sub(i, i + 1), 16) or 0
	i = i + 2
	if fo % 2 == 1 then
		return nil
	end
	local oa_len = tonumber(hex:sub(i, i + 1), 16) or 0
	i = i + 2
	local toa = tonumber(hex:sub(i, i + 1), 16) or 0
	i = i + 2
	local oa_hex = hex:sub(i, i + math.ceil(oa_len / 2) * 2 - 1)
	i = i + math.ceil(oa_len / 2) * 2
	local from = bcd_num(oa_hex, oa_len, toa)
	i = i + 2
	local dcs = tonumber(hex:sub(i, i + 1), 16) or 0
	i = i + 2
	local when = scts_str(hex:sub(i, i + 13))
	i = i + 14
	local udl = tonumber(hex:sub(i, i + 1), 16) or 0
	i = i + 2
	local ud = hex:sub(i, i + udl * 2 - 1)

	local ref, total, seq, udh_octets = nil, nil, nil, 0
	-- TP-UDHI (bit 6 of the first octet) tells whether a UDH is present;
	-- without it the first UD octet is already the text
	local udhi = math.floor(fo / 0x40) % 2 == 1
	local udhl = udhi and (tonumber(ud:sub(1, 2), 16) or 0) or 0
	if udhl > 0 then
		udh_octets = udhl + 1
		local j = 3
		while j <= udhl * 2 + 1 do
			local iei = tonumber(ud:sub(j, j + 1), 16) or 0
			local iedl = tonumber(ud:sub(j + 2, j + 3), 16) or 0
			if iei == 0x00 and iedl == 3 then
				ref = tonumber(ud:sub(j + 4, j + 5), 16)
				total = tonumber(ud:sub(j + 6, j + 7), 16)
				seq = tonumber(ud:sub(j + 8, j + 9), 16)
			end
			j = j + 4 + iedl * 2
		end
	end

	local text
	local coding = dcs % 0x10
	if coding == 0x08 then
		text = ucs2(ud:sub(udh_octets * 2 + 1))
	elseif coding == 0x00 then
		text = unpack7(ud, udh_octets > 0 and math.ceil(udh_octets * 8 / 7) or 0)
	else
		text = ud:sub(udh_octets * 2 + 1)
	end
	return from, when, text, ref, total, seq
end

function sms()
	local http = require "luci.http"
	local sys = require "luci.sys"

	local o = sys.exec("/usr/bin/modem-at -t 20 'AT+CMGF=0;+CMGL=4' 2>/dev/null") or ""
	local raw, cur = {}, nil
	for _, l in ipairs(lines(o)) do
		local idx, stat = l:match("^%+CMGL:%s*(%d+),(%d+)")
		if idx then
			cur = { index = tonum(idx), stat = tonum(stat) }
			raw[#raw + 1] = cur
		elseif cur and l:match("^[0-9A-Fa-f]+$") then
			cur.pdu = l
			cur = nil
		end
	end

	local list = {}
	for _, r in ipairs(raw) do
		if r.pdu then
			local from, when, text, ref, total, seq = pdu_parse(r.pdu)
			if from then
				local stat = ({ [0] = "REC UNREAD", [1] = "REC READ", [2] = "STO UNSENT", [3] = "STO SENT" })[r.stat] or tostring(r.stat)
				list[#list + 1] = {
					index = r.index, stat = stat, from = from, time = when,
					text = text, ref = ref, total = total, seq = seq,
				}
			end
		end
	end

	-- a long SMS arrives as several parts; group by concat reference (or by
	-- sender + timestamp when the carrier did not add a UDH) and order by
	-- the UDH sequence number
	local groups, order = {}, {}
	for _, m in ipairs(list) do
		local key = m.ref and ("ref:" .. m.ref .. ":" .. m.from) or (m.from .. "|" .. m.time)
		local g = groups[key]
		if not g then
			g = { from = m.from, time = m.time, stat = m.stat, index = m.index, parts = {} }
			groups[key] = g
			order[#order + 1] = key
		end
		g.parts[#g.parts + 1] = m
		if m.index < g.index then
			g.index = m.index
		end
	end
	local out = {}
	for _, key in ipairs(order) do
		local g = groups[key]
		table.sort(g.parts, function(a, b)
			return (a.seq or a.index) < (b.seq or b.index)
		end)
		local text = {}
		for _, p in ipairs(g.parts) do
			text[#text + 1] = p.text
		end
		out[#out + 1] = {
			index = g.index, stat = g.stat, from = g.from, time = g.time,
			text = table.concat(text), parts = #g.parts,
		}
	end

	http.prepare_content("application/json")
	http.write_json({ messages = out })
end

function smsdel()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local idx = http.formvalue("idx")
	if idx and idx:match("^%d+$") then
		sys.exec("/usr/bin/modem-at 'AT+CMGD=" .. idx .. "' >/dev/null 2>&1")
	end
	http.prepare_content("application/json")
	http.write_json({ ok = true })
end

function atrun()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local cmd = trim(http.formvalue("cmd") or "")
	if #cmd == 0 or #cmd > 1024 then
		http.status(400, "Bad Request")
		http.prepare_content("text/plain")
		http.write("empty or too long command\n")
		return
	end
	local to = tonum(http.formvalue("timeout")) or 3
	if to < 1 then
		to = 1
	elseif to > 120 then
		to = 120
	end
	local quoted = "'" .. cmd:gsub("'", "'\\''") .. "'"
	local out = sys.exec("MODEM_AT_TIMEOUT=" .. to .. " /usr/bin/modem-at " .. quoted .. " 2>&1")
	http.prepare_content("text/plain")
	http.write(out or "")
end

-- The RF view was folded into the status page; keep old links working.
function signal_moved()
	local http = require "luci.http"
	local disp = require "luci.dispatcher"
	http.redirect(disp.build_url("admin", "status", "modem", "status"))
end

local function utf8_to_ucs2hex(s)
	local out, i = {}, 1
	while i <= #s do
		local c = s:byte(i)
		local cp, n
		if c < 0x80 then
			cp, n = c, 1
		elseif c < 0xE0 then
			cp, n = (c - 0xC0) * 0x40 + (s:byte(i + 1) - 0x80), 2
		elseif c < 0xF0 then
			cp, n = (c - 0xE0) * 0x1000 + (s:byte(i + 1) - 0x80) * 0x40 + (s:byte(i + 2) - 0x80), 3
		else
			cp, n = (c - 0xF0) * 0x40000 + (s:byte(i + 1) - 0x80) * 0x1000 +
				(s:byte(i + 2) - 0x80) * 0x40 + (s:byte(i + 3) - 0x80), 4
		end
		out[#out + 1] = string.format("%04X", cp)
		i = i + n
	end
	return table.concat(out)
end

function smsend()
	local http = require "luci.http"
	local sys = require "luci.sys"

	local num = trim(http.formvalue("number") or "")
	local txt = http.formvalue("text") or ""
	if not num:match("^%+?%d+$") or #txt == 0 or #txt > 400 then
		http.status(400, "Bad Request")
		http.prepare_content("application/json")
		http.write_json({ ok = false, error = "bad input" })
		return
	end

	local cs, payload, arg = "GSM", txt, num
	if txt:match("[^\32-\126]") then
		-- non-GSM text: build a SMS-SUBMIT PDU with a UCS2 body
		local n = num:gsub("[^%d%+]", "")
		local intl = n:sub(1, 1) == "+"
		if intl then
			n = n:sub(2)
		end
		local bcd = {}
		for i = 1, #n, 2 do
			local a = n:sub(i, i)
			local b = n:sub(i + 1, i + 1)
			if b == "" then
				b = "F"
			end
			bcd[#bcd + 1] = string.format("%X%X", tonumber(b, 16), tonumber(a, 16))
		end
		local da = string.format("%02X%02X%s", #n, intl and 0x91 or 0x81, table.concat(bcd))
		local ud = utf8_to_ucs2hex(txt)
		-- 0x11 = SMS-SUBMIT with a relative VP, so the AA VP octet is valid
		local tpdu = "1100" .. da .. "0008AA" .. string.format("%02X", #ud / 2) .. ud
		cs = "PDU"
		payload = "00" .. tpdu          -- 00 = use the default SMSC
		arg = tostring(#tpdu / 2)       -- CMGS length excludes the SMSC part
	end

	local out = sys.exec("/usr/bin/modem-sms-send '" .. arg .. "' " .. cs .. " '" .. payload:gsub("'", "'\\''") .. "' 2>&1") or ""
	local ok = out:match("OK") and not out:match("ERROR") and not out:match("\+CMS ERROR")
	if ok then
		local esc = txt:gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\n", "\\n")
		local f = io.open("/etc/modem-sms-sent", "a")
		if f then
			f:write(os.time() .. "\t" .. num .. "\t" .. esc .. "\n")
			f:close()
		end
	end
	http.prepare_content("application/json")
	http.write_json({ ok = ok, output = trim(out) })
end

function smssent()
	local http = require "luci.http"
	local out = {}
	local f = io.open("/etc/modem-sms-sent", "r")
	if f then
		for l in f:lines() do
			local t, n, x = l:match("^(%d+)\t([^\t]*)\t(.*)$")
			if t then
				x = x:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\\\", "\\")
				out[#out + 1] = { t = tonum(t), number = n, text = x }
			end
		end
		f:close()
	end
	http.prepare_content("application/json")
	http.write_json({ messages = out })
end

function index()
	if not nixio.fs.access("/usr/bin/modem-at") then
		return
	end

	entry({"admin", "status", "modem"}, firstchild(), _("Modem"), 60).dependent = false
	entry({"admin", "status", "modem", "status"}, template("modem/status"), _("Status"), 10).leaf = true
	-- no title: resolves for old bookmarks without showing up as a tab
	entry({"admin", "status", "modem", "signal"}, call("signal_moved")).leaf = true
	entry({"admin", "status", "modem", "settings"}, template("modem/settings"), _("Settings"), 20).leaf = true
	entry({"admin", "status", "modem", "gps"}, template("modem/gps"), _("GPS"), 30).leaf = true
	entry({"admin", "status", "modem", "data"}, call("data")).leaf = true
	entry({"admin", "status", "modem", "setdata"}, call("setdata")).leaf = true
	entry({"admin", "status", "modem", "scan"}, call("scan")).leaf = true
	entry({"admin", "status", "modem", "setnet"}, call("setnet")).leaf = true
	entry({"admin", "status", "modem", "sms"}, template("modem/sms"), _("SMS"), 40).leaf = true
	entry({"admin", "status", "modem", "sms", "list"}, call("sms")).leaf = true
	entry({"admin", "status", "modem", "sms", "delete"}, call("smsdel")).leaf = true
	entry({"admin", "status", "modem", "sms", "send"}, call("smsend")).leaf = true
	entry({"admin", "status", "modem", "sms", "sent"}, call("smssent")).leaf = true
	entry({"admin", "status", "modem", "at"}, template("modem/at"), _("AT"), 45).leaf = true
	entry({"admin", "status", "modem", "at", "run"}, call("atrun")).leaf = true
end
