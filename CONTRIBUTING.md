# Contributing

Issues and pull requests are welcome. This page is the whole process; it is short on purpose.

## Reporting a problem

Open an issue with the output of `bash livemap.sh doctor --report` (the bug template asks for it). It holds
versions, GPU, screens, the helper's status and the last log lines, nothing personal beyond package versions.
For anything that looks like a security issue, see [SECURITY.md](SECURITY.md).

## Working on the code

    git clone https://github.com/TidyBitz/livemap.git
    cd livemap
    git switch -c my-change           # every change on its own branch

Edit, then build and install exactly what a user would get:

    scripts/package.sh                          # runs scripts/check.py, builds livemap.zip
    bash livemap.sh install livemap.zip         # installs over the current version; restarts plasmashell

Watch the wallpaper's own log while you test:

    journalctl --user -f | grep -i -E "livemap|qml"

`scripts/check.py` must pass. It checks that every setting in `main.xml` has an alias on the settings page
and is read somewhere, that QML brackets and ids are sane, that versions agree, and that `geo.js` loads. CI
runs the same script on every push and pull request.

Where things live and how a layer is put together is in the README under "Repository layout";
`livemap/README.md` has the developer notes (the `layer` id trap, how the night shade avoids a shader, and
so on).

## Sending a change

- Open a pull request against `main`. One change per PR; small is good.
- Add a line to `CHANGELOG.md` under the version at the top (the unreleased one) - wallpaper changes under
  the wallpaper version, widget changes under the widget version. Do not bump version numbers; that happens
  in the release PR.
- `main` only takes pull requests with a green check; they are squash-merged, so the PR title becomes the
  commit message - write it as one.
- Everything is GPL-3.0-or-later; by contributing you agree your change is too. Pictures and icons are
  CC BY 4.0.

## Releasing (maintainer)

Bump the versions (`metadata.json` ×2, the helper's `VERSION`, the two log lines in `main.qml`), date the
changelog entry, merge, then tag: `git tag -a v0.47 -m "Live World Map 0.47" && git push origin v0.47`. CI
builds `livemap.zip` and publishes the release with the changelog entry as its notes.
