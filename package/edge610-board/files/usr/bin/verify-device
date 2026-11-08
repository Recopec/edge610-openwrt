#!/bin/sh
# Edge 610 post-flash checks. Run on the router after the first boot:
#   sh /root/verify-device.sh          (or pipe it over the serial console)
# Everything here is read-only.

pass=0; fail=0
ok()   { echo "  [ OK ] $*"; pass=$((pass + 1)); }
bad()  { echo "  [FAIL] $*"; fail=$((fail + 1)); }
note() { echo "  [note] $*"; }

echo "== system =="
echo "  kernel : $(uname -r)"
echo "  model  : $(cat /tmp/sysinfo/model 2>/dev/null)"
echo "  uptime : $(uptime | sed 's/^ *//')"

echo
echo "== board bring-up (watchdog / switch / DSA) =="
log="$(logread -e edge610 2>/dev/null)"
echo "$log" | grep -q "watchdog: cleared register" && ok "watchdog cleared" || bad "watchdog not cleared (reboot in 4-5 min?)"
echo "$log" | grep -q "conduit:" && ok "conduit: $(echo "$log" | sed -n 's/.*conduit: \([a-z0-9]*\).*/\1/p' | tail -n1)" || bad "no conduit log"
for p in 1 2 3 4 5 6; do
	[ -e "/sys/class/net/lan$p" ] || { bad "lan$p missing"; break; }
done
[ -e /sys/class/net/lan6 ] && ok "lan1..lan6 present"

echo
echo "== links / MACs =="
ip -br link 2>/dev/null | grep -E '^(lan[1-6]|eth[0-9])' | sed 's/^/  /'
lan_macs="$(for p in 1 2 3 4 5 6; do cat "/sys/class/net/lan$p/address" 2>/dev/null; done | sort -u | wc -l)"
[ "$lan_macs" = "1" ] && note "all LAN ports share one MAC (normal for mv88e6xxx)" || note "LAN ports have $lan_macs distinct MACs"

echo
echo "== bridge =="
bridge link show 2>/dev/null | sed 's/^/  /' | head -n 10

echo
echo "== addresses =="
ip -br addr 2>/dev/null | sed 's/^/  /' | head -n 12

echo
echo "== storage (first-boot resize) =="
df -h / | sed 's/^/  /'
root_size="$(df -h / | awk 'NR==2 {print $2}')"
case "$root_size" in
*G) ok "root filesystem expanded ($root_size)" ;;
*) bad "root filesystem still small ($root_size) - resize did not run" ;;
esac

echo
echo "== thermal =="
if command -v sensors >/dev/null 2>&1; then
	sensors 2>/dev/null | grep -E 'Core|Package' | sed 's/^/  /' | head -n 4
fi
for z in /sys/class/thermal/thermal_zone*/temp; do
	[ -e "$z" ] && note "$z = $(cat "$z")"
done

echo
echo "== services / packages =="
[ -x /etc/openclash/core/clash_meta ] && ok "mihomo: $(/etc/openclash/core/clash_meta -v 2>/dev/null | head -n1)" || bad "clash_meta missing"
[ -d /www/luci-static/argon ] && ok "argon theme installed" || bad "argon theme missing"
if [ -e /usr/lib/lua/luci/controller/store.lua ] || [ -d /www/luci-static/resources/view/store ]; then
	ok "iStore installed"
else
	note "iStore files not found (check LuCI menu)"
fi
command -v dockerd >/dev/null 2>&1 && note "docker installed ($(dockerd --version 2>/dev/null | cut -d' ' -f3))" || note "docker not installed"

echo
echo "== enabled services =="
ls /etc/rc.d/S* 2>/dev/null | sed 's|/etc/rc.d/S||' | tr '\n' ' ' | fold -w 100 | sed 's/^/  /'
echo

echo "== result: $pass passed, $fail failed =="
[ "$fail" = 0 ] || echo "  -> see docs/bringup-log.md for troubleshooting"
exit 0
