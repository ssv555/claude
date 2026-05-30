# Chunk analysis prompt — для подагентов в Шаг 7a

Когда сессия > 5 MB или есть subagents/ — main session не читает JSONL целиком. Вместо этого:

1. Сплитим JSONL на куски ~2 MB (или по 300 user/assistant пар).
2. Для каждого куска вызываем `Agent({ subagent_type: 'general-purpose', ... })` с промптом ниже.
3. Подагент читает свой кусок, возвращает JSON со счётчиками + примерами.
4. Main session собирает все JSON, синтезирует сводный отчёт по report-template.md.

## Промпт-шаблон для каждого подагента

```
Ты анализируешь кусок Claude Code сессии разработчика для chief-side ревью качества AI-использования.

Файл с куском JSONL: {{CHUNK_PATH}}
Это кусок {{N}} из {{TOTAL}} сессии разработчика {{ALIAS}}.

Прочитай весь файл (он формат JSONL — каждая строка отдельный JSON-объект с полями type / message / timestamp).

Подсчитай и верни СТРОГО JSON со следующими полями:

{
  "chunk_index": {{N}},
  "first_ts": "ISO8601 timestamp первого сообщения в куске",
  "last_ts": "ISO8601 timestamp последнего",
  "msg_count": <int>,
  "user_msgs": <int>,
  "assistant_msgs": <int>,
  "tool_calls_by_name": {
    "Read": <int>, "Edit": <int>, "Bash": <int>, ...
  },
  "tokens": {
    "input": <int>, "cache": <int>, "output": <int>
  },
  "user_message_timestamps": [<list ISO8601 для расчёта active time>],
  "metrics": {
    "test_verification": {
      "edit_write_followed_by_test_count": <int>,
      "edit_write_total_count": <int>,
      "good_examples": ["цитата 1", "цитата 2"]
    },
    "iteration_cycles": {
      "detected_tasks": <int>,
      "avg_msgs_per_task": <float>,
      "examples": ["задача X — N итераций"]
    },
    "tool_diversity": {
      "unique_tools": ["Read", "Edit", "Bash", ...]
    },
    "ai_correction": {
      "pushback_count": <int>,
      "total_user_msgs": <int>,
      "examples_loyal": ["цитата с обоснованием"],
      "examples_blunt": ["голое 'не так'"]
    },
    "continuity": {
      "finished_explicitly": <bool>,
      "last_user_msg_preview": "первые 80 chars"
    },
    "ownership_signs": {
      "memory_writes": <int>,
      "claude_md_refs": <int>,
      "commit_msg_quality_examples": ["..."]
    },
    "pushback_maturity": {
      "with_justification": <int>,
      "bare_pushback": <int>,
      "examples": ["..."]
    },
    "self_validation": {
      "validated_facts": <int>,
      "examples": ["открыл X.tsx:42, там Y"]
    }
  }
}

ВАЖНО:
- Цитаты обрезай до 80 символов.
- Если в сообщениях встретятся секреты (BEGIN PRIVATE KEY / BOT_TG_TOKEN= / .credentials.json содержимое) — НЕ цитируй, помечай "[REDACTED]".
- НЕ комментируй, верни ТОЛЬКО JSON. Никакого markdown-обёртки.
```

## Синтез в main session

Когда все подагенты вернули JSON:

1. Просуммируй счётчики (msg_count, tool_calls, tokens, active_time из объединённых timestamps).
2. Слей `unique_tools` через Set.
3. Метрики 1-10 — взвешенное среднее с примерами из всех чанков (выбери 1-3 best/worst).
4. Заполни report-template.md, запиши итоговый отчёт.

## Параллелизация

Все подагенты — независимые. Запускать одним сообщением с несколькими `Agent` блоками для параллельного выполнения. Лимит — 5-8 одновременных, чтобы не упереться в rate-limit.
