;; 3Ding GitHub setup - Copyright (c) 2026 Denon Deterding.
;; Licensed under the MIT License. See LICENSE.
(vl-load-com)

;; No inputs. Returns the fixed per-user installation and data paths.
(defun GitHub_SetupPaths ( / bundle)
  (setq bundle (strcat (getenv "APPDATA") "\\Autodesk\\ApplicationPlugins\\3DingGitHub.bundle"))
  (list
    (cons "bundle" bundle)
    (cons "contents" (strcat bundle "\\Contents"))
    (cons "state" (strcat bundle "\\install.dat"))
    (cons "data" (strcat (getenv "LOCALAPPDATA") "\\3Ding\\GitHub"))
  )
)

;; path - path spelling. Returns a case-insensitive comparison key.
(defun GitHub_SetupPathKey (path)
  (strcase (vl-string-right-trim "\\" (vl-string-translate "/" "\\" (vl-string-trim " \"" path))))
)

;; No inputs. Returns the current profile's TRUSTEDPATHS registry key.
(defun GitHub_SetupProfileKey ()
  (strcat "HKEY_CURRENT_USER\\" (vlax-user-product-key)
    "\\Profiles\\" (getvar "CPROFILE") "\\Variables"
  )
)

;; text - semicolon-separated paths. Returns nonempty entries in their original order.
(defun GitHub_SetupSplit (text / pos entries part)
  (while (setq pos (vl-string-search ";" text))
    (setq part (substr text 1 pos) text (substr text (+ pos 2)))
    (if (/= part "")
      (setq entries (cons part entries))
    )
  )
  (if (/= text "")
    (setq entries (cons text entries))
  )
  (reverse entries)
)

;; entries - path strings. Returns their semicolon-separated representation.
(defun GitHub_SetupJoin (entries / result entry)
  (setq result "")
  (foreach entry entries
    (setq result (strcat result (if (= result "")
          ""
          ";"
        ) entry
      )
    )
  )
  result
)

;; filename - full path; mode - "r" or "w". Returns an open text stream or nil.
(defun GitHub_SetupOpen (filename mode)
  (if (> (getvar "LISPSYS") 0)
    (open filename mode "utf8")
    (open filename mode)
  )
)

;; directory - full path. Returns T if the directory exists or was created.
(defun GitHub_SetupMkdir (directory / parent)
  (cond
    ((vl-file-directory-p directory) T)
    ((and (setq parent (vl-filename-directory directory)) (/= parent "") (GitHub_SetupMkdir parent))
      (or (vl-mkdir directory) (vl-file-directory-p directory))
    )
  )
)

;; paths - SetupPaths output. Returns only this tool's two trust entries.
(defun GitHub_SetupTrustEntries (paths)
  (list (cdr (assoc "contents" paths)) (strcat (cdr (assoc "data" paths)) "\\sources\\..."))
)

;; state - setup metadata; paths - SetupPaths output. Returns T for owned, valid metadata.
(defun GitHub_SetupIsState (state paths / allowed)
  (setq allowed (mapcar 'GitHub_SetupPathKey (GitHub_SetupTrustEntries paths)))
  (and
    (= (length state) 3)
    (equal (cdr (assoc "product" state)) "3Ding.GitHub")
    (equal (cdr (assoc "version" state)) 1)
    (assoc "profiles" state)
    (listp (cdr (assoc "profiles" state)))
    (vl-every
      '(lambda (entry / key)
        (and
          (listp entry)
          (= (type (car entry)) 'STR)
          (setq key (strcase (car entry)))
          (= (substr key 1 43) "HKEY_CURRENT_USER\\SOFTWARE\\AUTODESK\\AUTOCAD")
          (vl-string-search "\\PROFILES\\" key)
          (= (substr key (max 1 (- (strlen key) 9))) "\\VARIABLES")
          (listp (cdr entry))
          (vl-every
            '(lambda (path)
              (and (= (type path) 'STR) (member (GitHub_SetupPathKey path) allowed))
            )
            (cdr entry)
          )
        )
      )
      (cdr (assoc "profiles" state))
    )
  )
)

;; filename - metadata path; paths - fixed setup paths. Returns validated data or nil.
;; Reads data only; never loads setup metadata as code.
(defun GitHub_SetupReadState (filename paths / stream result line)
  (if (and
      (equal filename (cdr (assoc "state" paths)))
      (null (vl-file-size filename))
      (vl-file-size (strcat filename ".bak"))
    )
    (setq filename (strcat filename ".bak"))
  )
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (if (setq stream (GitHub_SetupOpen filename "r"))
          (progn
            (setq line (read-line stream))
            (if (and line (null (read-line stream)))
              (progn
                (setq line (read line))
                (if (GitHub_SetupIsState line paths)
                  line
                )
              )
            )
          )
        )
      )
    )
  )
  (if stream
    (close stream)
  )
  (if (not (vl-catch-all-error-p result))
    result
  )
)

;; state - validated metadata; paths - fixed paths. Returns T after verified replacement.
;; Records ownership before changing TRUSTEDPATHS, and preserves backups on failure.
(defun GitHub_SetupWriteState (state paths / filename staged backup stream result moved created)
  (setq filename (cdr (assoc "state" paths))
    staged (strcat filename ".new")
    backup (strcat filename ".bak")
  )
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (if (and
            (GitHub_SetupIsState state paths)
            (not (vl-file-size staged))
            (not (vl-file-directory-p staged))
            (not (vl-file-size backup))
            (not (vl-file-directory-p backup))
            (setq stream (GitHub_SetupOpen staged "w"))
          )
          (progn
            (setq created T)
            (prin1 state stream)
            (write-line "" stream)
            (close stream)
            (setq stream nil)
            (if (equal state (GitHub_SetupReadState staged paths))
              (if (or (null (vl-file-size filename)) (setq moved (vl-file-rename filename backup)))
                (if (vl-file-rename staged filename)
                  (progn
                    (if moved
                      (vl-file-delete backup)
                    )
                    T
                  )
                )
              )
            )
          )
        )
      )
    )
  )
  (if stream
    (vl-catch-all-apply 'close (list stream))
  )
  (if (or (vl-catch-all-error-p result) (null result))
    (progn
      (if (and moved (not (vl-file-size filename)))
        (vl-file-rename backup filename)
      )
      (if (and created (vl-file-size staged))
        (vl-file-delete staged)
      )
      nil
    )
    T
  )
)

;; paths/state - setup metadata. Returns T when this profile has both trust entries.
;; Preserves existing paths and records only entries the installer adds.
(defun GitHub_SetupTrust (paths state / key entries keys additions wanted records old result)
  (setq key (GitHub_SetupProfileKey)
    entries (GitHub_SetupSplit (getvar "TRUSTEDPATHS"))
    keys (mapcar 'GitHub_SetupPathKey entries)
  )
  (foreach wanted (GitHub_SetupTrustEntries paths)
    (if (not (member (GitHub_SetupPathKey wanted) keys))
      (setq additions (cons wanted additions) entries (append entries (list wanted)))
    )
  )
  (cond
    ((not (GitHub_SetupRootsSafe paths))
      (prompt "\nGitHub setup: trust-path setup was blocked by an unsafe installation path.")
      nil
    )
    ((null additions) T)
    (t
      (setq records (cdr (assoc "profiles" state)) old (assoc key records))
      (if old
        (setq records (subst (cons key (append (cdr old) (reverse additions))) old records))
        (setq records (cons (cons key (reverse additions)) records))
      )
      (setq state (subst (cons "profiles" records) (assoc "profiles" state) state))
      (if (GitHub_SetupWriteState state paths)
        (progn
          (setq result (vl-catch-all-apply 'setvar (list "TRUSTEDPATHS" (GitHub_SetupJoin entries))))
          (if (vl-catch-all-error-p result)
            (progn
              (prompt "\nGitHub setup: TRUSTEDPATHS is locked or could not be updated.")
              nil
            )
            T
          )
        )
        (progn
          (prompt "\nGitHub setup: could not record trust-path ownership.")
          nil
        )
      )
    )
  )
)

;; state - owned metadata. Returns T after removing installer-added trust entries.
;; Updates active settings through setvar; removes recorded entries from other profiles too.
(defun GitHub_SetupRemoveTrust (state / active entry current remaining owned result valid)
  (setq active (strcase (GitHub_SetupProfileKey)) valid T)
  (foreach entry (cdr (assoc "profiles" state))
    (setq current
      (if (= active (strcase (car entry)))
        (getvar "TRUSTEDPATHS")
        (vl-registry-read (car entry) "TRUSTEDPATHS")
      )
    )
    (if current
      (progn
        (setq owned (mapcar 'GitHub_SetupPathKey (cdr entry))
          remaining (vl-remove-if
            '(lambda (path)
              (member (GitHub_SetupPathKey path) owned)
            )
            (GitHub_SetupSplit current)
          )
          result
          (if (= active (strcase (car entry)))
            (vl-catch-all-apply 'setvar (list "TRUSTEDPATHS" (GitHub_SetupJoin remaining)))
            (vl-catch-all-apply 'vl-registry-write
              (list (car entry) "TRUSTEDPATHS" (GitHub_SetupJoin remaining))
            )
          )
        )
        (if (or (null result) (vl-catch-all-error-p result))
          (setq valid nil)
        )
      )
    )
  )
  valid
)

;; fso - filesystem COM object; path - full path. Returns T for an ordinary file/folder.
;; Reparse points are rejected, including ancestors, before any traversal or deletion.
(defun GitHub_SetupOrdinary (fso path / current object kind valid)
  (setq current path valid T)
  (while (and valid current (/= current ""))
    (setq kind
      (cond
        ((= (vlax-invoke-method fso 'FolderExists current) :vlax-true) 'GetFolder)
        ((= (vlax-invoke-method fso 'FileExists current) :vlax-true) 'GetFile)
      )
    )
    (if kind
      (progn
        (setq object (vlax-invoke-method fso kind current))
        (if (/= 0 (logand 1024 (vlax-get-property object 'Attributes)))
          (setq valid nil)
        )
        (vlax-release-object object)
        (setq object nil)
      )
    )
    (setq current (vlax-invoke-method fso 'GetParentFolderName current))
  )
  valid
)

;; fso - COM filesystem; directory/boundary - absolute paths.
;; Returns T only when the whole tree is inside its boundary without reparse points.
(defun GitHub_SetupTreeSafe (fso directory boundary / child valid prefix)
  (setq prefix (strcat boundary "\\")
    valid (and
      (or (vl-file-directory-p directory) (null (vl-file-size directory)))
      (or
        (= (strcase directory) (strcase boundary))
        (= (strcase (substr directory 1 (strlen prefix))) (strcase prefix))
      )
      (GitHub_SetupOrdinary fso directory)
    )
  )
  (if (and valid (vl-file-directory-p directory))
    (progn
      (foreach child (vl-directory-files directory nil 1)
        (if (not (GitHub_SetupOrdinary fso (strcat directory "\\" child)))
          (setq valid nil)
        )
      )
      (foreach child (vl-directory-files directory nil -1)
        (if (and
            (not (member child '("." "..")))
            (not (GitHub_SetupTreeSafe fso (strcat directory "\\" child) boundary))
          )
          (setq valid nil)
        )
      )
    )
  )
  valid
)

;; paths - fixed setup paths. Returns T when installation targets have safe ancestry.
(defun GitHub_SetupRootsSafe (paths / fso result)
  (setq fso (vlax-create-object "Scripting.FileSystemObject"))
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (and
          (GitHub_SetupTreeSafe fso (cdr (assoc "bundle" paths)) (cdr (assoc "bundle" paths)))
          (GitHub_SetupOrdinary fso (cdr (assoc "data" paths)))
        )
      )
    )
  )
  (vlax-release-object fso)
  (and (not (vl-catch-all-error-p result)) result)
)

;; fso/directory/boundary - prechecked filesystem tree.
;; Returns T when removed. Deletes files individually and only then empty folders.
(defun GitHub_SetupDeleteWalk (fso directory boundary / child valid folder files folders)
  (setq valid (GitHub_SetupTreeSafe fso directory boundary))
  (if (and valid (vl-file-directory-p directory))
    (progn
      (foreach child (vl-directory-files directory nil -1)
        (if (and valid (not (member child '("." ".."))))
          (setq valid (GitHub_SetupDeleteWalk fso (strcat directory "\\" child) boundary))
        )
      )
      (foreach child
        (append
          (vl-remove "install.dat" (vl-directory-files directory nil 1))
          (if (vl-file-size (strcat directory "\\install.dat"))
            '("install.dat")
          )
        )
        (if valid
          (if (GitHub_SetupOrdinary fso (strcat directory "\\" child))
            (setq valid (vl-file-delete (strcat directory "\\" child)))
            (setq valid nil)
          )
        )
      )
      (if valid
        (progn
          (setq folder (vlax-invoke-method fso 'GetFolder directory)
            files (vlax-get-property folder 'Files)
            folders (vlax-get-property folder 'SubFolders)
            valid (and (= 0 (vlax-get-property files 'Count)) (= 0 (vlax-get-property folders 'Count)))
          )
          (vlax-release-object files)
          (vlax-release-object folders)
          (vlax-release-object folder)
          (if valid
            (vlax-invoke-method fso 'DeleteFolder directory :vlax-false)
          )
        )
      )
    )
  )
  valid
)

;; directory - requested target; expected - fixed target from SetupPaths.
;; Returns T after guarded removal; refuses changed paths, files, or reparse points.
(defun GitHub_SetupDeleteTree (directory expected / fso result absolute boundary paths allowed)
  (setq paths (GitHub_SetupPaths)
    allowed (mapcar 'GitHub_SetupPathKey
      (list (cdr (assoc "bundle" paths)) (cdr (assoc "data" paths))
        (strcat (cdr (assoc "data" paths)) "\\sources")
      )
    )
  )
  (setq fso (vlax-create-object "Scripting.FileSystemObject"))
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (setq absolute (vlax-invoke-method fso 'GetAbsolutePathName directory)
          boundary (vlax-invoke-method fso 'GetAbsolutePathName expected)
        )
        (and
          (member (GitHub_SetupPathKey boundary) allowed)
          (= (GitHub_SetupPathKey absolute) (GitHub_SetupPathKey boundary))
          (> (strlen boundary) 20)
          (or (vl-file-directory-p boundary) (null (vl-file-size boundary)))
          (GitHub_SetupDeleteWalk fso absolute boundary)
        )
      )
    )
  )
  (vlax-release-object fso)
  (and (not (vl-catch-all-error-p result)) result)
)

;; paths - install paths. Returns T after writing the bundle activation manifest.
;; Written last so AutoCAD does not discover a half-copied application.
(defun GitHub_SetupPackage (paths / stream line result)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (if (setq stream (GitHub_SetupOpen (strcat (cdr (assoc "bundle" paths)) "\\PackageContents.xml") "w")
          )
          (progn
            (foreach line
              '("<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                "<ApplicationPackage SchemaVersion=\"1.0\" AppVersion=\"1.0.0\" Name=\"3Ding GitHub\" Description=\"GitHub-backed AutoLISP loading\" Author=\"Denon Deterding\" ProductCode=\"{885A15C9-1E61-4EAA-80D5-F5F2EC3159A0}\" UpgradeCode=\"{BA3E6C93-9B2B-47A2-A853-85AE629BE249}\" Helpfile=\"./README.md\">"
                "  <CompanyDetails Name=\"3Ding\" />"
                "  <Components>"
                "    <RuntimeRequirements OS=\"Win64\" Platform=\"AutoCAD*\" SeriesMin=\"R24.0\" />"
                "    <ComponentEntry AppName=\"3DingGitHub\" ModuleName=\"./Contents/GitHub.lsp\" PerDocument=\"True\" />"
                "    <ComponentEntry AppName=\"3DingGitHubSetup\" ModuleName=\"./Contents/Install.lsp\" PerDocument=\"True\" />"
                "  </Components>"
                "</ApplicationPackage>"
              )
              (write-line line stream)
            )
            (close stream)
            (setq stream nil)
            T
          )
        )
      )
    )
  )
  (if stream
    (vl-catch-all-apply 'close (list stream))
  )
  (and (not (vl-catch-all-error-p result)) result)
)

;; source - selected GitHub.lsp; paths - destinations. Returns T after initial install.
;; Existing installations are preserved; this version requires uninstall before upgrade.
(defun GitHub_SetupInstall (source paths / parent state item from to created result)
  (setq parent (vl-filename-directory source)
    state (GitHub_SetupReadState (cdr (assoc "state" paths)) paths)
  )
  (cond
    ((not (GitHub_SetupRootsSafe paths))
      (prompt "\nGitHub setup: an installation path is unsafe or contains a reparse point.")
      nil
    )
    ((vl-file-directory-p (cdr (assoc "bundle" paths)))
      (if state
        (if (vl-every
            '(lambda (relative / file)
              (setq file (strcat (cdr (assoc "bundle" paths)) "\\" relative))
              (and (not (vl-file-directory-p file)) (vl-file-size file))
            )
            '("Contents\\GitHub.lsp" "Contents\\Install.lsp" "README.md" "LICENSE")
          )
          (if (GitHub_SetupTrust paths state)
            (if (vl-file-size (strcat (cdr (assoc "bundle" paths)) "\\PackageContents.xml"))
              (prompt "\nGitHub: already installed. To upgrade, uninstall and install the new copy.")
              (if (GitHub_SetupPackage paths)
                (prompt "\nGitHub: setup repaired. Restart AutoCAD.")
                (prompt "\nGitHub: bundle activation could not be written.")
              )
            )
            (prompt "\nGitHub: installed files were preserved; profile setup is incomplete.")
          )
          (prompt "\nGitHub: installed files are incomplete. Run GITHUBUNINSTALL, then install again.")
        )
        (prompt "\nGitHub setup: an unrecognized bundle already exists; it was preserved.")
      )
    )
    (t
      (setq result
        (vl-catch-all-apply
          '(lambda ()
            (if (vl-every
                '(lambda (name)
                  (vl-file-size (strcat parent "\\" name))
                )
                '("GitHub.lsp" "Install.lsp" "README.md" "LICENSE")
              )
              (if (GitHub_SetupMkdir (vl-filename-directory (cdr (assoc "bundle" paths))))
                (if (setq created (vl-mkdir (cdr (assoc "bundle" paths))))
                  (if (GitHub_SetupMkdir (cdr (assoc "contents" paths)))
                    (progn
                      (setq result T)
                      (foreach item
                        '(("GitHub.lsp" . "Contents\\GitHub.lsp")
                          ("Install.lsp" . "Contents\\Install.lsp")
                          ("README.md" . "README.md") ("LICENSE" . "LICENSE")
                        )
                        (setq from (strcat parent "\\" (car item))
                          to (strcat (cdr (assoc "bundle" paths)) "\\" (cdr item))
                        )
                        (if (not (and (vl-file-copy from to) (= (vl-file-size from) (vl-file-size to))))
                          (setq result nil)
                        )
                      )
                      (setq state '(("product" . "3Ding.GitHub") ("version" . 1) ("profiles")))
                      (and
                        result
                        (GitHub_SetupWriteState state paths)
                        (GitHub_SetupTrust paths state)
                        (GitHub_SetupPackage paths)
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
      (cond
        ((and result (not (vl-catch-all-error-p result)))
          (prompt "\nGitHub: installed successfully. Restart AutoCAD to activate in all drawings.")
          (prompt "\nGitHub: the bundle loads the tool; repository loading remains explicit.")
          T
        )
        (t
          (setq state (GitHub_SetupReadState (cdr (assoc "state" paths)) paths))
          (if (and created (or (null state) (GitHub_SetupRemoveTrust state)))
            (GitHub_SetupDeleteTree (cdr (assoc "bundle" paths)) (cdr (assoc "bundle" paths)))
          )
          (prompt "\nGitHub setup: installation did not complete. Check file access and TRUSTEDPATHS.")
          nil
        )
      )
    )
  )
)

;; message - native error text. Prints unexpected errors; cancellation exits quietly.
;; Returns nothing visible and leaves AutoCAD's surrounding error handler intact.
(defun GitHub_SetupError (message)
  (if (not (wcmatch (strcase message) "*CANCEL*,*QUIT*,*BREAK*"))
    (prompt (strcat "\nGitHub setup: " message))
  )
  (princ)
)

;; No inputs. Guides initial installation; returns nothing visible.
(defun C:GITHUBINSTALL ( / *error* paths source answer result)
  (setq *error* GitHub_SetupError)
  (setq paths (GitHub_SetupPaths))
  (prompt "\n3Ding GitHub installation")
  (prompt (strcat "\nApplication: " (cdr (assoc "bundle" paths))))
  (prompt (strcat "\nCache: " (cdr (assoc "data" paths))))
  (prompt "\nSetup adds only the application folder and cache subfolders to TRUSTEDPATHS.")
  (setq source (getfiled "Select GitHub.lsp from the extracted release folder" "GitHub.lsp" "lsp" 16)
  )
  (if source
    (progn
      (initget "Yes No")
      (setq answer (getkword "\nInstall for this Windows user? [Yes/No] <No>: "))
      (if (= answer "Yes")
        (progn
          (setq result (vl-catch-all-apply 'GitHub_SetupInstall (list source paths)))
          (if (vl-catch-all-error-p result)
            (prompt (strcat "\nGitHub setup: " (vl-catch-all-error-message result)))
          )
        )
        (prompt "\nGitHub setup: cancelled.")
      )
    )
    (prompt "\nGitHub setup: cancelled.")
  )
  (princ)
)

;; No inputs. Deletes cached sources and rate-limit data after confirmation.
;; Keeps the installed tool and trust paths; returns nothing visible.
(defun C:GITHUBCLEARCACHE ( / *error* paths sources fso result answer file)
  (setq *error* GitHub_SetupError)
  (setq paths (GitHub_SetupPaths) sources (strcat (cdr (assoc "data" paths)) "\\sources"))
  (prompt (strcat "\nCache to remove: " sources))
  (prompt "\nThis includes downloaded files and any local edits inside the cache.")
  (initget "Yes No")
  (setq answer (getkword "\nClear all cached sources? [Yes/No] <No>: "))
  (if (= answer "Yes")
    (progn
      (setq result (GitHub_SetupDeleteTree sources sources))
      (setq file (strcat (cdr (assoc "data" paths)) "\\rate-limit.dat"))
      (if (and result (vl-file-size file))
        (progn
          (setq fso (vlax-create-object "Scripting.FileSystemObject"))
          (setq result (and (GitHub_SetupOrdinary fso file) (vl-file-delete file)))
          (vlax-release-object fso)
        )
      )
      (prompt
        (if result
          "\nGitHub: cache cleared. Offline loading needs a new successful sync."
          "\nGitHub: cache could not be completely cleared; unsafe or locked files were preserved."
        )
      )
    )
    (prompt "\nGitHub: cancelled.")
  )
  (princ)
)

;; No inputs. Removes owned setup entries, application bundle, and all default tool data.
;; Requires confirmation; current drawings keep loaded definitions until restart.
;; Returns nothing visible; reports incomplete cleanup so it can be retried.
(defun C:GITHUBUNINSTALL ( / *error* paths state answer result bundle data fso safe)
  (setq *error* GitHub_SetupError)
  (setq paths (GitHub_SetupPaths)
    bundle (cdr (assoc "bundle" paths))
    data (cdr (assoc "data" paths))
    state (GitHub_SetupReadState (cdr (assoc "state" paths)) paths)
  )
  (if (null state)
    (prompt "\nGitHub: no recognized installation found. GITHUBCLEARCACHE can remove cached data.")
    (progn
      (prompt (strcat "\nApplication to remove: " bundle "\nAll tool data to remove: " data))
      (prompt "\nInstaller-added trust entries are removed from recorded AutoCAD profiles.")
      (initget "Yes No")
      (setq answer (getkword "\nUninstall and remove all cached files, including local edits? [Yes/No] <No>: ")
      )
      (if (= answer "Yes")
        (progn
          (setq fso (vlax-create-object "Scripting.FileSystemObject")
            safe (and (GitHub_SetupTreeSafe fso bundle bundle) (GitHub_SetupTreeSafe fso data data))
          )
          (vlax-release-object fso)
          (cond
            ((not safe) (prompt "\nGitHub: uninstall blocked by an unsafe/reparse-point path."))
            ((not (GitHub_SetupRemoveTrust state))
              (prompt "\nGitHub: profile trust settings could not be cleaned. Installation records were retained.")
            )
            ((not (GitHub_SetupDeleteTree data data))
              (prompt "\nGitHub: some data could not be removed. Installation records were retained; retry uninstall.")
            )
            ((not (GitHub_SetupDeleteTree bundle bundle))
              (if (and
                  (vl-file-directory-p bundle)
                  (null (GitHub_SetupReadState (cdr (assoc "state" paths)) paths))
                )
                (GitHub_SetupWriteState state paths)
              )
              (prompt "\nGitHub: the bundle could not be fully removed. Close other AutoCAD sessions and retry.")
            )
            (t
              (setq *GitHub-Disabled* T)
              (prompt "\nGitHub: uninstalled. Restart AutoCAD to clear commands from open drawings.")
            )
          )
        )
        (prompt "\nGitHub: cancelled.")
      )
    )
  )
  (princ)
)

;; No inputs. Prints installation/profile/cache details; returns nothing visible.
(defun C:GITHUBSTATUS ( / *error* paths state)
  (setq *error* GitHub_SetupError)
  (setq paths (GitHub_SetupPaths) state (GitHub_SetupReadState (cdr (assoc "state" paths)) paths))
  (prompt (strcat "\n3Ding GitHub: " (if state
        "installed"
        "running without a registered installation"
      )
    )
  )
  (prompt (strcat "\nProfile: " (getvar "CPROFILE")))
  (prompt (strcat "\nApplication: " (cdr (assoc "bundle" paths))))
  (prompt (strcat "\nCache: " (cdr (assoc "data" paths))))
  (princ)
)

;; No inputs. Enrolls a newly used AutoCAD profile in an existing per-user installation.
;; Returns nothing visible; locked profiles are reported without changing SECURELOAD.
(defun GitHub_SetupStart ( / paths state result)
  (setq paths (GitHub_SetupPaths) state (GitHub_SetupReadState (cdr (assoc "state" paths)) paths))
  (if state
    (progn
      (setq result (vl-catch-all-apply 'GitHub_SetupTrust (list paths state)))
      (if (or (null result) (vl-catch-all-error-p result))
        (prompt "\nGitHub setup: profile trust setup is incomplete. Run GITHUBINSTALL or contact your CAD administrator.")
      )
    )
    (prompt "\n3Ding GitHub setup ready. Type GITHUBINSTALL to begin.")
  )
  (princ)
)

(GitHub_SetupStart)
(princ)
