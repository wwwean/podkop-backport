#!/bin/sh
# shellcheck shell=dash
set -e

REPO="https://api.github.com/repos/wwwean/podkop-backport/releases/latest"
DOWNLOAD_DIR="/tmp/podkop"
COUNT=3
FIX_REPO=0

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
}

pkg_list_update() {
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk update
    else
        opkg update
        if [ $? -ne 0 ]; then
            if ! echo $MODEL | grep -qi "gl.inet"; then
                if [ $FIX_REPO -ne "1" ] ; then
                    msg_er "Failed to update packages list. Let's try fixing gl-inet repository feeds (.com --> .cn)."
                    repo_fix
                else
                    for file in /etc/opkg/*.conf; do
                        mv "${file}.back" "${file}" 2> /dev/null
                    done
                    msg_er "Failed to update packages list. Please try again later. The repository feeds have been rolled back."
                    exit 1
                fi
            else
                msg_er "Failed to update packages list. Please try again later."
                exit 1
            fi
        fi
    fi
    msg "Ok"
    msg
}

repo_fix() {
    msg "Backup default repository feeds"
    for file in /etc/opkg/*.conf; do
        if ! [ -f "${file}.back" ]; then
            cp "${file}" "${file}.back"
        fi
    done

    cat /etc/opkg/distfeeds.conf >> /etc/opkg/customfeeds.conf
    awk '!seen[substr($0, ($0 ~ /^#/ ? 2 : 1))]++' /etc/opkg/customfeeds.conf > /etc/opkg/customfeeds.conf.tmp && mv /etc/opkg/customfeeds.conf.tmp /etc/opkg/customfeeds.conf
    sed -i "/^#/! s/^/#/" /etc/opkg/distfeeds.conf
    sed -i "/^src\/gz /s|gl-inet.com|gl-inet.cn|g" /etc/opkg/customfeeds.conf
    # sed -i -E 's#(https?://[^/ ]*)\.org([/ ]|$)#\1.cn\2#g; s#(https?://[^/ ]*)\.com([/ ]|$)#\1.cn\2#g' /etc/opkg/distfeeds.conf
    FIX_REPO=1

    msg "Trying to update package list after fixing repository feeds."
    pkg_list_update
}

pkg_install() {
    local pkg_file="$1"

    if [ "$PKG_IS_APK" -eq 1 ]; then
        # Can't install without flag based on info from documentation
        # If you're installing a non-standard (self-built) package, use the --allow-untrusted option:
        if ! apk add --allow-untrusted "$pkg_file"; then
            exit 1
        fi
    else
        if ! opkg install --force-downgrade "$pkg_file"; then
            exit 1
        fi
    fi
}

pkg_download() {
    if ! nslookup google.com >/dev/null 2>&1; then
        msg_er "DNS is not working."
        exit 1
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

    tmpfile="$DOWNLOAD_DIR/urls.$$"
    trap 'rm -f "$tmpfile"' EXIT INT TERM
    wget --timeout=60 -qO- "$REPO" | grep -o "$grep_url_pattern" > "$tmpfile"
    while read -r url; do
        filename=$(basename "$url")
        filepath="$DOWNLOAD_DIR/$filename"

        attempt=0
        while [ $attempt -lt $COUNT ]; do
            msg "Download $filename (count $((attempt+1)))..."
            if wget --timeout=60 -q -O "$filepath" "$url"; then
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
            msg_er "Try again later"
            exit 1
        fi
    done < "$tmpfile"

    msg "Check if required packages were downloaded"
    for pkg in sing-box jq coreutils podkop luci-app-podkop luci-i18n-podkop; do
        if ! ls "$DOWNLOAD_DIR"/"$pkg"* >/dev/null 2>&1; then
            msg_er "$pkg was not downloaded successfully"
            exit 1
        fi
    done
    msg "Ok"
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
                cp /etc/config/podkop /etc/config/podkop-070
                if wget --timeout=60 -qO /etc/config/podkop https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/podkop/files/etc/config/podkop; then
                    msg "Podkop config has been reset to default. Your old config saved in /etc/config/podkop-070"
                    break
                else
                    msg_er "New podkop config was not downloaded successfully. Try again later"
                    exit 1
                fi
                ;;
            *)
                msg "Exit"
                exit 1
                ;;
        esac
    done
}

main() {
    # Get router model
    MODEL=$(cat /tmp/sysinfo/model)
    msg "Router model: $MODEL"
    msg

    msg "Check and prepare"
    prepare_system

    msg "Check sing-box"
    sing_box

    if [ -f "/etc/init.d/podkop" ]; then
        msg "Podkop is already installed. Upgrading..."
        /etc/init.d/podkop stop 2> /dev/null
        sleep 3

        # Check version
        msg "Check podkop version"
        if command -v podkop > /dev/null 2>&1; then
            local version
            version=$(/usr/bin/podkop show_version 2> /dev/null)
            if [ -n "$version" ]; then
                version=$(echo "$version" | sed -E 's/^backport(-|_)(dev_)?([0-9.]+).*/\3/')
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
    else
        msg "Installing podkop"
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
            msg "Ok"
            msg
        fi
    done

    ru=""
    for f in "$DOWNLOAD_DIR"/luci-i18n-podkop*; do
        if [ -f "$f" ]; then
            ru=$(basename "$f")
            break
        fi
    done
    if [ -n "$ru" ]; then
        if pkg_is_installed luci-i18n-podkop; then
                msg "Upgrading Russian translation..."
                pkg_remove luci-i18n-podkop*
                pkg_install "$DOWNLOAD_DIR/$ru"
                msg "Ok"
        else
            msg "Русский язык интерфейса ставим? y/n (Install the Russian interface language?)"
            while true; do
                read -r -p '' RUS
                case $RUS in
                y)
                    pkg_remove luci-i18n-podkop* > /dev/null 2>&1
                    pkg_install "$DOWNLOAD_DIR/$ru"
                    msg "Ok"
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
    msg

    find "$DOWNLOAD_DIR" -type f -name '*podkop*' -exec rm {} \;
    msg "Congratulations! Podkop is running now"
}

prepare_system() {
    msg "Check and update packages list"
    /usr/sbin/ntpd -q -p 194.190.168.1 -p 216.239.35.0 -p 216.239.35.4 -p 162.159.200.1 -p 162.159.200.123
    pkg_list_update || { msg_er "Packages list update failed"; exit 1; }

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
        msg "Check/Install iptables-mod-tproxy"
        pkg_install iptables-mod-tproxy
    else
        msg "Check/Install kmod-nft-tproxy"
        pkg_install kmod-nft-tproxy
    fi
    msg "Ok"
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

    msg "Download required packages"
    pkg_download

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
    msg "Ok"
    msg
}

sing_box() {
    if ! pkg_is_installed "^sing-box"; then
        msg_er "Sing-box is not installed"
        sing_box_install
    fi

    sing_box_version=$(sing-box version | sed -nE 's/.*version ([0-9.]+)(-extended-([0-9.]+))?/\1-\3/; T; s/-$//; p')
    # latest_version=$(curl -s https://api.github.com/repos/shtorm-7/sing-box-extended/releases/latest | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4 | sed 's/^v//' | sed -nE 's/([0-9.]+)(-.*)?/\1/p')
    latest_version=$(basename $(echo "$DOWNLOAD_DIR"/"sing-box"*) | sed -nE 's/^sing-box_backport-([0-9.]+)-extended-([0-9.]+)_.*/\1-\2/; T; s/-$//; p')
    required_version=$latest_version

    if [ "$(printf '%s\n%s\n' "$sing_box_version" "$required_version" | sort -V | head -n 1)" != "$required_version" ]; then
        msg_er "sing-box version $sing_box_version is older than the latest version"
        msg "Removing old version..."
        /etc/init.d/podkop stop > /dev/null 2>&1
        sleep 3
        pkg_remove sing-box

        msg "Install/update sing-box"
        sing_box_install
    fi
    msg "Ok"
    msg
}

sing_box_install() {
    sb=$(ls "$DOWNLOAD_DIR" | grep "sing-box" | head -n 1)
    pkg_install "$DOWNLOAD_DIR/$sb"
    sleep 3
}

main