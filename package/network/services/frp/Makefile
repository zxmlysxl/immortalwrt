include $(TOPDIR)/rules.mk

PKG_NAME:=frp
PKG_VERSION:=0.70.1
PKG_RELEASE:=2

PKG_PROVIDES := frpc frps

PKG_SOURCE:=$(PKG_NAME)_$(PKG_VERSION)_linux_x86_64.tar.gz
PKG_HASH:=skip

PKG_MAINTAINER:=zuoxm <zxmlysxl@gmail.com>
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/frpc
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=frpc - Fast Reverse Proxy client
  URL:=https://github.com/fatedier/frp
endef

define Package/frpc/description
  frpc is the client of frp, a fast reverse proxy to help you expose
  a local server behind a NAT or firewall to the internet.
endef

define Package/frps
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=frps - Fast Reverse Proxy server
  URL:=https://github.com/fatedier/frp
endef

define Package/frps/description
  frps is the server of frp, receives proxied traffic from frpc.
endef

define Download/frp
  FILE:=$(PKG_SOURCE)
  URL:=https://github.com/fatedier/frp/releases/download/v$(PKG_VERSION)/
  HASH:=skip
endef
$(eval $(call Download,frp))

define Build/Prepare
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)
	mv $(PKG_BUILD_DIR)/frp-*/* $(PKG_BUILD_DIR)/ 2>/dev/null || true
endef

define Package/frpc/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/frpc $(1)/usr/bin/frpc
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/frpc.init $(1)/etc/init.d/frpc
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/frpc.config $(1)/etc/config/frpc
endef

define Package/frps/install
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/frps $(1)/usr/bin/frps
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/frps.init $(1)/etc/init.d/frps
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/frps.config $(1)/etc/config/frps
endef

$(eval $(call Package,frpc))
$(eval $(call Package,frps))
$(eval $(call BuildPackage,frpc))
$(eval $(call BuildPackage,frps))
