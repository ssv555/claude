# Onboarding for alx

Welcome to VDole dev environment.

## Your access

- Server: `moscow_my`, host alias in your `~/.ssh/config`
- SSH port: `53847` (public, IPv4)
- Username: `alx`
- Private key: keep secure on your machine only.

## ~/.ssh/config entry

```
Host vdole-moscow
    HostName <ip>
    Port 53847
    User alx
    IdentityFile ~/.ssh/vdole_moscow
```

## Clone VDole

```bash
git clone vdole-moscow:/srv/git/VDole.git
cd VDole
git config user.name "Aleksandr Novikov"
git config user.email "alx@moscow.my"
```

## Push workflow

- Your branches: `git push origin alx/feature-name`
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
