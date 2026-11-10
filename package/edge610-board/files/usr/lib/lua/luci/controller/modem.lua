module("luci.controller.modem", package.seeall)

local ID_CACHE = "/tmp/.modem-id"

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
		local ts, man, mod, rev, imei, sv, fsn, imsi, iccid =
			s:match("^(%d+)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)$")
		if ts and t - tonum(ts) < 120 then
			return {
				manufacturer = man ~= "" and man or nil,
				model = mod ~= "" and mod or nil,
				revision = rev ~= "" and rev or nil,
				imei = imei ~= "" and imei or nil,
				imei_sv = sv ~= "" and sv or nil,
				fsn = fsn ~= "" and fsn or nil,
				imsi = imsi ~= "" and imsi or nil,
				iccid = iccid ~= "" and iccid or nil,
			}
		end
	end

	local o = at("ATI;+CIMI;+ICCID")
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
	}
	local w = io.open(ID_CACHE, "w")
	if w then
		w:write(string.format("%d|%s|%s|%s|%s|%s|%s|%s|%s", t,
			res.manufacturer or "", res.model or "", res.revision or "",
			res.imei or "", res.imei_sv or "", res.fsn or "",
			res.imsi or "", res.iccid or ""))
		w:close()
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
	return res
end

function data()
	local http = require "luci.http"

	local res = {
		sim = {}, net = {}, sig = {}, cell = {}, modem = {},
		neigh = { intra = {}, inter = {} },
		wan = wan_state(),
	}

	res.modem = identity()

	-- SIM / registration / operator / CSQ ---------------------------------
	local basic = at("AT+CPIN?;+CSQ;+COPS=3,0;+COPS?;+COPS=3,2;+COPS?;+CEREG?")
	res.sim.state = basic:match("+CPIN:%s*([%a ]+)")
	res.sig.csq = tonum(basic:match("+CSQ:%s*(%d+)"))
	res.sig.ber = tonum(basic:match("+CSQ:%s*%d+,(%d+)"))
	res.net.operator = basic:match('+COPS:%s*%d+,0,"([^"]*)"')
	res.net.plmn = basic:match('+COPS:%s*%d+,2,"([^"]*)"')
	res.net.act = tonum(basic:match('+COPS:%s*%d+,2,"[^"]*",(%d+)'))
	if res.net.operator == "????" then
		res.net.operator = nil
	end
	local cereg = parse_cereg(basic:match("+CEREG:%s*([^\r\n]+)"))
	res.net.reg = cereg.stat
	res.net.act = res.net.act or cereg.act
	res.cell.tac = cereg.tac
	res.cell.ci = cereg.ci

	-- Radio + neighbour cells ----------------------------------------------
	local radio = at("AT!GSTATUS?;!LTEINFO?")
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
			local earfcn, prio, pci, rsrq, rsrp, rssi, rxlev =
				l:match("^(%d+)%s+%d+%s+%d+%s+(%d+)%s+(%d+)%s+(-?[%d%.]+)%s+(-?[%d%.]+)%s+(-?[%d%.]+)%s+(-?%d+)$")
			if earfcn then
				res.neigh.inter[#res.neigh.inter + 1] = {
					earfcn = tonum(earfcn), prio = tonum(prio), pci = tonum(pci),
					rsrq = tonum(rsrq), rsrp = tonum(rsrp), rssi = tonum(rssi),
					rxlev = tonum(rxlev),
				}
			end
		end
	end

	-- Settings + data-connection state -------------------------------------
	local extra = at("AT!BAND?;!SELRAT?;!UIMS?;+CGDCONT?;!PCTEMP?;+CCLK?;+CGATT?;+CGACT?;+CGPADDR=1")
	res.net.bandlock = trim(extra:match("%d%d,%s*([%a][%a ]*)"))
	res.net.selrat = trim(extra:match("!SELRAT:%s*%d+,%s*([^\r\n]+)"))
	res.net.uims = tonum(extra:match("!UIMS:%s*(%d+)"))
	res.net.apn = extra:match('+CGDCONT:%s*%d+,"%a+","([^"]*)"')
	res.sig.temp_state = trim(extra:match("Temp state:%s*([%a ]+)"))
	res.modem.clock = extra:match("+CCLK:%s*\"([^\"]+)\"")
	res.wan.attach = tonum(extra:match("+CGATT:%s*(%d+)"))
	local cid, act = extra:match("+CGACT:%s*(%d+),(%d+)")
	res.wan.cid = tonum(cid)
	res.wan.context = tonum(act)
	res.wan.ip_modem = extra:match("+CGPADDR:%s*%d+,%s*([%d%.]+)")

	http.prepare_content("application/json")
	http.write_json(res)
end

-- Enable or disable the mobile data connection (PS attach + PDP context).
function setdata()
	local http = require "luci.http"
	local sys = require "luci.sys"

	if http.formvalue("enable") == "1" then
		sys.exec("/usr/bin/modem-at 'AT+CGATT=1' >/dev/null 2>&1")
		sys.exec("/usr/bin/modem-at 'AT+CGACT=1,1' >/dev/null 2>&1")
	else
		sys.exec("/usr/bin/modem-at 'AT+CGACT=0,1' >/dev/null 2>&1")
		sys.exec("/usr/bin/modem-at 'AT+CGATT=0' >/dev/null 2>&1")
	end

	http.prepare_content("application/json")
	http.write_json({ ok = true })
end

function index()
	if not nixio.fs.access("/usr/bin/modem-at") then
		return
	end

	entry({"admin", "status", "modem"}, firstchild(), _("Modem"), 60).dependent = false
	entry({"admin", "status", "modem", "status"}, template("modem/status"), _("Status"), 10).leaf = true
	entry({"admin", "status", "modem", "settings"}, template("modem/settings"), _("Settings"), 20).leaf = true
	entry({"admin", "status", "modem", "gps"}, template("modem/gps"), _("GPS"), 30).leaf = true
	entry({"admin", "status", "modem", "data"}, call("data")).leaf = true
	entry({"admin", "status", "modem", "setdata"}, call("setdata")).leaf = true
end
