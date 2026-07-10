#!/bin/sh
# shellcheck shell=dash

REPO="https://api.github.com/repos/wwwean/podkop-backport/releases/latest"
DOWNLOAD_DIR="/tmp/podkop"
COUNT=3

# Cached flag to switch between ipk or apk package managers
PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

rm -rf "$DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"

msg() {
    printf "\033[32;1m%s\033[0m\n" "$1"
}

msg_er() {
    printf "\033[31m%s\033[0m\n" "$1"
}

pkg_is_installed () {
    local pkg_name="$1"

    if [ "$PKG_IS_APK" -eq 1 ]; then
        # grep -q should work without change based on example from documentation
        # apk list --installed --providers dnsmasq
        # <dnsmasq> dnsmasq-full-2.90-r3 x86_64 {feeds/base/package/network/services/dnsmasq} (GPL-2.0) [installed]
        apk list --installed | grep -q "$pkg_name"
    else
        opkg list-installed | grep -q "$pkg_name"
    fi
}

pkg_remove() {
    local pkg_name="$1"

    if [ "$PKG_IS_APK" -eq 1 ]; then
        # TODO: check --force-depends flag
        # Nothing here: https://openwrt.org/docs/guide-user/additional-software/opkg-to-apk-cheatsheet
        apk del "$pkg_name"
    else
        opkg remove --force-depends "$pkg_name"
    fi
    msg
}

pkg_list_update() {
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk update
    else
        if opkg update; then
            exit 0
        else
            msg_er "Something went wrong. Let's try fixing the repository (.com --> .cn)"
            msg
            fix_owrtrepo
        fi
    fi
}

fix_owrtrepo() {
    for file in /etc/opkg/*.conf; do
        if ! [ -f "${file}.back" ]; then
            cp "${file}" "${file}.back"
        fi
    done
    cat /etc/opkg/distfeeds.conf >> /etc/opkg/customfeeds.conf
    awk '!seen[$0]++' /etc/opkg/customfeeds.conf > /etc/opkg/customfeeds.conf.tmp && mv /etc/opkg/customfeeds.conf.tmp /etc/opkg/customfeeds.conf
    #sed -i "/^#/! s/^/#/" /etc/opkg/distfeeds.conf
    #sed -i "/^src\/gz openwrt_/s|openwrts.org|openwrt.org|g" /etc/opkg/customfeeds.conf
    # if [ "$PKG_IS_APK" -eq 1 ]; then
    #     apk update
    # else
    #     opkg update
    # fi
}

pkg_install() {
    local pkg_file="$1"

    if [ "$PKG_IS_APK" -eq 1 ]; then
        # Can't install without flag based on info from documentation
        # If you're installing a non-standard (self-built) package, use the --allow-untrusted option:
        apk add --allow-untrusted "$pkg_file"
    else
        opkg install "$pkg_file"
    fi
    msg
}

update_config() {
    printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[48;5;196m\033[1m║ ! Обнаружена старая версия podkop.                                   ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Если продолжите обновление, вам потребуется настроить Podkop заново. ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Старая конфигурация будет сохранена в /etc/config/podkop-070         ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Подробности: https://github.com/itdoginfo/podkop                     ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Точно хотите продолжить?                                             ║\033[0m\n"
    printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"

    echo ""

    printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[48;5;196m\033[1m║ ! Detected old podkop version.                                       ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ If you continue the update, you will need to RECONFIGURE podkop.     ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Your old configuration will be saved to /etc/config/podkop-070       ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Details: https://github.com/itdoginfo/podkop                         ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Are you sure you want to continue?                                   ║\033[0m\n"
    printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"

    msg "Continue? (yes/no)"

    while true; do
            read -r -p '' CONFIG_UPDATE
            case $CONFIG_UPDATE in

            yes|y|Y)
                mv /etc/config/podkop /etc/config/podkop-070
                wget -O /etc/config/podkop https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/podkop/files/etc/config/podkop
                msg "Podkop config has been reset to default. Your old config saved in /etc/config/podkop-070"
                break
                ;;
            *)
                msg "Exit"
                exit 1
                ;;
        esac
    done
}

main() {
    /usr/sbin/ntpd -q -p 194.190.168.1 -p 216.239.35.0 -p 216.239.35.4 -p 162.159.200.1 -p 162.159.200.123
    pkg_list_update || { msg_er "Packages list update failed"; exit 1; }
    exit 1
    
    check_system
    sing_box


    if [ -f "/etc/init.d/podkop" ]; then
        msg "Podkop is already installed. Upgrading..."
    else
        msg "Installing podkop..."
    fi

    if command -v curl >/dev/null 2>&1; then
        check_response=$(curl -s "https://api.github.com/repos/wwwean/podkop-backport/releases/latest")

        if echo "$check_response" | grep -q 'API rate limit '; then
            msg_er "You've reached the GitHub rate limit. Repeat in five minutes."
            exit 1
        fi
    fi

    local grep_url_pattern
    if [ "$PKG_IS_APK" -eq 1 ]; then
        grep_url_pattern='https://[^"[:space:]]*\.apk'
    else
        grep_url_pattern='https://[^"[:space:]]*\.ipk'
    fi

    wget -qO- "$REPO" | grep -o "$grep_url_pattern" | while read -r url; do
        filename=$(basename "$url")
        filepath="$DOWNLOAD_DIR/$filename"

        attempt=0
        while [ $attempt -lt $COUNT ]; do
            msg "Download $filename (count $((attempt+1)))..."
            if wget -q -O "$filepath" "$url"; then
                if [ -s "$filepath" ]; then
                    msg "$filename successfully downloaded"
                    break
                fi
            fi
            msg "Download error for $filename. Retrying..."
            rm -f "$filepath"
            attempt=$((attempt+1))
        done

        if [ $attempt -eq $COUNT ]; then
            msg_er "Failed to download $filename after $COUNT attempts"
        fi
    done

    # Check if any files were downloaded
    if ! ls "$DOWNLOAD_DIR"/*podkop* >/dev/null 2>&1; then
        msg_er "No packages were downloaded successfully"
        exit 1
    fi

    for pkg in podkop luci-app-podkop; do
        file=""
        for f in "$DOWNLOAD_DIR"/"$pkg"*; do
            if [ -f "$f" ]; then
                file=$(basename "$f")
                break
            fi
        done
        if [ -n "$file" ]; then
            msg "Installing $file..."
            pkg_install "$DOWNLOAD_DIR/$file"
            sleep 3
        fi
    done

    ru=""
    for f in "$DOWNLOAD_DIR"/luci-i18n-podkop-ru*; do
        if [ -f "$f" ]; then
            ru=$(basename "$f")
            break
        fi
    done
    if [ -n "$ru" ]; then
        if pkg_is_installed luci-i18n-podkop-ru; then
                msg "Upgrading Russian translation..."
                pkg_remove luci-i18n-podkop*
                pkg_install "$DOWNLOAD_DIR/$ru"
        else
            msg "Русский язык интерфейса ставим? y/n (Install the Russian interface language?)"
            while true; do
                read -r -p '' RUS
                case $RUS in
                y)
                    pkg_remove luci-i18n-podkop*
                    pkg_install "$DOWNLOAD_DIR/$ru"
                    break
                    ;;
                n)
                    break
                    ;;
                *)
                    echo "Введите y или n"
                    ;;
                esac
            done
        fi
    fi

    find "$DOWNLOAD_DIR" -type f -name '*podkop*' -exec rm {} \;
}

check_system() {
    msg "Check and prepare system..."
    # Get router model
    MODEL=$(cat /tmp/sysinfo/model)
    msg "Router model: $MODEL"
    msg

    # Get OpenWrt version
    local openwrt_version=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d"'" -f2 | cut -d'.' -f1)

    # Check kmod-inet-diag
    msg "Check kmod-inet-diag"
    if ! opkg find kmod-inet-diag | grep -q "kmod-inet-diag"; then
        msg_er "The kmod-inet-diag package cannot be installed. Try installing manually or pre-integrating into the firmware and try again."
        msg 
        exit 1
    fi
    msg "Ok"
    msg

    # Check/Install Tproxy
    local def_openwrt_ver=21
    if [[ "$openwrt_version" -le "$def_openwrt_ver" ]]; then
        msg "Check/Install iptables-mod-tproxy..."
        pkg_install iptables-mod-tproxy
    else
        msg "Check/Install kmod-nft-tproxy"
        pkg_install kmod-nft-tproxy
    fi
    msg

    # Check available space
    AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=15360 # 15MB in KB
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        msg_er "Error: Insufficient space in flash"
        msg_er "Available: $((AVAILABLE_SPACE/1024))MB"
        msg_er "Required: $((REQUIRED_SPACE/1024))MB"
        exit 1
    fi
    if ! nslookup google.com >/dev/null 2>&1; then
        msg_er "DNS is not working."
        exit 1
    fi

    # Download required packages
    msg "Download required packages"
    local urls="https://downloads.openwrt.org/releases/packages-24.10/x86_64/packages/jq_1.8.1-r1_x86_64.ipk \
    https://downloads.openwrt.org/releases/packages-24.10/x86_64/packages/coreutils-base64_9.7-r1_x86_64.ipk"

    for url in $urls; do
        filename=$(basename "$url")
        filepath="$DOWNLOAD_DIR/$filename"

        attempt=0
        while [ $attempt -lt $COUNT ]; do
            msg "Download $filename (count $((attempt+1)))..."
            if wget -q -O "$filepath" "$url"; then
                if [ -s "$filepath" ]; then
                    msg "$filename successfully downloaded"
                    break
                fi
            fi
            msg "Download error for $filename. Retrying..."
            rm -f "$filepath"
            attempt=$((attempt+1))
        done

        if [ $attempt -eq $COUNT ]; then
            msg "Failed to download $filename after $COUNT attempts"
        fi
    done

    # Check if required files were downloaded
    for pkg in jq coreutils; do
        if ! ls "$DOWNLOAD_DIR"/"$pkg"* >/dev/null 2>&1; then
            msg_er "$pkg was not downloaded successfully"
            exit 1
        fi
    done
    msg

    msg "Install/Update required packages"
    for pkg in jq coreutils; do
        file=""
        for f in "$DOWNLOAD_DIR"/"$pkg"*; do
            if [ -f "$f" ]; then
                file=$(basename "$f")
                break
            fi
        done
        if [ -n "$file" ]; then
            msg "Installing $file..."
            pkg_install "$DOWNLOAD_DIR/$file"
            sleep 3
        fi
    done

    # Check version
    msg "Check podkop version (if installed)"
    if command -v podkop > /dev/null 2>&1; then
        local version
        version=$(/usr/bin/podkop show_version 2> /dev/null)
        if [ -n "$version" ]; then
            version=$(echo "$version" | sed -E 's/^backport_([0-9.]+).*/\1/')
            local major
            local minor
            local patch
            major=$(echo "$version" | cut -d. -f1 2> /dev/null) 
            minor=$(echo "$version" | cut -d. -f2 2> /dev/null)
            patch=$(echo "$version" | cut -d. -f3 2> /dev/null)

            # Compare version: must be >= 0.7.0
            if [ "$major" -gt 0 ] ||
                [ "$major" -eq 0 ] && [ "$minor" -gt 7 ] ||
                [ "$major" -eq 0 ] && [ "$minor" -eq 7 ] && [ "$patch" -ge 0 ]; then
                msg "Podkop version >= 0.7.0"
                break
            else
                msg "Podkop version < 0.7.0. Update config..."
                update_config
            fi
        else
            msg "Unknown podkop version. Update config..."
            update_config
        fi
    fi

    if pkg_is_installed https-dns-proxy; then
        msg "Conflicting package detected: https-dns-proxy. Remove?"

        while true; do
            read -r -p '' DNSPROXY
            case $DNSPROXY in

            yes|y|Y)
                pkg_remove luci-app-https-dns-proxy
                pkg_remove https-dns-proxy
                pkg_remove luci-i18n-https-dns-proxy*
                break
                ;;
            *)
                msg "Exit"
                exit 1
                ;;
            esac
        done
    fi
    msg "System is ready"
    msg "---------------------------------------------------------------------------"
    msg
}

sing_box() {
    msg "Check sing-box..."
    if ! pkg_is_installed "^sing-box"; then
        msg_er "Sing-box is not installed"
        sing_box_install
    fi

    sing_box_version=$(sing-box version | head -n 1 | awk '{print $3}')
    required_version="1.12.4"

    if [ "$(printf '%s\n%s\n' "$sing_box_version" "$required_version" | sort -V | head -n 1)" != "$required_version" ]; then
        msg_er "sing-box version $sing_box_version is older than the required version $required_version."
        msg "Removing old version..."
        service podkop stop > /dev/null 2>&1
        pkg_remove sing-box
        sleep 3
        sing_box_install
    fi
    msg "Sing-box successfully installed/update"
    msg "---------------------------------------------------------------------------"
    msg
}

sing_box_install() {
    msg "Install/update sing-box"
    sb=$(ls "$DOWNLOAD_DIR" | grep "sing-box" | head -n 1)
    pkg_install "$DOWNLOAD_DIR/$sb"
    sleep 3
}

main