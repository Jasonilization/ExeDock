# Security Policy

## Reporting a vulnerability

If you find a security issue in Playdock, please **don't open a public issue for it**. Email
**thesuperjasonprocoolisplay@hotmail.com** with:

- A description of the issue and its potential impact
- Steps to reproduce it (a minimal case is ideal)
- Your macOS version and Playdock version

You should get a response within a few days. This is a small, mostly solo-maintained project, so
there's no formal disclosure timeline or bug bounty - but real reports get taken seriously and
fixed promptly, and you'll get credit in the release notes unless you'd rather stay anonymous.

## Scope

Playdock is a native macOS app that launches Windows executables through an existing Sikarugir Wine
engine, browses a Wine bottle's C: drive, and talks to Steam's public store API and GitHub's public
release API over HTTPS. Things worth reporting:

- Anything that lets a downloaded/opened file escape its Wine bottle in an unexpected way
- Anything that writes outside `~/Library/Application Support/ExeDock/` or a bottle's own prefix
- Unsafe handling of data fetched from the network (Steam metadata, GitHub releases, downloaded
  engine/wrapper tarballs)
- Credential or token handling issues (Playdock doesn't handle Steam login directly, but flag
  anything that looks like it touches auth)

Not in scope: vulnerabilities in Wine itself, in the Sikarugir engine it reuses, or in a game you
choose to run through it - those belong to their own upstream projects.
