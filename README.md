# StandoffWH — Wallhack для Standoff 2

iOS tweak (jailbreak) — wallhack + chams с полным обходом античита Axlebolt.

## Сборка

### Через GitHub Actions (автоматически)

1. Пуш в `main` → Actions билдит автоматически
2. Готовый `.deb` лежит в **Artifacts** после билда
3. Скачиваешь → кидаешь на телефон → устанавливаешь

### Вручную (если есть мак)

```bash
# один раз — установить theos
brew install dpkg ldid make
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git $THEOS

# билд
cd tweak/
make package
```

## Установка

### Rootless (Dopamine, palera1n 2.x)
```bash
# на телефоне через SSH:
dpkg -i com.onyx.standoffwh_1.0.0_iphoneos-arm.deb
# или через Filza / Sileo
```

### Rootful (unc0ver, checkra1n, palera1n 1.x)
```bash
dpkg -i com.onyx.standoffwh_1.0.0_iphoneos-arm.deb
killall -9 standoff2
```

## Как работает

Запускаешь Standoff 2 → tweak автоматически загружается → через 5 секунд появляется зелёная панелька в левом верхнем углу:

- **Wallhack: ON/OFF** — видишь игроков сквозь стены
- **Chams: ON/OFF** — игроки подсвечиваются зелёным

Панельку можно перетаскивать по экрану.

## Что под капотом

| Компонент | Механизм |
|-----------|----------|
| WH основной | `Camera.set_cullingMask` — форсит рендер всех слоёв |
| Chams | `Material.SetPass` → `_ZTest = Always`, зелёный тинт |
| Occlusion bypass | Хук окклюзии, игроки не скрываются |
| AC bypass | 6 обфусцированных методов AntiCheatManager → no-op |
| Server report | `ReportViaServer` + `PlayerBannedHandler` → swallowed |
| JB hide | sysctl, dyld, NSFileManager, canOpenURL, fork, access |
