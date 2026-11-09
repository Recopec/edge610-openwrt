include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-modemdata
PKG_VERSION:=1.0.31
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=Rafal Wabik (IceG), Cezary Jackiewicz

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-modemdata
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Modemdata modem dashboard (third-party, EM7565 supported)
  DEPENDS:=+sms-tool +comgt +kmod-usb-serial-option +libubox +jshn
endef

define Package/luci-app-modemdata/description
  LuCI dashboard for cellular modems: parsed signal/band/CA/cell data,
  SIM and modem info, SMS, band locking. The device list explicitly
  includes the Sierra Wireless EM7565. Upstream:
  https://github.com/4IceG/Modem-extras (luci-app-modemdata 1.0.31,
  modemdata 20260606-1).
endef

define Build/Compile
endef

define Package/luci-app-modemdata/install
	$(CP) ./files/. $(1)/
endef

$(eval $(call BuildPackage,luci-app-modemdata))
