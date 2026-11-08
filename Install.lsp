;; GitLISP online installer v2 - Copyright (c) 2026 Denon Deterding.
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
(defun GitHub_SetupTrust (paths state / key entries keys additions wanted records old result owned)
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
        (progn
          (setq owned (cdr old))
          (foreach wanted (reverse additions)
            (if (not (member (GitHub_SetupPathKey wanted) (mapcar 'GitHub_SetupPathKey owned)))
              (setq owned (append owned (list wanted)))
            )
          )
          (setq records (subst (cons key owned) old records))
        )
        (setq records (cons (cons key (reverse additions)) records))
      )
      (if (or
          (equal records (cdr (assoc "profiles" state)))
          (GitHub_SetupWriteState (subst (cons "profiles" records) (assoc "profiles" state) state) paths)
        )
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

;; ref - branch, tag, or commit text. Returns T for a supported deployment ref.
(defun GitHub_SetupValidRef (ref)
  (and
    (= (type ref) 'STR)
    (<= 1 (strlen ref) 200)
    (null (vl-string-search ".." ref))
    (vl-every
      '(lambda (n)
        (or (<= 48 n 57) (<= 65 n 90) (<= 97 n 122) (member n '(45 46 47 64 43 95)))
      )
      (vl-string->list ref)
    )
  )
)

;; ref - validated ASCII Git ref. Returns a single escaped URL path component.
(defun GitHub_SetupEscapeRef (ref / result n)
  (setq result "")
  (foreach n (vl-string->list ref)
    (setq result
      (strcat result
        (if (or (<= 48 n 57) (<= 65 n 90) (<= 97 n 122) (member n '(45 46 95)))
          (chr n)
          (strcat "%"
            (substr "0123456789ABCDEF" (1+ (fix (/ n 16))) 1)
            (substr "0123456789ABCDEF" (1+ (rem n 16)) 1)
          )
        )
      )
    )
  )
  result
)

;; url - fixed GitHub API/raw URL; accept - requested response type.
;; Returns HTTP body/bytes on success, or nil. GITLISP_TOKEN is optional and never saved.
(defun GitHub_SetupRequest (url accept / http result token body)
  (setq token (getenv "GITLISP_TOKEN"))
  (cond
    ((not
        (or
          (= (substr url 1 23) "https://api.github.com/")
          (= (substr url 1 34) "https://raw.githubusercontent.com/")
        )
      )
      (prompt "\nGitLISP: blocked an unexpected download URL.")
      nil
    )
    ((and
        token
        (/= token "")
        (not (vl-every '(lambda (n)
              (<= 33 n 126)
            ) (vl-string->list token)
          )
        )
      )
      (prompt "\nGitLISP: GITLISP_TOKEN has an invalid format.")
      nil
    )
    (t
      (setq http (vl-catch-all-apply 'vlax-create-object '("WinHttp.WinHttpRequest.5.1")))
      (if (and http (not (vl-catch-all-error-p http)))
        (progn
          (setq result
            (vl-catch-all-apply
              '(lambda ()
                (vlax-invoke-method http 'SetTimeouts 5000 5000 10000 30000)
                (vlax-invoke-method http 'Open "GET" url :vlax-false)
                (vlax-put-property http 'Option 6 :vlax-false)
                (vlax-invoke-method http 'SetRequestHeader "User-Agent" "GitLISP-Installer")
                (vlax-invoke-method http 'SetRequestHeader "Accept" accept)
                (vlax-invoke-method http 'SetRequestHeader "X-GitHub-Api-Version" "2026-03-10")
                (if (and token (/= token ""))
                  (vlax-invoke-method http 'SetRequestHeader "Authorization" (strcat "Bearer " token))
                )
                (vlax-invoke-method http 'Send)
                (if (= 200 (vlax-get-property http 'Status))
                  (progn
                    (setq body (vl-catch-all-apply 'vlax-get-property (list http 'ResponseText)))
                    (list
                      (cons "text" (if (vl-catch-all-error-p body)
                          ""
                          body
                        )
                      )
                      (cons "bytes" (vlax-get-property http 'ResponseBody))
                    )
                  )
                  (progn
                    (prompt (strcat "\nGitLISP: download returned HTTP "
                        (itoa (vlax-get-property http 'Status))
                        ". Check the published revision and repository access."
                      )
                    )
                    nil
                  )
                )
              )
            )
          )
          (vlax-release-object http)
          (setq token nil)
          (if (not (vl-catch-all-error-p result))
            result
          )
        )
      )
    )
  )
)

;; ref - validated branch/tag/SHA. Returns a pinned 40-character SHA, or nil.
(defun GitHub_SetupCommit (ref / response sha)
  (if (and
      (= (strlen ref) 40)
      (vl-every '(lambda (n)
          (or (<= 48 n 57) (<= 65 n 70) (<= 97 n 102))
        )
        (vl-string->list ref)
      )
    )
    (strcase ref T)
    (if (setq response (GitHub_SetupRequest
          (strcat "https://api.github.com/repos/CODED1NG/GitLISP/commits/" (GitHub_SetupEscapeRef ref))
          "application/vnd.github.sha"
        )
      )
      (progn
        (setq sha (vl-string-trim " \t\r\n" (cdr (assoc "text" response))))
        (if (and
            (= (strlen sha) 40)
            (vl-every '(lambda (n)
                (or (<= 48 n 57) (<= 65 n 70) (<= 97 n 102))
              )
              (vl-string->list sha)
            )
          )
          (strcase sha T)
          (progn
            (prompt "\nGitLISP: GitHub did not return a full commit SHA.")
            nil
          )
        )
      )
    )
  )
)

;; response - binary HTTP result; filename - new path; expected - GitHub tree byte count.
;; Returns T after size-verified creation, or nil. Never overwrites an existing file.
(defun GitHub_SetupSaveFile (response filename expected / stream result bytes array count created)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (setq bytes (cdr (assoc "bytes" response))
          array (if (= (type bytes) 'VARIANT)
            (vlax-variant-value bytes)
            bytes
          )
        )
        (if (and array (null (vl-file-size filename)) (not (vl-file-directory-p filename)))
          (progn
            (setq count (1+ (- (vlax-safearray-get-u-bound array 1) (vlax-safearray-get-l-bound array 1))))
            (if (and (= count expected) (<= 1 count 5242880))
              (progn
                (setq stream (vlax-create-object "ADODB.Stream"))
                (vlax-put-property stream 'Type 1)
                (vlax-invoke stream 'Open)
                (vlax-invoke-method stream 'Write bytes)
                (vlax-invoke-method stream 'SaveToFile filename 1)
                (setq created T)
                (= count (vl-file-size filename))
              )
            )
          )
        )
      )
    )
  )
  (if stream
    (progn
      (vl-catch-all-apply 'vlax-invoke-method (list stream 'Close))
      (vlax-release-object stream)
    )
  )
  (if (and (not (vl-catch-all-error-p result)) result)
    T
    (progn
      (if (and created (vl-file-size filename))
        (vl-file-delete filename)
      )
      nil
    )
  )
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
                "<ApplicationPackage SchemaVersion=\"1.0\" AppVersion=\"1.1.0\" Name=\"GitLISP\" Description=\"GitHub-backed AutoLISP loading\" Author=\"Denon Deterding\" ProductCode=\"{885A15C9-1E61-4EAA-80D5-F5F2EC3159A0}\" UpgradeCode=\"{BA3E6C93-9B2B-47A2-A853-85AE629BE249}\" Helpfile=\"./README.md\">"
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

;; json - GitHub tree JSON text. Returns the parsed object/array lists.
(defun GitHub_SetupJSON (json / data newData inStr dPrev strPos d n)
  (setq data (vl-string->list json))
  (foreach d data
    (cond
      ;if we're in a string, test length and continue
      (inStr
        (if (or (setq inStr (and (= 34 d) (/= 92 dPrev))) (<= strPos 2300)) ;[--- MAX string length is 2300 characters ---]
          (setq strPos (1+ strPos) newData (cons d newData))
        );if
        (setq instr (not inStr))
      );cond 1
      ;this signals that we're starting a string
      ((= 34 d) (setq inStr t strPos 1 newData (cons d newData)));cond 2
      ;replacing relevant characters Outside of json object strings
      ((member d '(44 58 91 93 123 125)) ; ("," ":" "[" "]" "{" "}")
        (foreach n (cond
            ((= 44 d) '(41 32 40)) ; ") ("
            ((= 58 d) '(32)) ; " "
            ((or (= 91 d) (= 123 d)) '(40 40)) ; "(("
            ((or (= 93 d) (= 125 d)) '(41 41)) ; "))"
          );cond
          (setq newData (cons n newData))
        );foreach
      );cond 3
      ;this handles numbers.. real/int, pos/neg
      ((member d '(45 46 48 49 50 51 52 53 54 55 56 57)) ; ("-" "." "0" "1" "2" "3" "4" "5" "6" "7" "8" "9")
        (setq newData (cons d newData))
      );cond 4
      ;these will signal a "true" value
      ((or (= 116 d) (= 84 d)) ; ("t" "T")
        (setq newData (cons 116 newData)) ; "t"
      );cond 5
      ;these will signal a "null" or "false" value (both are nil in lisp)
      ((or (= 110 d) (= 102 d) (= 78 d) (= 70 d)) ; ("n" "f" "N" "F")
        (foreach n '(110 105 108)
          (setq newData (cons n newData))
        ) ; "nil"
      );cond 6
    );cond
    (setq dPrev d)
  );foreach
  (read (vl-list->string (reverse newData)))
);defun

;; tree - parsed Git tree. Returns the five required regular-file records, or nil.
(defun GitHub_SetupPayload (tree / names records name wrapper entry found valid)
  (setq names '("GitHub.lsp" "Install.lsp" "Deploy.ps1" "README.md" "LICENSE")
    valid (and (assoc "tree" tree) (assoc "truncated" tree) (null (cadr (assoc "truncated" tree))))
  )
  (foreach name names
    (setq found nil)
    (foreach wrapper (cadr (assoc "tree" tree))
      (setq entry (car wrapper))
      (if (equal name (cadr (assoc "path" entry)))
        (if (and
            (null found)
            (equal (cadr (assoc "type" entry)) "blob")
            (member (cadr (assoc "mode" entry)) '("100644" "100755"))
            (= (type (cadr (assoc "size" entry))) 'INT)
            (<= 1 (cadr (assoc "size" entry)) 5242880)
          )
          (setq found (list (cons "name" name) (cons "size" (cadr (assoc "size" entry)))))
          (setq valid nil)
        )
      )
    )
    (if found
      (setq records (cons found records))
      (progn
        (prompt (strcat "\nGitLISP: required installer file is missing or invalid in the published revision: " name "."))
        (setq valid nil)
      )
    )
  )
  (if valid
    (reverse records)
  )
)

;; filename - new data file; data - printable metadata. Returns T after writing and closing.
(defun GitHub_SetupWriteData (filename data / stream result)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (if (setq stream (GitHub_SetupOpen filename "w"))
          (progn
            (prin1 data stream)
            (write-line "" stream)
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

;; directory - owned directory. Returns T when absent or removed empty, never recursively.
(defun GitHub_SetupEmptyDir (directory / fso folder files folders result)
  (setq fso (vlax-create-object "Scripting.FileSystemObject"))
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (if (and (GitHub_SetupOrdinary fso directory) (vl-file-directory-p directory))
          (progn
            (setq folder (vlax-invoke-method fso 'GetFolder directory)
              files (vlax-get-property folder 'Files)
              folders (vlax-get-property folder 'SubFolders)
            )
            (if (and (= 0 (vlax-get-property files 'Count)) (= 0 (vlax-get-property folders 'Count)))
              (progn
                (vlax-release-object files)
                (setq files nil)
                (vlax-release-object folders)
                (setq folders nil)
                (vlax-release-object folder)
                (setq folder nil)
                (vlax-invoke-method fso 'DeleteFolder directory :vlax-false)
                T
              )
            )
          )
          (and (null (vl-file-size directory)) (not (vl-file-directory-p directory)))
        )
      )
    )
  )
  (if files
    (vlax-release-object files)
  )
  (if folders
    (vlax-release-object folders)
  )
  (if folder
    (vlax-release-object folder)
  )
  (vlax-release-object fso)
  (and (not (vl-catch-all-error-p result)) result)
)

;; file - tracked file snapshot. Returns T when size/time still match.
(defun GitHub_SetupSnapshotMatches (file)
  (and
    (not (vl-file-directory-p (car file)))
    (vl-file-size (car file))
    (equal (vl-file-size (car file)) (cadr file))
    (equal (vl-file-systime (car file)) (caddr file))
  )
)

;; ref - branch/tag/SHA; channel - Stable/Development.
;; Returns 0 on success, 1 on failure, 1618 when busy, or 1003 for retained recovery data.
;; Uses only AutoLISP/COM; no PowerShell policy change or script execution is needed.
(defun GitLISPDeploy
  (ref channel / paths bundle state created lock locked stage fresh backup slot response tree
    payload entry relative filename stagePaths result reason sha pending current
    target saved old installed moved item beforeTrust appliedTrust committed recovery code fso
  )
  (setq paths (GitHub_SetupPaths)
    bundle (cdr (assoc "bundle" paths))
    pending (strcat bundle "\\pending-deploy.json")
    lock (strcat bundle "\\.deploy.lock")
    beforeTrust (getvar "TRUSTEDPATHS")
    code 1
  )
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (cond
          ((not (and (GitHub_SetupValidRef ref) (member channel '("Stable" "Development"))))
            (setq reason "invalid deployment ref or channel.")
          )
          ((or (vl-file-size pending) (vl-file-directory-p pending))
            (setq code 1003 reason "a deployment needs recovery; its backups were preserved.")
          )
          ((or (vl-file-size lock) (vl-file-directory-p lock))
            (setq code 1618 reason "another installation or a stale deployment lock exists.")
          )
          ((not (GitHub_SetupRootsSafe paths)) (setq reason "an installation path is unsafe."))
          ((and
              (vl-file-directory-p bundle)
              (null (setq state (GitHub_SetupReadState (cdr (assoc "state" paths)) paths)))
            )
            (setq reason "an unrecognized bundle exists; it was preserved.")
          )
          ((or
              (vl-file-size (strcat bundle "\\install.dat.bak"))
              (vl-file-size (strcat bundle "\\install.dat.new"))
            )
            (setq code 1003 reason "setup ownership metadata needs recovery before deployment.")
          )
          (t
            (if (not (vl-file-directory-p bundle))
              (if (GitHub_SetupMkdir (vl-filename-directory bundle))
                (setq created (vl-mkdir bundle))
              )
            )
            (if (setq locked (vl-mkdir lock))
              (progn
                (setq slot 0)
                (while (and (null stage) (< slot 1000))
                  (setq filename (strcat bundle "\\.deploy-" (itoa (getvar "MILLISECS")) "-" (itoa slot)))
                  (if (vl-mkdir filename)
                    (setq stage filename)
                  )
                  (setq slot (1+ slot))
                )
                (if stage
                  (progn
                    (setq fresh (strcat stage "\\new") backup (strcat stage "\\backup"))
                    (GitHub_SetupMkdir (strcat fresh "\\Contents"))
                    (GitHub_SetupMkdir (strcat backup "\\Contents"))
                    (prompt "\nGitLISP: resolving the requested build...")
                    (setq sha (GitHub_SetupCommit ref))
                    (if sha
                      (setq response (GitHub_SetupRequest
                          (strcat "https://api.github.com/repos/CODED1NG/GitLISP/git/trees/" sha "?recursive=1")
                          "application/vnd.github+json"
                        )
                      )
                    )
                    (if response
                      (setq tree (GitHub_SetupJSON (cdr (assoc "text" response))) payload (GitHub_SetupPayload tree))
                    )
                    (if (null payload)
                      (setq reason "the published installer files are unavailable or incomplete.")
                    )
                    (foreach entry payload
                      (if (null reason)
                        (progn
                          (setq filename (cdr (assoc "name" entry))
                            relative (if (member filename '("README.md" "LICENSE"))
                              filename
                              (strcat "Contents\\" filename)
                            )
                          )
                          (prompt (strcat "\nGitLISP: downloading " filename "..."))
                          (setq response (GitHub_SetupRequest
                              (strcat "https://raw.githubusercontent.com/CODED1NG/GitLISP/" sha "/" filename)
                              "application/octet-stream"
                            )
                          )
                          (if (not (and
                                response
                                (GitHub_SetupSaveFile response (strcat fresh "\\" relative) (cdr (assoc "size" entry)))
                              )
                            )
                            (setq reason (strcat "could not download and verify " filename "."))
                          )
                        )
                      )
                    )
                    (if (null reason)
                      (progn
                        (if (null state)
                          (setq state '(("product" . "3Ding.GitHub") ("version" . 1) ("profiles")))
                        )
                        (setq stagePaths (subst (cons "state" (strcat fresh "\\install.dat")) (assoc "state" paths) paths)
                        )
                        (if (not (and
                              (GitHub_SetupWriteState state stagePaths)
                              (GitHub_SetupWriteData (strcat fresh "\\release.dat")
                                (list '("repository" . "CODED1NG/GitLISP") (cons "ref" ref)
                                  (cons "commit" sha) (cons "channel" channel)
                                )
                              )
                              (GitHub_SetupPackage (subst (cons "bundle" fresh) (assoc "bundle" paths) paths))
                            )
                          )
                          (setq reason "could not prepare the staged application metadata.")
                        )
                      )
                    )
                    (if (null reason)
                      (progn
                        (setq current (GitHub_SetupOpen pending "w"))
                        (if current
                          (progn
                            (write-line (strcat "{\"installer\":\"AutoLISP\",\"stage\":"
                                (vl-prin1-to-string stage) ",\"commit\":\"" sha "\"}"
                              ) current
                            )
                            (close current)
                            (setq current nil)
                          )
                          (setq reason "could not record the deployment transaction.")
                        )
                      )
                    )
                    (if (null reason)
                      (foreach relative
                        '("PackageContents.xml" "install.dat" "Contents\\GitHub.lsp"
                          "Contents\\Install.lsp" "Contents\\Deploy.ps1" "README.md" "LICENSE" "release.dat"
                        )
                        (if (null reason)
                          (progn
                            (setq target (strcat bundle "\\" relative)
                              saved (strcat backup "\\" relative)
                              old (if (vl-file-size target)
                                (list saved (vl-file-size target) (vl-file-systime target))
                              )
                            )
                            (if old
                              (if (vl-file-rename target saved)
                                (setq moved (cons (cons target old) moved))
                                (setq reason "could not preserve an installed file for rollback.")
                              )
                            )
                            (if (and (null reason) (/= relative "PackageContents.xml"))
                              (if (vl-file-rename (strcat fresh "\\" relative) target)
                                (setq installed (cons (list target (vl-file-size target) (vl-file-systime target)) installed))
                                (setq reason "could not install a staged application file.")
                              )
                            )
                          )
                        )
                      )
                    )
                    (if (null reason)
                      (progn
                        (setq current (GitHub_SetupTrust paths state)
                          appliedTrust (getvar "TRUSTEDPATHS")
                          target (strcat bundle "\\install.dat")
                        )
                        (if (vl-file-size target)
                          (setq installed (subst
                              (list target (vl-file-size target) (vl-file-systime target))
                              (assoc target installed) installed
                            )
                          )
                        )
                        (if (not current)
                          (setq reason "this profile's trust settings could not be configured.")
                        )
                      )
                    )
                    (if (null reason)
                      (if (vl-file-rename (strcat fresh "\\PackageContents.xml") (strcat bundle "\\PackageContents.xml"))
                        (setq committed T code 0)
                        (setq reason "could not activate the installed bundle.")
                      )
                    )
                  )
                  (setq reason "could not create a staging transaction.")
                )
              )
              (setq code 1618 reason "could not acquire the installation lock.")
            )
          )
        )
      )
    )
  )
  (if current
    (vl-catch-all-apply 'close (list current))
  )
  (if (and (not committed) locked)
    (progn
      (if (and appliedTrust (not (equal beforeTrust (getvar "TRUSTEDPATHS"))))
        (if (and
            (equal appliedTrust (getvar "TRUSTEDPATHS"))
            (not (vl-catch-all-error-p (vl-catch-all-apply 'setvar (list "TRUSTEDPATHS" beforeTrust))))
          )
          nil
          (setq recovery T)
        )
      )
      (foreach item installed
        (cond
          ((vl-file-directory-p (car item)) (setq recovery T))
          ((vl-file-size (car item))
            (if (not (and (GitHub_SetupSnapshotMatches item) (vl-file-delete (car item))))
              (setq recovery T)
            )
          )
        )
      )
      (foreach item moved
        (if (not (and
              (null (vl-file-size (car item)))
              (GitHub_SetupSnapshotMatches (cdr item))
              (vl-file-rename (cadr item) (car item))
            )
          )
          (setq recovery T)
        )
      )
    )
  )
  (if (and stage (not recovery))
    (progn
      (setq fso (vlax-create-object "Scripting.FileSystemObject"))
      (setq current (vl-catch-all-apply 'GitHub_SetupDeleteWalk (list fso stage stage)))
      (vlax-release-object fso)
      (if (or (null current) (vl-catch-all-error-p current))
        (setq recovery T)
      )
    )
  )
  (if (and locked (not recovery) (vl-file-size pending))
    (vl-file-delete pending)
  )
  (if locked
    (if (not (GitHub_SetupEmptyDir lock))
      (setq recovery T)
    )
  )
  (if recovery
    (setq code 1003)
  )
  (if (and created (not committed) (not recovery))
    (progn
      (GitHub_SetupEmptyDir (strcat bundle "\\Contents"))
      (GitHub_SetupEmptyDir bundle)
    )
  )
  (cond
    (recovery
      (prompt (strcat "\nGitLISP: deployment recovery is needed. Backups remain in " stage "."))
    )
    (committed
      (prompt (strcat "\nGitLISP: installed " channel " build " (substr sha 1 12) ". Restart AutoCAD."))
    )
    (t
      (prompt (strcat "\nGitLISP: installation did not complete: "
          (cond
            (reason reason)
            ((vl-catch-all-error-p result) (vl-catch-all-error-message result))
            (t "download or file access failed.")
          )
        )
      )
    )
  )
  code
)

;; No inputs. One Yes/No popup authorizes a normal online install/update.
;; Returns nothing visible; progress and the final result appear as plain text.
(defun C:GITHUBINSTALL ( / *error* shell answer result)
  (setq *error* GitHub_SetupError)
  (setq shell (vl-catch-all-apply 'vlax-create-object '("WScript.Shell")))
  (if (and shell (not (vl-catch-all-error-p shell)))
    (progn
      (setq answer (vlax-invoke-method shell 'Popup
          "Install or update GitLISP from CODED1NG/GitLISP on GitHub?\n\nSetup configures the application and cache trust paths. Existing cached sources are kept.\n\nRestart AutoCAD afterward."
          0 "GitLISP setup" 292
        )
      )
      (vlax-release-object shell)
      (if (= answer 6)
        (setq result (GitLISPDeploy "main" "Stable"))
        (prompt "\nGitLISP: installation cancelled.")
      )
    )
    (prompt "\nGitLISP: Windows Script Host is unavailable. Use managed Deploy.ps1 installation.")
  )
  (princ)
)

;; message - native error text. Prints unexpected errors; cancellation exits quietly.
;; Returns nothing visible and leaves AutoCAD's surrounding error handler intact.
(defun GitHub_SetupError (message)
  (if (not (wcmatch (strcase message) "*CANCEL*,*QUIT*,*BREAK*"))
    (prompt (strcat "\nGitHub setup: " message))
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
  (if (or
      (vl-file-size (strcat bundle "\\pending-deploy.json"))
      (vl-file-size (strcat bundle "\\.deploy.lock"))
    )
    (progn
      (setq state nil)
      (prompt "\nGitLISP: deployment is active or needs recovery. Preserve its backups and contact your CAD manager.")
    )
  )
  (if (null state)
    (if (and
        (null (vl-file-size (strcat bundle "\\pending-deploy.json")))
        (null (vl-file-size (strcat bundle "\\.deploy.lock")))
      )
      (prompt "\nGitHub: no recognized installation found. GITHUBCLEARCACHE can remove cached data.")
    )
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

;; paths - fixed setup paths. Returns validated build metadata, or nil.
(defun GitHub_SetupRelease (paths / filename stream value result)
  (setq filename (strcat (cdr (assoc "bundle" paths)) "\\release.dat"))
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (if (setq stream (GitHub_SetupOpen filename "r"))
          (progn
            (setq value (read (read-line stream)))
            (if (and
                (= (length value) 4)
                (equal (cdr (assoc "repository" value)) "CODED1NG/GitLISP")
                (GitHub_SetupValidRef (cdr (assoc "ref" value)))
                (member (cdr (assoc "channel" value)) '("Stable" "Development"))
                (= (type (cdr (assoc "commit" value))) 'STR)
                (= (strlen (cdr (assoc "commit" value))) 40)
              )
              value
            )
          )
        )
      )
    )
  )
  (if stream
    (vl-catch-all-apply 'close (list stream))
  )
  (if (not (vl-catch-all-error-p result))
    result
  )
)

;; No inputs. Prints installation/profile/build/cache details; returns nothing visible.
(defun C:GITHUBSTATUS ( / *error* paths state release)
  (setq *error* GitHub_SetupError
    paths (GitHub_SetupPaths)
    state (GitHub_SetupReadState (cdr (assoc "state" paths)) paths)
    release (GitHub_SetupRelease paths)
  )
  (prompt (strcat "\nGitLISP: " (if state
        "installed"
        "not installed"
      )
    )
  )
  (prompt (strcat "\nProfile: " (getvar "CPROFILE")))
  (if release
    (prompt (strcat "\nBuild: " (cdr (assoc "channel" release)) " / "
        (cdr (assoc "ref" release)) " / " (substr (cdr (assoc "commit" release)) 1 12)
      )
    )
  )
  (prompt (strcat "\nApplication: " (cdr (assoc "bundle" paths))))
  (prompt (strcat "\nCache: " (cdr (assoc "data" paths))))
  (if (vl-file-size (strcat (cdr (assoc "bundle" paths)) "\\pending-deploy.json"))
    (prompt "\nDeployment recovery is pending; backups have been preserved.")
  )
  (princ)
)

;; No inputs. Installed bundles enroll the active profile without dialogs.
;; A standalone APPLOAD asks once to install, unless a managed caller suppresses it.
;; Returns nothing visible; never changes SECURELOAD or execution policy.
(defun GitHub_SetupStart ( / paths state result)
  (setq paths (GitHub_SetupPaths) state (GitHub_SetupReadState (cdr (assoc "state" paths)) paths))
  (cond
    ((or
        (vl-file-size (strcat (cdr (assoc "bundle" paths)) "\\pending-deploy.json"))
        (vl-file-size (strcat (cdr (assoc "bundle" paths)) "\\.deploy.lock"))
          (vl-file-directory-p (strcat (cdr (assoc "bundle" paths)) "\\.deploy.lock"))
      )
      (prompt "\nGitLISP: deployment is active or needs recovery; setup was deferred.")
    )
    (state
      (setq result (vl-catch-all-apply 'GitHub_SetupTrust (list paths state)))
      (if (or (null result) (vl-catch-all-error-p result))
        (prompt "\nGitLISP: profile trust setup is incomplete; contact your CAD administrator.")
      )
    )
    (*GitLISP-SuppressInstallPrompt* (prompt "\nGitLISP: managed setup functions loaded."))
    (t (C:GITHUBINSTALL))
  )
  (princ)
)

(GitHub_SetupStart)
(princ)
