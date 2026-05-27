---
name: Seal auth frontend after implementation
description: After implementing and testing any auth feature — seal ALL auth mechanics (backend + frontend). Failing to seal frontend is a mistake.
type: feedback
originSessionId: b0082493-3a6f-4a31-a990-feede3c026cb
---
After implementing and testing auth-related features, ALWAYS add frontend auth files to the `auth` sealed group before considering the task done.

**Why:** Only backend was sealed after initial setup — frontend auth mechanics (LoginFlow, OAuthButtonsRow, TelegramLogin, AppGate, etc.) were left unsealed. This is a mistake: the full auth mechanism includes both layers.

**How to apply:** After any auth feature implementation + testing, run:
1. `/seal add auth <new-frontend-files>` for any new auth components created
2. `/seal auth` to re-seal the group

Frontend files that belong in the `auth` sealed group:
- `front/src/components/auth/LoginFlow.tsx`
- `front/src/components/auth/RegistrationFlow.tsx`
- `front/src/components/auth/OAuthButtonsRow.tsx`
- `front/src/components/TelegramLogin.tsx`
- `front/src/AppGate.tsx`
- Any new auth components (e.g. `BotPromo.tsx`) created during implementation

After sealing — delete `.tmp/auth_4.8_new_device_progress.md` (progress tracker, no longer needed once session is archived).
