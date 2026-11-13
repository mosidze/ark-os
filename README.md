# ARK-OS («Цифровой Ковчег»)

Офлайн-дистрибутив для восстановления инфраструктуры из того, что уцелело: один образ на любом x86_64 железе (от NUC до сервера с GPU), роль узла выбирается после загрузки, узлы собираются в k3s-кластер с общим доменом, SSO и панелью.

Статус: **скелет ARK-Core (слой 0)**. Ни разу не собирался и не загружался на железе, всё ниже нужно проверить первой сборкой.

## Слои

| Слой | Что | Где |
| --- | --- | --- |
| 0. ARK-Core | загрузочная флешка 32 ГБ: Debian 13, k3s, детект, мастер | этот репозиторий |
| 1. Паки ролей | OCI-образы и манифесты ролей | позже |
| 2. Контент-паки | знания, модели ИИ, карты, медиа, dev-зеркала, toolbox, docs, telecom | позже |
| 3. Данные узла | зашифрованный том на узле | позже |

Подробно: [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/OPEN-QUESTIONS.md](docs/OPEN-QUESTIONS.md).

## Сборка

Нужен Debian 13 (хост или привилегированный контейнер) и root.

```sh
sudo apt install live-build debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
    gdisk dosfstools e2fsprogs mtools curl fdisk
sudo ./core/build.sh          # out/ark-core.iso, out/ark-core.img, out/SHA256SUMS
SKIP_DISK=1 ./core/build.sh   # только ISO, без loop-устройств
tests/qemu-smoke.sh out/ark-core.iso bios   # или uefi
```

`tools/fetch-vendor.sh` скачивает k3s и airgap-образы, проверяет контрольные суммы и фиксирует версию в `tools/vendor.lock`.

## Структура

```
core/            конфиг live-build, хуки, файлы, попадающие в образ
  config/includes.chroot/usr/local/lib/ark/ark-detect   детект железа -> hw.json, labels.json
  config/includes.chroot/usr/local/bin/ark-wizard       мастер первой загрузки (web + tty1)
  config/includes.chroot/etc/ark/roles.json             каталог ролей и аппаратные лимиты
grub/grub.cfg    меню загрузки (слоты A/B, toram, safe, clone)
tools/           fetch-vendor.sh, mkdisk.sh (сборка образа 32 ГБ)
tests/           unit-тесты логики ролей, QEMU smoke
```

## Что работает в скелете, чего нет

Есть: детект железа и labels узла, каталог из 18 ролей с аппаратными лимитами, мастер с токеном и защитой от перебора, сборка ISO и диска A/B, меню GRUB, CI.

Нет (следующие этапы): `ark-net` (выбор интерфейса, проба на чужой DHCP, режим собственного DHCP), `ark-k3s` (init/join кластера из `provision.json`), шифрованный том данных, механизм паков, автооткат слотов A/B, клонирование флешки, SSO и панель.
