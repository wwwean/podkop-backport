include $(TOPDIR)/rules.mk

PKG_NAME:=podkop

#PKG_VERSION:= $(if $(PKG_VERSION),$(PKG_VERSION),backport_0.7.20_$(shell date +%d%m%Y-%H%M%S))
PKG_VERSION:= $(if $(PKG_VERSION),$(PKG_VERSION),backport-0.7.20)

PKG_MAINTAINER:=ITDog <podkop@itdog.info>
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+sing-box +curl +jq +coreutils +bind-dig +bind-nslookup
	CONFLICTS:=https-dns-proxy nextdns luci-app-passwall luci-app-passwall2
	TITLE:=Domain routing app
	URL:=https://podkop.net
	PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
	Domain routing. Use of VLESS, Shadowsocks technologies
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh

grep -q "105 podkop" /etc/iproute2/rt_tables && sed -i "/105 podkop/d" /etc/iproute2/rt_tables

/etc/init.d/podkop stop 2> /dev/null

exit 0
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/podkop
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/podkop $(1)/etc/init.d/podkop

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/podkop $(1)/etc/config/podkop

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/podkop $(1)/usr/bin/podkop

	$(INSTALL_DIR) $(1)/usr/lib/podkop
	$(CP) ./files/usr/lib/* $(1)/usr/lib/podkop/

	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(PKG_VERSION)/g' $(1)/usr/lib/podkop/constants.sh
endef

$(eval $(call BuildPackage,$(PKG_NAME)))