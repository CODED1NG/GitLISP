# 3Ding GitHub

Download GitHub repositories, folders, or individual files into a local AutoCAD
cache. Load AutoLISP immediately or register commands to load it later.

**Windows AutoCAD 2021 or later**, including Civil 3D and other AutoCAD verticals.
Licensed under the [MIT License](LICENSE).

## Install

1. Download/extract this project. Keep these four files together:
   `GitHub.lsp`, `Install.lsp`, `README.md`, and `LICENSE`.
2. In AutoCAD, run **APPLOAD** and select **Install.lsp**.
   Handle AutoCAD's initial trusted-file prompt if one appears.
3. Run **GITHUBINSTALL**, select **GitHub.lsp** from the extracted folder, and
   confirm the displayed installation paths.
4. Restart AutoCAD. Run **GITHUBHELP** for the command list.

Installation uses a per-user Autodesk application bundle. It does not edit
`acad.lsp`, `acaddoc.lsp`, the Startup Suite, or `SECURELOAD`.

| Location | Purpose |
| --- | --- |
| `%APPDATA%\Autodesk\ApplicationPlugins\3DingGitHub.bundle` | Installed application, help, license, and setup records |
| `%LOCALAPPDATA%\3Ding\GitHub` | Cached sources, manifests, staging/recovery files, and anonymous rate-limit backoff |

The installer adds its application folder and the cache's recursive
`sources\...` path to **TRUSTEDPATHS**, preserving existing entries. These paths
allow cached code to run without a separate prompt for each file. Install only
sources you intend to trust.

When the bundle loads in another AutoCAD profile, setup adds missing trust
entries there and records what it added. An administrator-locked profile is
reported; setup does not bypass that policy. Bundle startup also depends on
AutoCAD's existing `APPAUTOLOAD` configuration.

To update this initial release, uninstall it, then install the new extracted
copy. Uninstall removes cached data, so sources must sync again afterward.

## Commands

| Command | What it does |
| --- | --- |
| **GITHUBLOAD** | Ask for a URL, sync it, and load its AutoLISP files |
| **GITHUBSYNC** | Ask for a URL and download/update its cache without executing code |
| **GITHUBPREVIEW** | Ask for a URL and show planned downloads and conflicts |
| **GITHUBSTATUS** | Show installation, AutoCAD profile, and cache locations |
| **GITHUBHELP** | Show the command list |
| **GITHUBINSTALL** | Install the bundle and configure the current profile |
| **GITHUBCLEARCACHE** | Remove cached sources and rate-limit data; keep the installation |
| **GITHUBUNINSTALL** | Remove installed files, default tool data, and installer-added trust entries |

The interactive URL commands use public/anonymous access.

## AutoLISP calls

Use one URL per call. Normal calls print readable status text and finish
silently, without returning a data dump to command history.

```lisp
(GitHubLoad "https://github.com/your-org/cad-tools" nil)

(GitHubLoad
  "https://github.com/your-org/cad-tools/tree/main/Tools"
  nil
)

(GitHubLoad
  "https://github.com/your-org/cad-tools/blob/main/Tools/example.lsp"
  nil
)

(GitHubSync "https://github.com/your-org/cad-tools" nil)
(GitHubPreview "https://github.com/your-org/cad-tools" nil)
```

Raw GitHub file URLs, slash-containing branch names, and UTF-8/percent-encoded
paths are supported. The repository owner and name use GitHub's ASCII spelling.

For authentication, pass a token string rather than `nil`. For example, if
you configured a `GITHUB_TOKEN` environment variable:

```lisp
(GitHubLoad "https://github.com/your-org/private-tools" (getenv "GITHUB_TOKEN"))
```

The tool does not save tokens in its files, setup records, or command stubs.

### Programmatic results

Scripts that need association lists can call `GitHub_Load`, `GitHub_Sync`,
`GitHub_Preview`, or `GitHub_Autoload` with the same arguments as their normal
counterparts. These internal data-returning functions are separate from the
quiet user-facing calls.

### Deferred commands

```lisp
(GitHubAutoload
  "https://github.com/your-org/cad-tools/blob/main/tools.lsp"
  '("TOOL1" "TOOL2")
  nil
)
```

Autoload requires an explicit file URL and command names without `C:` prefixes.
Registration syncs without executing the file and leaves existing command
definitions alone. First command use checks and loads the installed file, then
runs the command. Command use makes no sync requests. The source must define
the requested command.

## Loading and cache behavior

- File URLs load the exact `.lsp`, `.fas`, or `.vlx` file.
- Folder/repository URLs load eligible files recursively, in alphabetical path
  order. Dependency order is not inferred.
- For matching paths/basenames, automatic selection prefers VLX, FAS, then LSP.
  An explicit file URL keeps its specified format.
- A source error stops the batch and names the failed file. Earlier definitions
  remain loaded. A valid download cannot repair unfinished third-party code.
- Tool-generated output is plain text. Loaded third-party files may still print
  their own messages or request user input.

Sources normally check for remote updates every four hours. Repeated loading
calls still execute the cached code in the current drawing.

Downloads are pinned to one commit, staged before replacement, and tracked by
a per-source manifest. Local size/modification times are checked; a complete
local content-hash audit is not performed.

When refresh fails, an intact installed copy can still load. Each source must
have synced first. Repository, folder, and individual-file sources have separate
caches. Modified entry files and unfinished recovery state block loading.

The bundle makes this tool available in drawings. It does **not** automatically
execute downloaded repository code. To load your own tested sources when a
drawing opens, add explicit `GitHubLoad` calls to your existing `acaddoc.lsp`.

## Clear data or uninstall

Both removal commands show the target paths and require **Yes** before deleting
anything. Cached files include any edits made inside the cache.

**GITHUBCLEARCACHE** removes downloaded sources, manifests, recovery/staging
folders, and anonymous rate-limit data. Offline loading requires a successful
sync after clearing the cache.

**GITHUBUNINSTALL** also removes the bundle and the trust entries setup added
to its recorded AutoCAD profiles. Existing/manual trust entries are preserved.
The original extracted project folder is not removed.

Removal refuses filesystem reparse points and paths outside the tool's fixed
locations. Locked files or profile settings are reported. Close other AutoCAD
sessions before uninstalling, and restart afterward: definitions already loaded
into open drawings cannot be unloaded by deleting their source files.

## References

- [Autodesk application-bundle components](https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-Customization/files/GUID-3C25E517-8660-4BB7-9447-2310462EF06F.htm)
- [Autodesk installer security requirements](https://help.autodesk.com/cloudhelp/2021/ENU/OARX-IOP/files/GUID-332144C1-3562-493F-B361-9D1A21AF540E.htm)
- [TRUSTEDPATHS](https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-LT/files/GUID-2FB4611D-F141-48D5-9B6E-460EB59351AF.htm)
