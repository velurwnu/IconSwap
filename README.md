# IconSwap

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue) ![swift](https://img.shields.io/badge/swift-SwiftUI%20%2B%20AppKit-orange)

**English** | [Русский ↓](#русский)

---

## English

A native macOS app for changing installed apps' icons to icons from the [macosicons.com](https://macosicons.com) catalog — no more manually dragging files onto Get Info (⌘I).

### What it does

- Scans `/Applications`, `/Applications/Utilities`, and `~/Applications`, and lists installed apps with their current icons.
- Lets you search macosicons.com right inside the app (a preview grid, each icon's author, infinite-scroll pagination).
- On **Apply**, downloads the selected icon and assigns it via `NSWorkspace.setIcon(_:forFile:options:)` — the official AppKit API that sets a Finder "custom icon" (an `Icon\r` file at the bundle root plus a flag in `com.apple.FinderInfo`). Nothing inside `Contents/` is touched and the app's code signature stays intact.
- Backs up the original icon automatically before the first change (`~/Library/Application Support/IconSwap/backups/`), so **Revert** / **Revert All** always restores the stock icon.
- Ships a **"Keep icons after updates"** toggle: it installs a LaunchAgent that watches each customized app's `Info.plist` and reapplies the cached icon the moment an app update resets it back to default (which macOS does on every bundle replacement).
- The same binary also works as a CLI: `iconswap set <path.app> <image>`, `iconswap reset <path.app>`, `iconswap restore`.

### Setting up your macosicons.com API key

Icon search goes through macosicons.com's official API (`POST /api/search`), not the website itself — that requires a **free API key**:

1. Sign up at [macosicons.com](https://macosicons.com) and grab an API key from your account.
2. On first launch, IconSwap will prompt for it (the sheet opens automatically and blocks further use until a key is entered).
3. The key is stored locally only, in the macOS Keychain (`service: IconSwap`, `account: macosicons-api`) — it's never sent anywhere but api.macosicons.com.
4. You can change it anytime via "Change API key…" at the bottom of the window.

**Note:** macosicons.com's free tier disallows commercial use and enforces a monthly call quota — once it's spent, the app shows an error and offers to wait for the reset or swap in another key; anything already downloaded keeps working from the local cache.

### macOS permissions

The first time you apply an icon, macOS will prompt for **App Management** access (System Settings → Privacy & Security → App Management) — required since macOS Ventura to write a custom icon into a third-party app bundle. Grant it once.

Apps under `/System/Applications` can't have their icon changed — they're SIP-protected, a macOS-level restriction this app can't work around.

### Building

1. Open the project in Xcode, select the **My Mac** target.
2. Product → Archive → Distribute App → **Custom** → **Copy App** → sign with **Sign to Run Locally** (no paid Apple Developer Program needed).
3. Drag the resulting `.app` into `/Applications`.

### Stack

Swift, SwiftUI + AppKit, `NSWorkspace`, Keychain Services, `launchd` (LaunchAgent), App Sandbox disabled.

### Credits

Icons are contributed by the [macosicons.com](https://macosicons.com) community — using the API requires crediting the site and each icon's author, which the app does automatically in its UI.

---

## Русский

Нативное macOS-приложение для смены иконок установленных приложений на иконки из каталога [macosicons.com](https://macosicons.com) — без ручного перетаскивания файлов через «Свойства» (⌘I).

### Что делает приложение

- Сканирует `/Applications`, `/Applications/Utilities` и `~/Applications`, показывает список установленных приложений с их текущими иконками.
- Позволяет искать иконки на macosicons.com прямо внутри приложения (сетка превью, автор каждой иконки, бесконечная подгрузка страниц).
- По кнопке **Apply** скачивает выбранную иконку и назначает её приложению через `NSWorkspace.setIcon(_:forFile:options:)` — это официальный API AppKit, который создаёт «кастомную» иконку Finder (файл `Icon\r` в корне бандла + флаг в `com.apple.FinderInfo`). Содержимое `Contents/` и подпись приложения не трогаются.
- Перед первым применением автоматически сохраняет оригинальную иконку в `~/Library/Application Support/IconSwap/backups/` — можно вернуть как было кнопкой **Revert** или **Revert All**.
- Есть тумблер **«Сохранять иконки после обновлений»**: ставит LaunchAgent, который следит за `Info.plist` каждого изменённого приложения и переприменяет иконку из локального кэша сразу после того, как обновление приложения сбросило её (так делает macOS при любой переустановке бандла).
- Есть CLI-режим того же бинарника: `iconswap set <path.app> <image>`, `iconswap reset <path.app>`, `iconswap restore`.

### Установка API-ключа macosicons.com

Поиск иконок идёт через официальный API macosicons.com (`POST /api/search`), а не через сам сайт — для него нужен **бесплатный API-ключ**:

1. Зарегистрируйтесь на [macosicons.com](https://macosicons.com) и получите API-ключ в личном кабинете.
2. При первом запуске IconSwap попросит его ввести (окно открывается автоматически и не даёт продолжить без ключа).
3. Ключ хранится только локально, в Keychain macOS (`service: IconSwap`, `account: macosicons-api`) — никуда, кроме api.macosicons.com, не отправляется.
4. Ключ можно сменить в любой момент кнопкой «Изменить API-ключ…» внизу окна.

**Важно:** на бесплатном тарифе macosicons.com коммерческое использование запрещено, и у ключа есть месячный лимит запросов (после исчерпания приложение покажет ошибку и предложит подождать сброса лимита или использовать другой ключ; уже загруженные результаты продолжают работать из локального кэша).

### Разрешения macOS

При первом применении иконки система спросит разрешение **App Management** (System Settings → Privacy & Security → App Management) — без него запись кастомной иконки в сторонние бандлы запрещена начиная с macOS Ventura. Разрешение нужно выдать один раз.

Системные приложения из `/System/Applications` иконку сменить не позволят — они защищены SIP, это ограничение самой macOS.

### Сборка

1. Открыть проект в Xcode, выбрать таргет **My Mac**.
2. Product → Archive → Distribute App → **Custom** → **Copy App** → подпись **Sign to Run Locally** (Apple Developer Program не требуется).
3. Готовый `.app` перетащить в `/Applications`.

### Технологии

Swift, SwiftUI + AppKit, `NSWorkspace`, Keychain Services, `launchd` (LaunchAgent), без App Sandbox.

### Авторство

Иконки предоставлены сообществом [macosicons.com](https://macosicons.com) — при использовании API обязательно указание авторства сайта и автора конкретной иконки (делается автоматически в интерфейсе приложения).
