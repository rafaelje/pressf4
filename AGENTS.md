# AGENTS.md

Build, install and run instructions live in [README.md](./README.md#build). Use `make` / `make install` (not SwiftPM or Xcode). When iterating on UI, run `make install && killall pressf4 2>/dev/null && open /Applications/pressf4.app` so the user sees the fresh binary — several "doesn't work" reports turned out to be stale binaries.
