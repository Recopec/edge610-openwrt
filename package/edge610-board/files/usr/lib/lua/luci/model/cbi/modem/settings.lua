local sys = require "luci.sys"

local m = Map("modem", translate("Modem settings"),
	translate("Band lock, SIM slot and radio mode are written to the modem NVRAM; the modem resets after Apply."))

local s = m:section(NamedSection, "main", "modem")
s.addremove = false

local o = s:option(ListValue, "sim", translate("SIM slot"))
o:value("0", translate("SIM1 (upper slot)"))
o:value("1", translate("SIM2 (lower slot, not wired on the Edge 610)"))

o = s:option(ListValue, "rat", translate("Radio mode"))
o:value("00", translate("Automatic"))
o:value("06", translate("LTE only"))

o = s:option(ListValue, "band", translate("Band lock"))
o:value("00", translate("All bands"))
o:value("01", "LTE B1 (2100 MHz)")
o:value("03", "LTE B3 (1800 MHz)")
o:value("05", "LTE B5 (850 MHz)")
o:value("08", "LTE B8 (900 MHz)")
o:value("41", "LTE B41 (2600 MHz TDD)")

local masks = {
	["01"] = "0000000000000001",
	["03"] = "0000000000000004",
	["05"] = "0000000000000010",
	["08"] = "0000000000000080",
	["41"] = "0000010000000000",
}

function m.on_after_commit(self)
	local sim = self.uci:get("modem", "main", "sim") or "0"
	local rat = self.uci:get("modem", "main", "rat") or "06"
	local band = self.uci:get("modem", "main", "band") or "00"

	sys.exec("/usr/bin/modem-at 'AT!ENTERCND=\"A710\"'")
	if band == "00" then
		sys.exec("/usr/bin/modem-at 'AT!BAND=00'")
	elseif masks[band] then
		sys.exec("/usr/bin/modem-at 'AT!BAND=0B,\"B" .. band .. "\",0," .. masks[band] .. ",0,0,0,0'")
		sys.exec("/usr/bin/modem-at 'AT!BAND=0B'")
	end
	sys.exec("/usr/bin/modem-at 'AT!UIMS=" .. sim .. "'")
	sys.exec("/usr/bin/modem-at 'AT!SELRAT=" .. rat .. "'")
	sys.exec("/usr/bin/modem-at 'AT!RESET'")
end

return m
