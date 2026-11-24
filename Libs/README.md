# Vendored libraries

Third-party packages live in workspace `Libs/` (not under `Common/`).

**Hard rule:** packaging never renames these files. Install/build mirror
`Libs/**` → `<addon>/Libs/**` with original relative paths and basenames
(`Scripts/wowf-vendor-common.sh` → `vendor_libs`).

| Workspace | Packaged |
|-----------|----------|
| `Libs/LibStub/LibStub.lua` | `Libs/LibStub/LibStub.lua` |
| `Libs/LibEditMode/embed.xml` | `Libs/LibEditMode/embed.xml` |

TOC entries must list `Libs\...` paths.
