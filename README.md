# Dimbuntu Tiny

**Dimbuntu Tiny** — крошечный «свой» live-дистрибутив на базе **Tiny Core Linux (CorePlus)**. Итоговый ISO весит **~110 МБ** — в ~14 раз меньше прежней Ubuntu-сборки, грузится за секунды.

![Build](https://github.com/ehekufa/Dimbuntu/actions/workflows/build-iso.yml/badge.svg)

## Что это такое

Скрипт берёт официальный CorePlus ISO, распаковывает его и пересобирает со своими настройками:

- пункт меню **«Dimbuntu Tiny (Russian keyboard)»** по умолчанию — русская консольная раскладка (`kmap=ru`) и имя хоста `dimbuntu`
- фирменные названия в меню загрузки, метка тома `DIMBUNTU_TINY`
- гибридный ISO с isohybrid-MBR — можно писать на флешку через `dd`

Внутри CorePlus: графическое окружение FLTK (flwm + wbar), набор утилит, установщик на диск, поддержка Wi-Fi и не-англоязычных раскладок.

## Скачивание

GitHub → **Actions** → зелёный прогон **Build Dimbuntu Tiny ISO** → **Download artifacts** → `dimbuntu-tiny-x86` (внутри ISO + SHA256SUMS). Артефакт хранится 30 дней. На тегах `v*` ISO автоматически прикладывается к Releases.

## Запуск

- **Виртуалка:** VirtualBox/VMware или `qemu-system-i386 -m 512 -cdrom dimbuntu-tiny.iso` — хватает 512 МБ RAM
- **Флешка:** `sudo dd if=dimbuntu-tiny.iso of=/dev/sdX bs=4M status=progress oflag=sync`
- ⚠️ Образ (как и оригинальный CorePlus) грузится в режиме **BIOS/Legacy** — на чистых UEFI-машинах включите CSM или используйте виртуалку. 64-битный вариант с UEFI (CorePure64) — в планах.

## Локальная сборка

```bash
sudo apt install xorriso libarchive-tools syslinux-common curl
./scripts/build.sh
```

Скрипт скачивает CorePlus с официальных зеркал (пробует версии 16.x → 15.x, проверяет md5), правит меню и пересобирает ISO в `build/dimbuntu-tiny.iso`.

Переменные окружения: `TC_VERSIONS` (кандидаты версий Tiny Core), `ISO_NAME` (имя результата), `HOSTNAME_T` (hostname live-системы).

## Переименование репозитория

Workflow не содержит зашитого имени репозитория (использует встроенные переменные GitHub), поэтому переименование ничего не ломает. Бейдж в README после переименования продолжит работать через автоматический редирект GitHub — при желании обновите ссылку.

## История

Первая версия Dimbuntu собиралась на базе **Ubuntu 24.04 + Xfce** (ISO ~1.5 ГБ, успешный прогон CI есть в истории Actions) — она осталась в истории git (коммиты до `641af43`), если захочешь вернуться.

## Идеи на будущее

- Вшить свои расширения (.tcz) прямо в initrd
- Своя тема wbar, обои, брендинг
- CorePure64 (x86_64 + UEFI) вариант
- Persist-режим для флешки (tce/copy2fs)
