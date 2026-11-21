# Dimbuntu

**Dimbuntu** — это маленький «свой» дистрибутив на базе **Ubuntu 24.04 LTS** с рабочим столом **Xfce** (в духе Xubuntu). Собирается с нуля из deb-пакетов Ubuntu и упаковывается в загрузочный live-ISO (BIOS + UEFI).

![Build](https://github.com/ehekufa/Dimbuntu/actions/workflows/build-iso.yml/badge.svg)

## Что внутри

- Ubuntu 24.04 LTS (noble), ядро `linux-image-generic`
- Рабочий стол Xfce из метапакета `xubuntu-core` (как у Xubuntu)
- LightDM + lightdm-gtk-greeter, браузер Epiphany, Thunar, xfce4-terminal
- Сеть через NetworkManager, индикатор раскладки `xfce4-xkb-plugin`
- **Русская локаль и раскладка по умолчанию** (us/ru, переключение Alt+Shift)
- Live-режим через `casper`: загрузка без установки, пользователь `dimbuntu`
- Без snapd — быстрая загрузка

## Как собрать через GitHub Actions (основной способ)

1. Открой вкладку **Actions** в репозитории → workflow **Build Dimbuntu ISO**.
2. Сборка запускается автоматически на каждый push, либо нажми **Run workflow**.
3. Когда програнение завершится — в нём появится артефакт **dimbuntu-24.04-amd64** (zip с ISO и SHA256SUMS). Скачай его.
4. При пуше тега `v*` (например `v24.04`) ISO автоматически прикладывается к GitHub Release.

## Как собрать локально

Нужен Ubuntu/Debian и пакеты:

```bash
sudo apt install debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools
sudo ./scripts/build.sh
```

Готовый ISO появится в `build/dimbuntu-24.04-amd64.iso`.

Переменные окружения: `DISTRO` (базовый релиз Ubuntu, по умолчанию `noble`), `VERSION` (версия Dimbuntu, по умолчанию `24.04`).

## Как записать на флешку

- **Windows:** Rufus, balenaEtcher или Ventoy.
- **Linux:**
  ```bash
  sudo dd if=build/dimbuntu-24.04-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
  ```

> ⚠️ **Secure Boot нужно отключить** в UEFI/BIOS — GRUB в образе не подписан. Обычная загрузка (UEFI или Legacy) работает.

## Первый запуск

- В меню GRUB выбери **Dimbuntu 24.04 (live)**.
- Вариант **whole image in RAM** целиком копирует систему в память (нужно 4+ ГБ RAM) — работает быстрее и позволяет вынуть флешку.
- Интернет: подключись через значок сети в трее. Ставить пакеты можно прямо в live-режиме: `sudo apt update && sudo apt install <пакет>`.

## Структура

```
scripts/build.sh              # вся сборка: debootstrap -> chroot -> squashfs -> grub-mkrescue
.github/workflows/build-iso.yml  # CI: сборка ISO на каждый push + артефакт/Release
build/                        # временные файлы сборки (в git не попадают)
```

## Идеи на будущее

- Установщик на диск (Calamares) и persist-режим для флешки
- Своя тема/обои/брендинг
- Сборка под ARM64
