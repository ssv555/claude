# Onboarding for grey

Welcome to VDole dev environment.

## Your access

- Server: `moscow_my`, host alias in your `~/.ssh/config`
- SSH port: `53847` (public, IPv4)
- Username: `grey`
- Private key: keep secure on your machine only.

## ~/.ssh/config entry

```
Host vdole-moscow
    HostName <ip>
    Port 53847
    User grey
    IdentityFile ~/.ssh/vdole_moscow
```

## Clone VDole

```bash
git clone vdole-moscow:/srv/git/VDole.git
cd VDole
git config user.name "Sergey Иванов"
git config user.email "grey@moscow.my"
```

## Push workflow

- Your branches: `git push origin grey/feature-name`
- `main`, `master`, `release/*`, `prod`, `production` — push blocked by hook. Open PR on GitHub instead.
- All pushes mirrored to GitHub automatically via internal bot.

## Claude Code

Pre-configured. Just run:

```bash
claude
```

Skills/hooks/CLAUDE.md are shared (read-only). Your sessions and projects are private to your home.

## Questions

Ping ssv (chief) directly.
