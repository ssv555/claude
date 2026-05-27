/*
 * setuid-claude-wrapper.c — setuid wrapper that switches to claude-runner
 * and forwards to /opt/claude/bin/claude with sanitized argv.
 *
 * Blocks flags that would redirect claude's config/skills/hooks to a
 * dev-controlled path. Sets HOME from passwd by REAL uid so claude
 * still writes session data to the dev's home.
 *
 * Compile: gcc -O2 -Wall -Wextra -o claude setuid-claude-wrapper.c
 * Install: install -o claude-runner -g claude-runner -m 4755 claude /usr/local/bin/claude
 */

#define _GNU_SOURCE
#include <errno.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

static const char *TARGET = "/opt/claude/bin/claude";

static const char *BLOCKED_PREFIXES[] = {
    "--config-dir",
    "--projects-dir",
    "--skills-dir",
    "--hooks-dir",
    "--settings",
    NULL
};

static int is_blocked(const char *arg) {
    for (int i = 0; BLOCKED_PREFIXES[i]; i++) {
        size_t n = strlen(BLOCKED_PREFIXES[i]);
        if (strncmp(arg, BLOCKED_PREFIXES[i], n) == 0 &&
            (arg[n] == '\0' || arg[n] == '=')) {
            return 1;
        }
    }
    return 0;
}

int main(int argc, char **argv) {
    /* Resolve HOME from real uid BEFORE switching identity. */
    uid_t real_uid = getuid();
    struct passwd *pw = getpwuid(real_uid);
    if (!pw) {
        fprintf(stderr, "claude-wrapper: cannot resolve passwd entry for uid %d\n", real_uid);
        return 1;
    }
    const char *home = pw->pw_dir;

    /* Filter argv — drop blocked flags. */
    char **filtered = calloc((size_t)argc + 1, sizeof(char *));
    if (!filtered) { perror("calloc"); return 1; }
    int j = 0;
    filtered[j++] = argv[0];
    for (int i = 1; i < argc; i++) {
        if (is_blocked(argv[i])) {
            fprintf(stderr, "claude-wrapper: blocked flag '%s'\n", argv[i]);
            /* If flag took a separate value (no '='), skip next arg too */
            if (!strchr(argv[i], '=') && i + 1 < argc && argv[i + 1][0] != '-') {
                i++;
            }
            continue;
        }
        filtered[j++] = argv[i];
    }
    filtered[j] = NULL;

    /* Drop privileges to claude-runner (which we ARE via setuid bit). */
    uid_t target_uid = geteuid();
    if (target_uid == real_uid && real_uid != 0) {
        fprintf(stderr, "claude-wrapper: not running setuid — refusing\n");
        return 1;
    }
    if (setresgid(getegid(), getegid(), getegid()) != 0) {
        perror("setresgid"); return 1;
    }
    if (setresuid(target_uid, target_uid, target_uid) != 0) {
        perror("setresuid"); return 1;
    }

    /* Sanitize env: keep PATH/TERM/LANG, force HOME, drop XDG_* and CLAUDE_* */
    char *path = getenv("PATH");
    char *term = getenv("TERM");
    char *lang = getenv("LANG");
    clearenv();
    setenv("HOME", home, 1);
    setenv("USER", pw->pw_name, 1);
    setenv("LOGNAME", pw->pw_name, 1);
    setenv("SHELL", pw->pw_shell ? pw->pw_shell : "/bin/bash", 1);
    setenv("PATH", path ? path : "/usr/local/bin:/usr/bin:/bin", 1);
    if (term) setenv("TERM", term, 1);
    if (lang) setenv("LANG", lang, 1);

    execv(TARGET, filtered);
    perror("execv");
    return 127;
}
