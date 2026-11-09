include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

PKG_NAME:=edge610-board
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0

define KernelPackage/edge610-switch
  SUBMENU:=Network Devices
  TITLE:=Edge 610 X553/switch pre-initializer (runs before ixgbe probes)
  DEPENDS:=@PCI_SUPPORT @TARGET_x86
  FILES:=$(PKG_BUILD_DIR)/edge610_switch_standalone.ko
  # Intentionally NO AUTOLOAD: /etc/init.d/edge610 loads this module with
  # explicit board parameters BEFORE ixgbe, guaranteeing probe order.
endef

define KernelPackage/edge610-dsa
  SUBMENU:=Network Devices
  TITLE:=Marvell 88E6190 DSA switch for Edge 610 (6x RJ45 behind conduit)
  DEPENDS:=+kmod-dsa +kmod-dsa-mv88e6xxx
  FILES:=$(PKG_BUILD_DIR)/edge610_dsa.ko
endef

define KernelPackage/i2c-ismt
  SUBMENU:=I2C support
  TITLE:=Intel iSMT SMBus host controller (Edge 610 hardware watchdog bus)
  DEPENDS:=@PCI_SUPPORT @TARGET_x86 +kmod-i2c-core +kmod-i2c-smbus
  KCONFIG:=CONFIG_I2C_ISMT
  FILES:=$(LINUX_DIR)/drivers/i2c/busses/i2c-ismt.ko
  AUTOLOAD:=$(call AutoLoad,52,i2c-ismt)
endef

define Package/edge610-board
  SECTION:=utils
  CATEGORY:=Base system
  TITLE:=VMware SD-WAN Edge 610 board support
  DEPENDS:=+kmod-edge610-switch +kmod-edge610-dsa +kmod-i2c-ismt +kmod-ixgbe \
	+i2c-tools +ip-full +sfdisk +partx-utils +resize2fs
endef

define Package/edge610-board/description
  Board bring-up for the VMware SD-WAN Edge 610 (Dell VEP1400):
  disables the PIC hardware watchdog over the iSMT SMBus, initializes
  the X553 conduit and Marvell 88E6190 switch before ixgbe probes,
  registers the DSA switch (lan1..lan6), ships first-boot network
  defaults and the prebuilt OpenClash mihomo core (amd64-v1).
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(KERNEL_MAKE) M="$(PKG_BUILD_DIR)" modules
endef

define Package/edge610-board/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/edge610 $(1)/etc/init.d/edge610
	$(INSTALL_DIR) $(1)/etc/modprobe.d
	$(INSTALL_DATA) ./files/etc/modprobe.d/edge610.conf $(1)/etc/modprobe.d/edge610.conf
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DATA) ./files/etc/uci-defaults/zzz99-edge610-network $(1)/etc/uci-defaults/zzz99-edge610-network
	$(INSTALL_BIN) ./files/etc/uci-defaults/zzz98-edge610-resize $(1)/etc/uci-defaults/zzz98-edge610-resize
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/verify-device $(1)/usr/bin/verify-device
	$(INSTALL_BIN) ./files/usr/bin/modem-at $(1)/usr/bin/modem-at
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/modem $(1)/etc/config/modem
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/controller/modem.lua $(1)/usr/lib/lua/luci/controller/modem.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/modem
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/view/modem/status.htm $(1)/usr/lib/lua/luci/view/modem/status.htm
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/view/modem/gps.htm $(1)/usr/lib/lua/luci/view/modem/gps.htm
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/modem
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/model/cbi/modem/settings.lua $(1)/usr/lib/lua/luci/model/cbi/modem/settings.lua
	$(INSTALL_DIR) $(1)/etc/openclash/core
	$(INSTALL_BIN) ./files/etc/openclash/core/clash_meta $(1)/etc/openclash/core/clash_meta
endef

$(eval $(call KernelPackage,edge610-switch))
$(eval $(call KernelPackage,edge610-dsa))
$(eval $(call KernelPackage,i2c-ismt))
$(eval $(call BuildPackage,edge610-board))
