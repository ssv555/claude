---
name: Russian communication — always structure problem/fact/question explicitly
description: When writing in Russian, never mix statements and questions in vague prose — label each section explicitly
type: feedback
---

When communicating with the user in Russian, NEVER dump a paragraph that blends a statement, a problem description, and a question into one flow. The user cannot tell whether you are informing, asking, or complaining — and calls it "набор букв без пояснений".

**Rule:** any message that contains more than one intent (inform + ask, describe + propose, etc.) MUST be structured with explicit headers:

- **"## Проблема"** — what's wrong, factually
- **"## Почему это проблема"** — consequences / why the user should care
- **"## Что я сделал / НЕ сделал"** — current state of actions
- **"## Вопрос"** — the specific ask, phrased as a direct question with a yes/no or numbered options

**Do NOT use:**
- Vague openers like "Остаётся открытым вопросом..." followed by prose that doesn't clearly end in a question
- Mixed statement+question sentences like "Если хочешь — могу сделать X, скажи"
- Trailing "скажи" / "дай знать" — always put the question explicitly at the top of a "Вопрос" section

**Why:** this happened once already with the env variables actualization question — user responded with anger ("блядь, просто набор букв"). The information was technically correct but the structure made the intent opaque. Clear structure beats clever prose every single time.

**How to apply:** before sending any Russian message that has more than one logical part, stop and ask yourself: "Would a person reading this know — is this informing me, or asking me, or both?" If not instantly obvious, rewrite with headers.
