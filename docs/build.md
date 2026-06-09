# Build system (M0)

See [decisions/0014](../decisions/0014-compilation-toolchain-architecture.md).

## Layout

```
.kinglet/
├── cache/           # stamp indexes (reserved)
├── objects/         # content-addressed blobs + <id>.meta
├── out/             # default outputs (e.g. compiler.kbc)
└── stamps/          # last-success stamp per target
```
