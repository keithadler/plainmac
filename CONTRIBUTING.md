# Contributing

Thank you. The bar is the same as for the rest of the family: one thing, plainly explained, read-only, nothing leaves the Mac.

- Build with `./build-app.sh`; the Command Line Tools are enough.
- Run `watchmac selftest` before a pull request. Tests use recorded `nettop` output and fixed reverse-DNS answers; they never sample or resolve anything real.
- New company names go in `Names.swift` with their kind. Only add a domain you can show belongs to that company; unknown is an honest answer.
- Anything that blocks, intercepts, or sends data off the Mac will not be merged.

MIT licensed; contributions are accepted under the same license.
