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

-- LTE bands supported by the EM7565 (product spec Table 1-1).
-- AT!BAND extended masks: bit = band-1 in Lmask1 (bands 1-64),
-- bit = band-65 in Lmask2 (bands 65-128).
local bands = {
	{ 1,  "B1 (2100 MHz)" },   { 2,  "B2 (1900 MHz)" },   { 3,  "B3 (1800 MHz)" },
	{ 4,  "B4 (1700 MHz)" },   { 5,  "B5 (850 MHz)" },    { 7,  "B7 (2600 MHz)" },
	{ 8,  "B8 (900 MHz)" },    { 9,  "B9 (1800 MHz)" },   { 12, "B12 (700 MHz)" },
	{ 13, "B13 (700 MHz)" },   { 18, "B18 (850 MHz)" },   { 19, "B19 (850 MHz)" },
	{ 20, "B20 (800 MHz)" },   { 26, "B26 (850 MHz)" },   { 28, "B28 (700 MHz)" },
	{ 29, "B29 (700 MHz, DL only)" }, { 30, "B30 (2300 MHz, DL only)" },
	{ 32, "B32 (1500 MHz, DL only)" }, { 41, "B41 (2600 MHz TDD)" },
	{ 42, "B42 (3500 MHz TDD)" }, { 43, "B43 (3700 MHz TDD)" },
	{ 46, "B46 (5200 MHz LAA)" }, { 48, "B48 (3500 MHz CBRS)" },
	{ 66, "B66 (AWS-3)" },
}

o = s:option(MultiValue, "band", translate("Band lock"),
	translate("Tick the LTE bands to allow. Leave all unticked to use every band."))
o.widget = "checkbox"
o.delimiter = " "
o.rmempty = true
for _, b in ipairs(bands) do
	o:value(tostring(b[1]), b[2])
end

-- Lua 5.1 here has 32-bit integers, so build the 64-bit AT!BAND masks as hex
-- strings instead of formatting numbers.
local function hex64(bits)
	local d = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
	for _, b in ipairs(bits) do
		local q = math.floor(b / 4)
		d[16 - q] = d[16 - q] + 2 ^ (b % 4)
	end
	local h = "0123456789abcdef"
	local out = ""
	for i = 1, 16 do
		out = out .. h:sub(d[i] + 1, d[i] + 1)
	end
	return out
end

function m.on_after_commit(self)
	local sim = self.uci:get("modem", "main", "sim") or "0"
	local rat = self.uci:get("modem", "main", "rat") or "06"
	local list = self.uci:get("modem", "main", "band") or ""

	local l1bits, l2bits, n = {}, {}, 0
	for b in list:gmatch("%d+") do
		local band = tonumber(b)
		if band and band >= 1 and band <= 64 then
			l1bits[#l1bits + 1] = band - 1
			n = n + 1
		elseif band and band >= 65 and band <= 128 then
			l2bits[#l2bits + 1] = band - 65
			n = n + 1
		end
	end

	-- -p unlocks password-protected commands in the same AT session
	if n == 0 or n == #bands then
		sys.exec("/usr/bin/modem-at -p 'AT!BAND=00'")
	else
		sys.exec("/usr/bin/modem-at -p 'AT!BAND=0B,\"custom\",0,"
			.. hex64(l1bits) .. "," .. hex64(l2bits) .. ",0,0,0'")
		sys.exec("/usr/bin/modem-at -p 'AT!BAND=0B'")
	end
	sys.exec("/usr/bin/modem-at 'AT!UIMS=" .. sim .. "'")
	sys.exec("/usr/bin/modem-at -p 'AT!SELRAT=" .. rat .. "'")
	sys.exec("/usr/bin/modem-at 'AT!RESET'")
end

return m
