# 240-MP Security Policy

240-MP is a hobby project, but the Emby/Jellyfin module handles local server credentials, so security reports are taken seriously.

## Supported versions

This is a single-maintainer project without long-term support branches. Only the **latest
[release](https://github.com/TaterTotterson/240-MP-Emby-Jelly/releases/latest)** (and the current `main`) is
supported. Fixes ship in a new release rather than as patches to older tags.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately via GitHub's **[Report a vulnerability](https://github.com/TaterTotterson/240-MP-Emby-Jelly/security/advisories/new)**
button (Security -> Advisories). This opens a private advisory only I can see.

When reporting, please include:

- What the issue is and the potential impact
- Steps to reproduce (and a proof of concept if you have one)
- The affected version / commit, and whether you tested on the Raspberry Pi 4 composite image or a local development build

You'll get an acknowledgement as soon as I can verify. Once a fix is ready it will go out in a new release, and I'll gladly credit you if you are ok with it.

## Scope & what to keep in mind

The most sensitive area is Emby/Jellyfin authentication:

- **Auth tokens** are stored in the local data directory with `0600` permissions and should never be logged or committed.
- Modules should only ever talk **directly** to the third-party API they integrate with, and only ever write to the local 240-MP data directory — never to an external service the contributor controls. See the principles in [CONTRIBUTING.md](CONTRIBUTING.md).

Things that are **not** security issues: bugs with no security impact (use a regular
[bug report](https://github.com/TaterTotterson/240-MP-Emby-Jelly/issues/new/choose) instead), and problems in
mpv, Qt, or other upstream dependencies (please report those to the respective projects).
