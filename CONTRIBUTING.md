# Contributing

Thank you. The bar for a change here is the same as for the other apps in the family: it must be something a person can understand in one sentence, and it must not write to anything it reads.

- Build with `./build-app.sh`; the Command Line Tools are enough.
- Run `permsmac selftest` before a pull request. Tests live in `Sources/PermsMac/Tests` and run against synthetic databases in a temporary folder; they never touch the real ones.
- New permission keys go in `Catalog.swift` with a sentence that says what an app holding it can do, not what Apple calls it.
- Keep the app reading. A pull request that changes a permission, a launch agent or a login item will not be merged.

MIT licensed; contributions are accepted under the same license.
