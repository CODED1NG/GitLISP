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

### Try HELLOWORLD

This project's [HELLOWORLD example](examples/HELLOWORLD.lsp) prints a greeting
without changing your drawing:

1. Type **GITHUBLOAD** in AutoCAD and press **Enter**.
2. At **GitHub URL:**, paste this address and press **Enter**:

   ```text
   https://github.com/CODED1NG/GitLISP/blob/main/examples/HELLOWORLD.lsp
   ```

3. When loading finishes, type **HELLOWORLD** and press **Enter**. You should see:

   ```text
   Hello, world! Loaded from GitHub with GitLISP.
   ```

For other tools, use the command listed by their author. A filename and its
command name may be different.

### Choosing other tools

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

**Deploy.ps1** is the silent Windows PowerShell installer for IT deployment or
user-logon scripts. Run it as **the user who will use AutoCAD**, with AutoCAD
closed. For Intune, select logged-on credentials and 64-bit PowerShell. Existing
script-signing/execution policies still apply.

Download [Deploy.ps1](https://github.com/CODED1NG/GitLISP/blob/main/Deploy.ps1)
and run the examples from its folder in PowerShell.

**Choose the version to install.** A *commit* is a saved revision of the project.
Its *SHA* is a unique, 40-character ID. *Pinning* means using that ID so every
user receives the exact revision you tested, even after newer code is published.

| `-Ref` value | Meaning |
| --- | --- |
| `main` | Latest commit on the main development line (a *branch*) |
| A tag name | A named revision, such as a published version tag |
| Full commit SHA | One exact revision; recommended for production |

After testing a build, find it in the [commit history](https://github.com/CODED1NG/GitLISP/commits/main/)
and copy its full SHA. `GITHUBSTATUS` shows only its first 12 characters; the
installed bundle's `release.dat` contains the full ID. Replace
`PASTE_FULL_COMMIT_SHA_HERE` below with that ID, keeping the quotation marks.

```powershell
# Production: install exactly the build you tested.
powershell.exe -NoProfile -NonInteractive -File .\Deploy.ps1 -Ref "PASTE_FULL_COMMIT_SHA_HERE"

# Pilot: test the current main branch before wider deployment.
powershell.exe -NoProfile -NonInteractive -File .\Deploy.ps1 -Ref "main" -Channel Development
```

`-Channel` labels a build as `Stable` (the default) or `Development`; `-Ref`
selects the actual code. Both channels share the same installation location.
`GITHUBSTATUS` displays the channel, requested ref, and installed commit.

Deployment verifies downloaded sizes and Git file hashes, preserves caches, and
records added trust entries. Failures trigger rollback; incomplete rollback
preserves backups for recovery.

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

For a CAD-startup script, load your managed copy of `Install.lsp` with its popup
suppressed. `GitLISPDeploy` accepts a revision and channel, runs without dialogs,
and returns an exit code from the table above:

```lisp
((lambda (/ *GitLISP-SuppressInstallPrompt* code)
   (setq *GitLISP-SuppressInstallPrompt* T)
   (load "C:/managed/Install.lsp")
   (setq code (GitLISPDeploy "PASTE_FULL_COMMIT_SHA_HERE" "Stable"))
   (princ)
))
```

Replace the local installer path and commit placeholder before use.

### Private source access

The installer targets `CODED1NG/GitLISP`. For a private source repository,
provision `GITLISP_TOKEN` in the install process's environment using approved
secret-management tooling. The installers do not save it to their files/logs.
Do not embed tokens in deployment command lines or checked-in scripts.

### Publishing an installer update

Publish `Install.lsp`, `Deploy.ps1`, `GitHub.lsp`, `README.md`, and `LICENSE`
together before online testing. Unpublished changes cannot be downloaded;
revisions missing a required file are rejected before replacement.

</details>

## For AutoLISP developers

<details>
<summary>Functions, authentication, rate limits, and deferred loading</summary>

### Calling GitLISP from a script

Once GitLISP is installed and loaded, these functions let an AutoLISP script
perform the same work as the interactive commands, without asking for a URL.

| Function call | Purpose |
| --- | --- |
| `(GitHubPreview url token)` | Print planned file counts and conflicts without installing files |
| `(GitHubSync url token)` | Download/update files without executing them |
| `(GitHubLoad url token)` | Sync, then load the selected AutoLISP files |
| `(GitHubAutoload url commands token)` | Register commands that load a file on first use |

`url` is a quoted GitHub repository, folder, or file address. `token` is `nil`
for public access, or an access-token string for authenticated access.
`commands` is a list of command names, explained below. These functions print
readable messages and finish without returning a visible data dump.

Replace the example address with your own. Preview, download, and load are
separate choices; you can call `GitHubLoad` directly.

```lisp
(setq toolURL "https://github.com/your-org/cad-tools/blob/main/example.lsp")
(GitHubPreview toolURL nil)
(GitHubSync toolURL nil)
(GitHubLoad toolURL nil)
```

Repository/folder addresses select files recursively. Raw-file addresses,
branch names containing slashes, and UTF-8/percent-encoded paths are supported.

### Authentication

A *personal access token* is a password-like secret that identifies your GitHub
account. It enables private access where permitted and a higher API allowance.
Create one using [GitHub's token instructions](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens),
with only the repository access and read permissions needed.

Have your deployment tooling or CAD manager set a Windows environment variable
named `GITHUB_TOKEN` before starting AutoCAD. An environment variable is a named
value a running application can read; this example passes its value explicitly:

```lisp
(GitHubLoad "https://github.com/your-org/private-tools" (getenv "GITHUB_TOKEN"))
```

`getenv` returns `nil` if the variable is missing, giving anonymous access.
GitLISP does not automatically read `GITHUB_TOKEN` or save supplied tokens.
Keep token values out of source files and command history. The installers use
the separate variable `GITLISP_TOKEN`.

### Rate limits: where they apply and what to do

GitHub limits automated requests to its *REST API*, the service GitLISP uses to
retrieve repository file lists. The usual hourly allowances are:

| Access | Allowance |
| --- | --- |
| Anonymous (`nil`) | 60 requests per public IP address; an office may share this |
| Personal access token | 5,000 requests per account, shared with other account activity |

Tokens from the same account do not create separate allowances. GitHub also
limits bursts of requests, including authenticated ones. See [GitHub's rate-limit guide](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).

| GitLISP operation | Uses this REST allowance? |
| --- | --- |
| Fetch a new/changed repository's file list | Yes; normally one tree request |
| Installer: resolve a branch/tag and fetch its file list | Yes; normally two requests, or one with a full commit SHA |
| Check Git refs or download raw files | No; separate GitHub restrictions can still apply |
| Read already-cached files | No; an online refresh may precede loading |

For example, a first sync of a 200-file repository normally needs **one REST
tree request**, plus 200 raw-file downloads. It does not consume 200 REST requests.
GitLISP's four-hour check interval and reuse of unchanged inventories reduce calls.

**If blocked:** keep the cache, wait for GitHub's reset time or `Retry-After`
delay, and retry later. For a burst limit without timing, wait at least a minute
and increase delays if it persists. Spread team deployments over time.
Use the authenticated example above when anonymous access is insufficient.
Authentication raises the allowance; it does not remove limits.
[GitHub's retry guidance](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#handle-rate-limit-errors-appropriately)
explains these response headers.

GitLISP saves anonymous REST pauses across sessions and can use an intact cache
when refresh fails. Authenticated pauses stop further REST calls within that
operation; callers must wait before starting another. Installers stop on HTTP
errors and need a later retry. HTTP 403 can also mean access was denied; check
permissions if waiting does not resolve it.

### Programmatic results

Scripts that need association lists can call `GitHub_Load`, `GitHub_Sync`,
`GitHub_Preview`, or `GitHub_Autoload` with the same arguments as their normal
counterparts. An association list contains named values your script can inspect:

```lisp
(setq result (GitHub_Preview toolURL nil))
(cdr (assoc "status" result)) ; Read the preview status; nil if no result.
```

### Deferred commands

*Autoload* downloads a file now but waits to execute it until a registered
command is used. Replace the URL and command names with ones your file defines:

```lisp
(GitHubAutoload
  "https://github.com/your-org/cad-tools/blob/main/tools.lsp"
  '("TOOL1" "TOOL2")
  nil
)
```

Use a file URL and command names without `C:`. Registration preserves existing
commands. First use checks and loads the cached file, then runs its command;
command use makes no sync requests.

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
