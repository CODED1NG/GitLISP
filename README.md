# GitLISP

Download GitHub repositories, folders, or individual files into a local AutoCAD
cache. Load AutoLISP immediately or register commands to load it later.

**Windows AutoCAD 2021 or later**, including Civil 3D and other AutoCAD verticals.
Licensed under the [MIT License](LICENSE).

## Install

1. Download only [Install.lsp](https://raw.githubusercontent.com/CODED1NG/GitLISP/main/Install.lsp).
2. In AutoCAD, use **APPLOAD** to load it.
3. Choose **Yes** in the GitLISP setup popup.
4. Restart AutoCAD, then run **GITHUBSTATUS**.

The installer resolves `main` to one commit and downloads all required files
from that revision. There is no file picker and no need to extract a release
beside the installer. Installation and updates preserve your source cache.

The normal installer runs entirely in AutoLISP/COM. It does not launch
PowerShell, change execution policy, or disable AutoCAD security. AutoCAD may
still require its own initial trusted-file approval when you first APPLOAD the
downloaded installer; that host security prompt is separate from our setup popup.

`GITHUBINSTALL` runs the same one-popup installation/update flow again.

The installer creates a per-user Autodesk application bundle. It does not edit
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

## CAD-manager deployment

Deploy the same bundle without dialogs using **Deploy.ps1** through IT's normal
management tool, a user-logon task, or a remote management session. Run in the
**target user's Windows context**, not SYSTEM or a service account.
For Intune, use logged-on credentials and the 64-bit PowerShell host. Respect
IT's script-signing/execution policy; the installer does not override it.

Close AutoCAD before managed deployment. An active session returns exit code
1618 so IT can retry during a maintenance/logon window.

```powershell
# Production: pin the full commit SHA that you tested.
powershell.exe -NoProfile -NonInteractive -File .\Deploy.ps1 -Ref "<40-character-tested-SHA>"

# Pilot users: explicitly select a development branch or tag.
powershell.exe -NoProfile -NonInteractive -File .\Deploy.ps1 -Ref "dev" -Channel Development
```

`dev` is an example branch name; create it first or supply an existing ref.
Both channels use the same install paths, rather than separate installations.
`GITHUBSTATUS` displays the channel, requested ref, and installed commit.

The managed installer verifies downloaded sizes and Git blob hashes, records
ownership of added trust entries in existing AutoCAD profiles, and preserves
source caches during updates. File/profile failures trigger rollback. Backups
and a transaction record remain when rollback cannot complete.

| Exit code | Meaning |
| --- | --- |
| `0` | Installation/update completed |
| `1` | Download, validation, policy, or file operation failed |
| `1618` | AutoCAD is running or another installer lock exists |
| `1003` | A deployment needs recovery; backups were preserved |

The managed result report is
`%LOCALAPPDATA%\3Ding\GitHub\installer\last-result.json`.
For application detection, inspect the bundle's `release.dat` for the required
commit. An existing bundle alone does not establish the intended version.

### Silent deployment from AutoCAD

For an authorized CAD-startup script, suppress the normal APPLOAD popup in a
temporary local scope, then call the data-returning deployment entry point:

```lisp
((lambda (/ *GitLISP-SuppressInstallPrompt* code)
   (setq *GitLISP-SuppressInstallPrompt* T)
   (load "C:/managed/Install.lsp")
   (setq code (GitLISPDeploy "<40-character-tested-SHA>" "Stable"))
   (princ)
))
```

`GitLISPDeploy` makes no dialogs and returns the exit code. Use `"Development"`
with an explicit branch/tag for pilots. Downloaded repository code still loads
only through your explicit `GitHubLoad`/autoload setup.

### Private source access

The installer targets `CODED1NG/GitLISP`. For a private source repository,
provision `GITLISP_TOKEN` in the install process's environment using approved
secret-management tooling. The installers do not save it to their files/logs.
Do not embed tokens in deployment command lines or checked-in scripts.

### Publishing an installer update

Push `Install.lsp`, `Deploy.ps1`, `GitHub.lsp`, `README.md`, and `LICENSE` together
before testing an online install against that revision. The bootstrap cannot
download local changes that have not been published. A revision missing any
required file is rejected before the application is replaced.

## Commands

| Command | What it does |
| --- | --- |
| **GITHUBLOAD** | Ask for a URL, sync it, and load its AutoLISP files |
| **GITHUBSYNC** | Ask for a URL and download/update its cache without executing code |
| **GITHUBPREVIEW** | Ask for a URL and show planned downloads and conflicts |
| **GITHUBSTATUS** | Show installation, AutoCAD profile, and cache locations |
| **GITHUBHELP** | Show the command list |
| **GITHUBINSTALL** | Confirm once, then download/install/update the tool |
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

Uninstall defers while a deployment lock or recovery record exists, preserving
the backups a CAD manager may need.

Removal refuses filesystem reparse points and paths outside the tool's fixed
locations. Locked files or profile settings are reported. Close other AutoCAD
sessions before uninstalling, and restart afterward: definitions already loaded
into open drawings cannot be unloaded by deleting their source files.

## References

- [Autodesk application-bundle components](https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-Customization/files/GUID-3C25E517-8660-4BB7-9447-2310462EF06F.htm)
- [Autodesk installer security requirements](https://help.autodesk.com/cloudhelp/2021/ENU/OARX-IOP/files/GUID-332144C1-3562-493F-B361-9D1A21AF540E.htm)
- [TRUSTEDPATHS](https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-LT/files/GUID-2FB4611D-F141-48D5-9B6E-460EB59351AF.htm)
- [Microsoft Intune user-context PowerShell deployment](https://learn.microsoft.com/intune/device-management/tools/run-powershell-scripts-windows)
