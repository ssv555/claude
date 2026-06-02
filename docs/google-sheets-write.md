# Google Sheets — запись из bun-скрипта

> **TL;DR.** Чтение и запись любого Google Sheet из локального bun-скрипта через Service Account + `googleapis`. Один раз настраивается GCP-проект и SA-ключ, дальше: расшарить лист на email сервис-аккаунта как Editor → задать `SHEET_ID`/`RANGE`/`values` в `~/.claude/tmp/sheets-write/write-sheet.ts` → запустить. Операции: update / append / clear / get / batchUpdate.

Как настроено редактирование Google Sheets из локальных скриптов через Service Account + `googleapis`. Один раз настроил GCP — дальше любая правка любого листа = одна функция.

## Архитектура

- **Google Cloud Project** — отдельный проект под эту задачу (никакой бизнес-логики).
- **Service Account** — техническая учётка внутри проекта. Имеет email вида `<sa-name>@<project-id>.iam.gserviceaccount.com`. Этой учётке мы шарим конкретные листы.
- **JSON-ключ** — приватный ключ сервис-аккаунта. Хранится локально в `~/.claude/.secrets/`. Никогда не пушится в git, не выкладывается публично.
- **Google Sheets API** — включён на уровне проекта. Один раз.
- **Шаринг** — на каждый целевой лист отдельно: расшариваем по email сервис-аккаунта как Editor.

## Одноразовый setup в GCP (~5 минут)

1. https://console.cloud.google.com → New Project → имя `sheets-writer` (или другое осмысленное).
2. APIs & Services → Library → `Google Sheets API` → Enable.
3. APIs & Services → Credentials → `+ CREATE CREDENTIALS` → `Service account`.
   - Name: `sheets-writer`. Role — пропустить. Принципалы — пропустить. Done.
4. Открыть созданный SA → вкладка **Keys** → ADD KEY → Create new key → JSON → Create.
5. Скачанный JSON положить в `~/.claude/.secrets/` (создать папку при необходимости).
6. Из JSON или из списка SA в Credentials взять **email сервис-аккаунта** — он понадобится для шаринга листов.

## Шаринг конкретного листа

Перед каждой записью в новый лист — расшарить его на email сервис-аккаунта:

1. Открыть Sheets → Share.
2. В поле «Add people» вставить email сервис-аккаунта.
3. Роль — **Editor**.
4. Снять галочку «Notify people» (на SA письмо никто не читает).
5. Share.

Без этого шага запись вернёт `403 The caller does not have permission`.

## Скрипт записи

Минимальный bun-скрипт, лежит в `~/.claude/tmp/sheets-write/write-sheet.ts`:

```ts
import { google } from 'googleapis'

const KEY_PATH = '<путь к JSON-ключу>'
const SHEET_ID = '<ID листа из URL: spreadsheets/d/{ID}/edit>'
const RANGE = 'A1:D12' // A1-нотация диапазона

const values = [
  ['header1', 'header2', ...],
  ['row1col1', 'row1col2', ...],
  // ...
]

const auth = new google.auth.GoogleAuth({
  keyFile: KEY_PATH,
  scopes: ['https://www.googleapis.com/auth/spreadsheets'],
})

const sheets = google.sheets({ version: 'v4', auth })

const res = await sheets.spreadsheets.values.update({
  spreadsheetId: SHEET_ID,
  range: RANGE,
  valueInputOption: 'RAW', // или 'USER_ENTERED' для парсинга формул/дат
  requestBody: { values },
})

console.log('Updated cells:', res.data.updatedCells)
```

Запуск:

```bash
cd ~/.claude/tmp/sheets-write && bun run write-sheet.ts
```

`node_modules` с `googleapis` уже установлены в этой папке.

## Параметры записи

- **`valueInputOption`**:
  - `RAW` — значения вставляются как есть, без интерпретации.
  - `USER_ENTERED` — Google парсит как при ручном вводе (формулы `=SUM(...)` работают, числа/даты приводятся к типам).
- **`range`** — A1-нотация. Примеры: `A1:D12`, `Sheet2!B2:F100`, `Лист1!A:A`.
- **`values`** — массив массивов. Внешний — строки, внутренний — ячейки слева направо. Длина внутренних массивов должна соответствовать ширине range.

## Другие операции

Кроме `update` (полная замена диапазона) есть:

- `append` — `sheets.spreadsheets.values.append({...})` — дописать строки в конец таблицы.
- `clear` — `sheets.spreadsheets.values.clear({ spreadsheetId, range })` — очистить диапазон.
- `get` — `sheets.spreadsheets.values.get({ spreadsheetId, range })` — прочитать диапазон.
- `batchUpdate` — `sheets.spreadsheets.batchUpdate({...})` — низкоуровневые операции (форматирование, добавление листов, merge, freeze, conditional formatting).

Документация: https://developers.google.com/sheets/api/reference/rest

## Безопасность

- **JSON-ключ — это полноценные учётные данные**. Кто угодно с этим файлом может писать во все расшаренные на этот SA листы. Хранить только локально.
- **Не пушить в git**. `~/.claude/.secrets/` уже вне любых репозиториев — безопасное место.
- **Не давать SA лишние права**. Шаринг — только на конкретные нужные листы. Никаких ролей на уровне GCP-проекта.
- **Ротация**: в любой момент можно создать новый ключ в Credentials → старый удалить. Доступ старого ключа отзовётся мгновенно.
- **Удаление SA**: если учётка скомпрометирована — удалить её в Credentials, расшаренные листы автоматически потеряют доступ.

## Quotas

Бесплатные лимиты (на момент 2026-04):
- 300 read requests / минута / проект
- 60 write requests / минута / пользователь (на сервис-аккаунт)
- Без дневных лимитов

Для разовых правок — с большим запасом. Для массовых записей лучше batchUpdate (одна операция на много ячеек).
