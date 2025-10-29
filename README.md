# Podkop с поддержкой устаревших версий OpenWrt

Это оригинальный Podkop, в который добавлена поддержка iptables. Проверено на OpenWrt 21 (GL.iNet GL-MT6000 Flint 2), OpenWrt 24 (BPI R4).

# Вещи, которые нужно знать перед установкой
- Это бета-версия, которая находится в активной разработке. Из версии в версию что-то может меняться.
- При обновлении **обязательно** [сбрасывайте кэш LuCI](https://podkop.net/docs/clear-browser-cache/).
- Также при обновлении всегда заходите в конфигурацию и проверяйте свои настройки. Конфигурация может измениться.
- Необходимо минимум 15МБ свободногмсо места на роутере. Роутеры с флешками на 16МБ сразу мимо.
- **Наличие пакета kmod-inet-diag** ([см. здесь](#1-установка-sing-box-backport-требуется-версия-1124-или-новее)).
- При старте программы редактируется конфиг Dnsmasq.
- Podkop редактирует конфиг sing-box. Обязательно сохраните ваш конфиг sing-box перед установкой, если он вам нужен.
- [Если у вас что-то не работает.](https://podkop.net/docs/diagnostics/)
- Если у вас установлен Getdomains, [его следует удалить](https://github.com/itdoginfo/domain-routing-openwrt?tab=readme-ov-file#%D1%81%D0%BA%D1%80%D0%B8%D0%BF%D1%82-%D0%B4%D0%BB%D1%8F-%D1%83%D0%B4%D0%B0%D0%BB%D0%B5%D0%BD%D0%B8%D1%8F).

# Документация от разработчиков оригинального Podkop
https://podkop.net/

# Автоматическая установка
Заходим на роутер через ssh, скачиваем и запускаем установочный скрипт:
```
wget -O install-podkop.sh https://raw.githubusercontent.com/wwwean/podkop-backport/refs/heads/main/install.sh && chmod +x install-podkop.sh && ./install-podkop.sh
```

# Ручная установка
## 1. Установка Sing-box-backport (требуется версия 1.12.4 или новее)
На старых версиях OpenWrt этого пакета нет в репозиториях - качаем пакет из [релиза](https://github.com/wwwean/podkop-backport/releases/latest) и устанавливаем.\
Могут возникнуть сложности с пакетом kmod-inet-diag. На GL.iNet GL-MT6000 Flint 2 он подтянется из репозитория GL.iNet. Для чистой OpenWrt 21 есть [патч](https://github.com/openwrt/openwrt/commit/efc8aff62cb244583a14c30f8d099103b75ced1d.patch), добавляющий поддержку этого пакета.

## 2. Установка Podkop-backport
### Перед установкой нужно проверить наличие следующих пакетов:
a. Для версии OpenWrt до 21 включительно: iptables-mod-tproxy. Есть в репозитории, ставим через Luci или ssh.\
b. Для версии OpenWrt 22 и новее: kmod-nft-tproxy, установка аналогичная.\
Далее качаем и устанавливаем пакет из [релиза](https://github.com/wwwean/podkop-backport/releases/latest) через Luci или ssh.

## 3. Установка Luci App Podkop
Качаем и устанавливаем пакет из [релиза](https://github.com/wwwean/podkop-backport/releases/latest) через Luci или ssh. Русифицируем по желанию.

# Известные проблемы
Периодически глючат статусы FakeIP и Config. Сброс кэша (или перезапуск браузера) решает "проблему".


