---
name: Playwright screenshot before any UI claim
description: Never state what UI looks like or how a CSS feature behaves from memory — verify via Playwright screenshot first
type: feedback
originSessionId: eda143f0-f4c3-430e-b778-a7512652a8b1
---
Перед любым утверждением о том, как выглядит/работает UI на экране (классы применились, свечение есть, border на месте, элемент виден, hover срабатывает) — **сначала Playwright-скрин на vdole-ssv.it-joy.ru**, потом утверждение. Не «по коду это должно работать», не «CSS-спецификация говорит X», не «classes включают Y». Только то, что реально отрендерилось — с подтверждением скриншотом.

**Why:** В сессии 2026-04-23 я несколько turn'ов утверждал «свечение на месте, focus-visible срабатывает» по памяти и по computed styles. Пользователь видел на экране иначе. Плюс проблема с max-w-[1600px] — я мог увидеть её сразу по скрину, но вместо этого теоретизировал про layout. Это правило уже было в глобальной памяти («VERIFY BEFORE OUTPUT», «PING BEFORE BROWSER»), но не применялось автоматически.

**How to apply:** Пользователь задал вопрос про UI / прислал скриншот / пожаловался на визуал → **первая реакция**: navigate на dev-стенд + screenshot + evaluate для замеров. Только после этого формулирую ответ. При HMR после каждого `Edit` на фронте — тоже повторить скриншот. Правило «ground truth = Playwright, не мои предположения» действует ВСЕГДА, не только по прямой просьбе.
