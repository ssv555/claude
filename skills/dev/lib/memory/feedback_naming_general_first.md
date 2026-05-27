---
name: File/topic naming — general category first, specific last
description: In file names, topic names, identifiers — always put the general category first, then the specific variant (e.g. Auth_VK, not VK_Auth; Icon_Google, not Google_Icon)
type: feedback
---

В именах файлов, тем, идентификаторов, заголовков — **сначала обобщающая категория, потом конкретный вариант**.

Правильно:
- `Auth_VK`, `Auth_Google`, `Auth_Telegram` (категория Auth, типы — VK/Google/Telegram)
- `Icon_VK`, `Icon_Yandex`, `Icon_Mail`
- `Button_Primary`, `Button_Secondary`
- `2026.04.05_16.48_ssv_Auth_VK.md` (сессия по теме Auth, подтип VK)

Неправильно:
- `VK_Auth`, `Google_Auth`
- `VK_Icon`, `Yandex_Icon`
- `Primary_Button`

**Why:** Обобщений меньше, конкретики больше. Когда файлов/сущностей по одной теме много, префикс-категория группирует их в алфавитном списке рядом. Открывая сортированный список, видишь все `Auth_*` файлы вместе — быстро понятно что по теме авторизации есть в архиве. Если префикс — специфика (`VK_*`), они разбросаны, и нельзя окинуть взглядом всю категорию.

**How to apply:** Всегда при создании имён файлов, идентификаторов компонентов, заголовков разделов, ключей в конфиге — сначала общая категория, затем уточнение. Применимо к session-archives (`YYYY.MM.DD_HH.mm_dev_Category_Specific.md`), компонентам, иконкам, темам, типам, любым составным именам.
