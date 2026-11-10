module("luci.controller.modem", package.seeall)

local function at(cmd)
	local sys = require "luci.sys"
	return sys.exec("/usr/bin/modem-at '" .. cmd .. "' 2>/dev/null") or ""
end

local function tonum(v)
	local n = tonumber(v)
	return n
end

local function unquote(s)
	if not s then return nil end
	return (s:gsub('"', ''))
end

local function parse_cereg(line)
	if not line then return {} end
	local f = {}
	for x in line:gmatch("[^,]+") do f[#f + 1] = x end
	return {
		stat = tonum(f[2]),
		tac = unquote(f[3]),
		-- Sierra reports six fields: <n>,<stat>,<tac>,<rac>,<ci>,<act>
		ci = unquote(f[5] or f[4]),
		act = tonum(f[#f]),
	}
end

function data()
	local http = require "luci.http"

	local res = {
		sim = {}, net = {}, sig = {}, cell = {}, modem = {},
	}

	-- Identity -----------------------------------------------------------
	local id = at("ATI")
	res.modem.manufacturer = id:match("Manufacturer:%s*([^\r\n]+)")
	res.modem.model = id:match("Model:%s*([^\r\n]+)")
	res.modem.revision = id:match("Revision:%s*([^\r\n]+)")
	res.modem.imei = id:match("IMEI:%s*(%d+)")

	-- SIM / registration / operator / CSQ ---------------------------------
	local basic = at("AT+CPIN?;+CSQ;+COPS=3,0;+COPS?;+COPS=3,2;+COPS?;+CEREG?")
	res.sim.state = basic:match("+CPIN:%s*([%a ]+)")
	res.sig.csq = tonum(basic:match("+CSQ:%s*(%d+)"))
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

	-- IMSI / ICCID ---------------------------------------------------------
	res.sim.imsi = at("AT+CIMI"):match("(%d%d%d%d%d%d%d%d%d%d%d%d%d%d+)")
	res.sim.iccid = at("AT+ICCID"):match("ICCID:%s*([%w]+)")

	-- Radio status ---------------------------------------------------------
	local gs = at("AT!GSTATUS?")
	res.sig.temp = tonum(gs:match("Temperature:%s*(%d+)"))
	res.net.sysmode = gs:match("System mode:%s*(%a+)")
	res.net.ps = gs:match("PS state:%s*([%a ]+)")
	res.net.emm = gs:match("EMM state:%s*([%a ]+)")
	res.cell.band = gs:match("LTE band:%s*(%w+)")
	res.cell.bw = tonum(gs:match("LTE bw:%s*(%d+)"))
	res.cell.earfcn_dl = tonum(gs:match("LTE Rx chan:%s*(%d+)"))
	res.cell.earfcn_ul = tonum(gs:match("LTE Tx chan:%s*(%d+)"))
	res.sig.rssi = tonum(gs:match("PCC RxM RSSI:%s*(-?%d+)"))
	res.sig.rsrp = tonum(gs:match("PCC RxM RSRP:%s*(-?%d+)"))
	res.sig.rsrq = tonum(gs:match("RSRQ %(dB%):%s*(-?[%d%.]+)"))
	res.sig.sinr = tonum(gs:match("SINR %(dB%):%s*(-?[%d%.]+)"))

	-- PCI from the LTE info table ------------------------------------------
	local lte = at("AT!LTEINFO?")
	local serving = lte:match("Serving:[^\r\n]*[\r\n]+%s*([^\r\n]+)")
	if serving then
		local f = {}
		for x in serving:gmatch("%S+") do f[#f + 1] = x end
		res.cell.pci = tonum(f[10])
		res.cell.tac = res.cell.tac or f[4]
		res.cell.ci = res.cell.ci or f[5]
		if not res.cell.band and f[6] then
			res.cell.band = "B" .. f[6]
		end
	end

	http.prepare_content("application/json")
	http.write_json(res)
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
end
