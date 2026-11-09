module("luci.controller.modem", package.seeall)

function index()
	if not nixio.fs.access("/usr/bin/modem-at") then
		return
	end

	entry({"admin", "status", "modem"}, firstchild(), _("Modem"), 60).dependent = false
	entry({"admin", "status", "modem", "status"}, template("modem/status"), _("Status"), 10).leaf = true
	entry({"admin", "status", "modem", "settings"}, cbi("modem/settings"), _("Settings"), 20).leaf = true
end
