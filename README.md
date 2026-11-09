# GitLISP

**Use AutoCAD tools from GitHub without writing AutoLISP.** Install GitLISP once,
copy the web address of a tool you want, and paste it into AutoCAD. GitLISP handles
getting the files, keeping a local copy, and loading them for you.

AutoLISP is a language used to add tools and commands to AutoCAD. You do not need
to learn it, edit code, or use Git to get started with GitLISP.

Requires **Windows AutoCAD 2021 or later**, including Civil 3D and other AutoCAD
verticals. You need internet access for installation and the first download of
each tool. Public GitHub projects do not require a GitHub account.

## Install GitLISP

1. Open the [Install.lsp file page on GitHub](https://github.com/CODED1NG/GitLISP/blob/main/Install.lsp).
2. Click the **Download raw file** button (the down-arrow icon above the code).
   Save the file somewhere easy to find, such as your Downloads folder. Keep the
   name **Install.lsp**; do not save it as a `.txt` file. You do not need to copy
   the code displayed on the page or download the whole project.
3. Open AutoCAD. Click its command line, type **APPLOAD**, and press **Enter**.
   If the command line is hidden, press **Ctrl+9** to show it.
4. In the Load/Unload Applications window, browse to **Install.lsp**, select it,
   and click **Load**. AutoCAD may show its own security prompt for this downloaded
   file. Approve it only if you intended to install this copy of GitLISP.
5. Choose **Yes** in the **GitLISP setup** popup. Setup downloads the remaining
   files and configures AutoCAD automatically. Wait for the **GitLISP setup
   complete** popup, then click **OK** and close the APPLOAD window if still open.
6. Restart AutoCAD. Type **GITHUBSTATUS** and press **Enter** to check the
   installation, or **GITHUBHELP** to see the available commands.

If GitLISP is already installed and no setup popup appears, type
**GITHUBINSTALL** and press **Enter** to run setup again.

## Load your first tool

Start with one tool file from a publisher you trust. A GitHub **repository** is
simply a project's main folder; its README usually explains what its tools do
and which commands they add to AutoCAD.

1. In your browser, open the tool's file page on GitHub and copy the address from
   the address bar. You can also copy the address of a folder or an entire
   repository if you want to load all of its AutoLISP files.
2. In AutoCAD, type **GITHUBLOAD** and press **Enter**.
3. At **GitHub URL:**, paste the address you copied and press **Enter**. Paste just
   the address, without quotation marks or any AutoLISP code.
4. Wait for the download and loading messages in the command line.
5. Run the tool's own command as described by its publisher. Loading a tool makes
   its commands available; GitLISP does not know which command you want to run.
   Some tools may also run actions immediately when loaded.

For example, if a tool's README says to run `MYTOOL`, type **MYTOOL** after
GitLISP finishes loading it. `MYTOOL` is only an example; use the actual command
listed by that tool's author. The filename and command name may be different.

Choose a file address when you only want one tool. A folder or repository
address loads every eligible tool in that location, including its subfolders.
Older examples and unfinished scripts may be included in someone else's project.

GitLISP adds its download folder to AutoCAD's trusted paths during setup, so you
do not need to approve each cached file separately. Loading code allows it to
run in AutoCAD: use sources you trust, just as you would with manually downloaded
tools.

## Everyday commands

Type a command in AutoCAD and press **Enter**. No parentheses or coding required.

| Command | Use it to... |
| --- | --- |
| **GITHUBLOAD** | Download a tool and load it into the current drawing |
| **GITHUBPREVIEW** | Check planned file counts and conflicts without loading code |
| **GITHUBSYNC** | Download or update files without loading them |
| **GITHUBHELP** | Show the command list |
| **GITHUBSTATUS** | Check your installation, installed version, and download location |
| **GITHUBINSTALL** | Install the latest GitLISP version after confirmation |
| **GITHUBCLEARCACHE** | Delete downloaded tools while keeping GitLISP installed |
| **GITHUBUNINSTALL** | Remove GitLISP and its stored data |

The three commands that ask for a GitHub address use public repositories.
Private repositories require the advanced authentication options below.

## Updates and working offline

- **Update a downloaded tool:** use **GITHUBLOAD** with the same address again.
  GitLISP normally checks for changes every four hours and uses its local copy
  between checks. **GITHUBSYNC** downloads without running the tool.
- **Use a tool in another drawing:** run **GITHUBLOAD** again with the same
  address. Loading normally applies to the current drawing.
- **Work offline:** use the same address after it has downloaded successfully at
  least once. GitLISP can load an intact local copy if an online refresh fails.
- **Update GitLISP itself:** run **GITHUBINSTALL**, choose **Yes**, wait for the
  completion popup, then restart AutoCAD. Existing downloaded tools are kept.

GitLISP being available in every drawing does not automatically load the tools
you downloaded. A CAD manager can arrange that separately for your team.

## Remove downloads or uninstall

Run **GITHUBCLEARCACHE** to remove all downloaded tools and their tracking data.
The next use of each tool needs internet access to download it again.

Run **GITHUBUNINSTALL** to remove the installed GitLISP application, its default
stored data, and the trusted-path entries it added. Existing trusted paths are
preserved. Your original Downloads file or project checkout is not removed.

Both commands display the locations involved and ask for **Yes** before deleting
anything. Edits made inside the download cache will also be deleted. Close other
AutoCAD sessions before uninstalling, then restart AutoCAD afterward. Deleting
files does not remove commands already loaded into an open drawing.

## If something goes wrong

| What you see | What to do |
| --- | --- |
| The installer link shows code | You are on the right file page. Use the down-arrow **Download raw file** button above the code. |
| No success popup after choosing Yes | Read the last GitLISP message in AutoCAD's command line. Setup only shows the success popup when installation completes. |
| **Unknown command** for a GitLISP command | Restart AutoCAD after installation. Run **GITHUBSTATUS**. If it is still unknown, contact your CAD manager or report the problem. |
| The downloaded tool's command is unknown | Load it with **GITHUBLOAD** in this drawing, then check its README for the correct command name. |
| A file fails to load | Note the filename and error. The publisher's script may need fixing; downloading it again cannot repair a code error. Earlier files in the batch may already have loaded. |
| An online request fails | Check your internet connection and repository access. Public downloads can also be limited temporarily by GitHub. Previously downloaded copies may still work. |
| A message mentions conflicts, changed files, or recovery | Keep the message and contact your CAD manager or report the problem. GitLISP preserves files that need review. |

When reporting an issue, include the GitHub address you used and the relevant
command-line messages. Do not include passwords or access tokens.

## For CAD managers

<details>
<summary>Deployment, installation locations, and managed settings</summary>

### Installation locations and settings

The installer creates a per-user Autodesk application bundle. It does not edit
`acad.lsp`, `acaddoc.lsp`, or the Startup Suite, and does not change `SECURELOAD`.
The interactive installer runs in AutoLISP/COM without launching PowerShell or
changing execution policy. AutoCAD's own initial security prompt is separate
from GitLISP's consent and completion popups.

| Location | Purpose |
| --- | --- |
| `%APPDATA%\Autodesk\ApplicationPlugins\3DingGitHub.bundle` | Application, documentation, license, and setup records |
| `%LOCALAPPDATA%\3Ding\GitHub` | Downloaded sources, manifests, recovery files, and rate-limit data |

Setup adds the bundle's `Contents` folder and the cache's recursive `sources\...`
path to `TRUSTEDPATHS`, preserving existing entries. Other AutoCAD profiles are
enrolled when the bundle loads there. Locked settings are reported rather than
bypassed. Bundle startup depends on the existing `APPAUTOLOAD` configuration.

Uninstall defers if a deployment lock or recovery record exists. Removal refuses
filesystem reparse points and locations outside the tool's fixed paths.

### Managed deployment

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

</details>

## For AutoLISP developers

<details>
<summary>Script calls, authentication, and deferred loading</summary>

The commands above cover normal use. These examples are for scripts and CAD
startup configuration.

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

### File selection and cache details

- Eligible files are `.lsp`, `.fas`, and `.vlx`.
- A file address loads that exact file. Folder/repository addresses load eligible
  files recursively in alphabetical path order; dependency order is not inferred.
- For matching paths and basenames, automatic selection prefers VLX, FAS, then
  LSP. An explicit file address keeps its specified format.
- A source error stops the batch. Earlier definitions remain loaded. Third-party
  code can print its own output or request input.
- Downloads are pinned to one commit, staged before replacement, and tracked by
  a per-source manifest. Local size and modification times are checked; a full
  local content-hash audit is not performed.
- Repository, folder, and individual-file sources have separate caches. Each
  must have synced before offline use. Modified entry files and unfinished
  recovery state block loading.

To load your tested sources whenever a drawing opens, add explicit `GitHubLoad`
calls to your existing `acaddoc.lsp`. Installation does not add these calls.

</details>

## License

GitLISP is licensed under the [MIT License](LICENSE). Tools downloaded from other
repositories keep their own licenses.

## References

- [Autodesk application-bundle components](https://help.autodesk.com/cloudhelp/2024/ENU/AutoCAD-Customization/files/GUID-3C25E517-8660-4BB7-9447-2310462EF06F.htm)
- [Autodesk installer security requirements](https://help.autodesk.com/cloudhelp/2021/ENU/OARX-IOP/files/GUID-332144C1-3562-493F-B361-9D1A21AF540E.htm)
- [TRUSTEDPATHS](https://help.autodesk.com/cloudhelp/2026/ENU/AutoCAD-LT/files/GUID-2FB4611D-F141-48D5-9B6E-460EB59351AF.htm)
- [Microsoft Intune user-context PowerShell deployment](https://learn.microsoft.com/intune/device-management/tools/run-powershell-scripts-windows)
- [GitHub file viewing and download controls](https://docs.github.com/en/repositories/working-with-files/using-files/viewing-and-understanding-files)
