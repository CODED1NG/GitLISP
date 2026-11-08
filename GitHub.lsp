;; 3Ding GitHub - Copyright (c) 2026 Denon Deterding.
;; Licensed under the MIT License. See LICENSE.

(vl-load-com)

;; Set our preset global vars
(setq
  *GitHub-Root* (strcat (getenv "LOCALAPPDATA") "\\3Ding\\GitHub")
  *GitHub-RestBlocked* nil
  *GitHub-Disabled* nil
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Utility Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Converts json string to list. By Denon Deterding (VL2 - 20200924)
;; NOTE: json object strings will be truncated to 2300 characters MAX ('read' function limitation)
;; ----- (the 'json' input variable is NOT limited to the 2300 chr limit)
;; json - string, as json data
;; returns - list, of data from json
(defun GitHub_ParseJSON->List (json / data newData inStr dPrev strPos d n)
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

;; Parses raw HTTP response headers into an association list
;; raw - string, of headers from GetAllResponseHeaders
;; returns - list, of dotted pairs like ("x-ratelimit-remaining" . "59"), with lowercase names
(defun GitHub_ParseHeaders (raw / pos result line)
  (foreach line (GitHub_Split raw "\r\n")
    (if (setq pos (vl-string-search ":" line))
      (setq result
        (cons
          (cons (strcase (substr line 1 pos) T) (vl-string-trim " \t" (substr line (+ pos 2))))
          result
        )
      )
    )
  )
  (reverse result)
)

;; Encodes an ASCII string as Base64, including required "=" padding.
;; text - string, containing only ASCII characters.
;; returns - Base64 string; "" for empty input; nil for invalid input.
;; Does not print or store credentials.
(defun GitHub_Base64 (text / bytes alphabet result a b c)
  (cond
    ((/= (type text) 'STR) nil)
    ((vl-some
        '(lambda (n)
          (> n 127)
        )
        (setq bytes (vl-string->list text))
      )
      nil
    )
    (t
      (setq alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" result "")
      ;; Convert each group of three bytes into four Base64 characters.
      (while bytes
        (setq a (car bytes)
          b (cadr bytes)
          c (caddr bytes)
          result
          (strcat
            result
            (substr alphabet (1+ (fix (/ a 4))) 1)
            (substr alphabet
              (1+ (+ (* (rem a 4) 16)
                  (if b
                    (fix (/ b 16))
                    0
                  )
                )
              )
              1
            )
            (if b
              (substr alphabet
                (1+ (+ (* (rem b 16) 4)
                    (if c
                      (fix (/ c 64))
                      0
                    )
                  )
                )
                1
              )
              "="
            )
            (if c
              (substr alphabet (1+ (rem c 64)) 1)
              "="
            )
          )
          bytes (cdddr bytes)
        )
      )
      result
    )
  )
)

;; Builds an optional Authorization header.
;; token - token string, or nil for unauthenticated access.
;; endpoint - "git" for refs; "api" or "raw" for API/file requests.
;; returns - header alist, e.g. (("Authorization" . "Bearer ...")).
;;   Returns nil for no token; warns and returns nil for invalid input.
;; Token must contain only printable ASCII characters without spaces.
;; Does not print credentials, persist them, or make web requests.
(defun GitHub_AuthHeaders (token endpoint / value)
  (cond
    ((null token) nil)
    ((not
        (and
          (= (type token) 'STR)
          (/= token "")
          (not
            (vl-some
              '(lambda (n)
                (or (< n 33) (> n 126))
              )
              (vl-string->list token)
            )
          )
        )
      )
      (prompt "\nGitHub error: invalid token format.")
      nil
    )
    ((not (member endpoint '("git" "api" "raw")))
      (prompt "\nGitHub error: unknown authentication endpoint.")
      nil
    )
    (t
      (setq value
        (if (= endpoint "git")
          (strcat "Basic " (GitHub_Base64 (strcat "x-access-token:" token)))
          (strcat "Bearer " token)
        )
      )
      (list (cons "Authorization" value))
    )
  )
)

;; Checks whether a URL is eligible to receive GitHub credentials.
;; url - string, requiring HTTPS and one of these exact hosts:
;;   github.com, api.github.com, raw.githubusercontent.com.
;; returns - T if allowed, otherwise nil.
;; Rejects explicit ports, embedded credentials, whitespace,
;; control characters, and backslashes. Makes no web requests.
(defun GitHub_IsAuthURL (url / authority delimiter pos)
  (and
    (= (type url) 'STR)
    (= (strcase (substr url 1 8)) "HTTPS://")
    (not
      (vl-some
        '(lambda (n)
          (or (<= n 32) (= n 127) (= n 92))
        )
        (vl-string->list url)
      )
    )
    (progn
      ;; Authority ends before the first path, query, or fragment.
      (setq authority (substr url 9))
      (foreach delimiter '("/" "?" "#")
        (if (setq pos (vl-string-search delimiter authority))
          (setq authority (substr authority 1 pos))
        )
      )
      (member (strcase authority T) '("github.com" "api.github.com" "raw.githubusercontent.com"))
    )
  )
)

;; Makes an HTTP GET request with optional request headers.
;; url - string, of URL to request.
;; headers - alist of header name/value dotted pairs, or nil.
;; returns - alist containing "status", "headers", "body", and "bytes".
;;   Returns nil for a blocked URL or a request/COM failure.
;; Authorization requires GitHub_IsAuthURL approval and disables redirects.
;; Authenticated redirects return their HTTP 3xx response to the caller.
;; Response headers have lowercase names; use "bytes" for binary content.
(defun GitHub_WebGet (url headers / http result header authenticated body)
  (foreach header headers
    (if (= (strcase (car header)) "AUTHORIZATION")
      (setq authenticated T)
    )
  )
  (cond
    ((and authenticated (not (GitHub_IsAuthURL url)))
      (prompt "\nGitHub error: credentials blocked for unapproved URL.")
      nil
    )
    ((or
        (null (setq http (vl-catch-all-apply 'vlax-create-object '("WinHttp.WinHttpRequest.5.1"))))
        (vl-catch-all-error-p http)
      )
      nil
    )
    (t
      (setq result
        (vl-catch-all-apply
          '(lambda ()
            (vlax-invoke-method http 'SetTimeouts 3000 3000 5000 10000)
            (vlax-invoke-method http 'Open "GET" url :vlax-false)

            ;; WinHttpRequestOption_EnableRedirects = 6.
            (if authenticated
              (vlax-put-property http 'Option 6 :vlax-false)
            )

            (vlax-invoke-method http 'SetRequestHeader "User-Agent" "3Ding-GitHub")
            (foreach header headers
              (vlax-invoke-method http 'SetRequestHeader (car header) (cdr header))
            )
            (vlax-invoke-method http 'Send)
            ;; Binary responses may not have a readable text representation.
            (setq body (vl-catch-all-apply 'vlax-get-property (list http 'ResponseText)))
            (list
              (cons "status" (vlax-get-property http 'Status))
              (cons "headers" (GitHub_ParseHeaders (vlax-invoke-method http 'GetAllResponseHeaders)))
              (cons "body" (if (vl-catch-all-error-p body)
                  ""
                  body
                )
              )
              (cons "bytes" (vlax-get-property http 'ResponseBody))
            )
          )
        )
      )
      (vlax-release-object http)
      (if (not (vl-catch-all-error-p result))
        result
      )
    )
  )
)

;; Converts a hexadecimal string to an integer
;; hex - string, of hexadecimal digits like "015b"
;; returns - integer, else nil if hex is empty or contains a non-hex character
(defun GitHub_HexToInt (hex / result c)
  (if (and (/= hex "") (not (wcmatch (strcase hex) "*[~0-9A-F]*")))
    (progn
      (setq result 0)
      (foreach c (vl-string->list (strcase hex))
        (setq result (+ (* result 16) (- c (if (> c 57)
                55
                48
              )
            )
          )
        )
      )
      result
    )
  )
)

;; Parses a Git smart HTTP ref advertisement (info/refs) into the default branch and its refs
;; bytes - variant, of raw response bytes ("bytes" from GitHub_WebGet)
;; returns - list, like (("head" . "refs/heads/master") ("refs" ("HEAD" . "<sha>") ("refs/heads/master" . "<sha>") ...)), else nil if unreadable
(defun GitHub_ParseRefs (bytes / data text size pos len line tokens token sha name head refs)
  (setq data (vl-catch-all-apply '(lambda ()
        (vlax-safearray->list (vlax-variant-value bytes))
      )
    )
  )
  (if (and data (not (vl-catch-all-error-p data)))
    (progn
      ;; NUL only separates the first ref from its capabilities, and ref names never contain spaces
      (setq text (vl-list->string (subst 32 0 data)) size (strlen text) pos 1)
      ;; Each pkt-line starts with 4 hex digits giving its total length; "0000" is a flush marker
      (while (and (<= (+ pos 3) size) (setq len (GitHub_HexToInt (substr text pos 4))))
        (cond
          ((= len 0) (setq pos (+ pos 4)))
          ((< len 4) (setq pos (1+ size))) ;; malformed, stop reading
          (t
            (setq line (vl-string-right-trim "\n" (substr text (+ pos 4) (- len 4))) pos (+ pos len))
            (if (/= (substr line 1 1) "#")
              (progn
                (setq tokens (GitHub_Split line " ") sha (car tokens) name (cadr tokens))
                ;; Capabilities on the first ref line name the default branch
                (foreach token (cddr tokens)
                  (if (wcmatch token "symref=HEAD:*")
                    (setq head (substr token 13))
                  )
                )
                (cond
                  ((or (null name) (= name "capabilities^{}")))
                  ;; "^{}" lines give the commit an annotated tag points to; replace the tag's entry
                  ((wcmatch name "*^{}")
                    (setq name (substr name 1 (- (strlen name) 3))
                      refs (cons (cons name sha) (vl-remove (assoc name refs) refs))
                    )
                  )
                  (t (setq refs (cons (cons name sha) refs)))
                )
              )
            )
          )
        )
      )
      (if refs
        (list (cons "head" head) (cons "refs" (reverse refs)))
      )
    )
  )
)

;; Fetches and parses a repository's advertised Git refs.
;; data - alist from GitHub_ParseGitHubURL; uses "owner" and "repo".
;; token - token string, or nil for unauthenticated access.
;; returns - alist from GitHub_ParseRefs, e.g.:
;;   (("head" . "refs/heads/main")
;;    ("refs"
;;      ("HEAD" . "<40-character SHA>")
;;      ("refs/heads/main" . "<40-character SHA>")))
;;   "head" is the default branch name, or nil if not advertised.
;;   "refs" maps advertised ref names to SHAs; annotated tags use
;;   their peeled commit SHA.
;;   On failure, prints a warning and returns nil.
;; Makes at most one Git smart HTTP request; credentials are not persisted.
(defun GitHub_GetRefs (data token / owner repo headers response status parsed)
  (setq owner (cdr (assoc "owner" data)) repo (cdr (assoc "repo" data)))
  (cond
    ((not (and owner repo)) (prompt "\nGitHub error: missing repository owner or name.") nil)
    ;; AuthHeaders reports invalid tokens; stop without requesting.
    ((and token (null (setq headers (GitHub_AuthHeaders token "git")))) nil)
    ((null
        (setq response
          (GitHub_WebGet
            (strcat "https://github.com/" owner "/" repo ".git/info/refs?service=git-upload-pack")
            headers
          )
        )
      )
      (prompt "\nGitHub warning: unable to refresh repository refs.")
      nil
    )
    ((/= (setq status (cdr (assoc "status" response))) 200)
      (prompt (strcat "\nGitHub error: repository refs request returned HTTP " (itoa status) "."))
      nil
    )
    ((null (setq parsed (GitHub_ParseRefs (cdr (assoc "bytes" response)))))
      (prompt "\nGitHub error: no readable repository refs returned.")
      nil
    )
    (t parsed)
  )
)

;; Fetches a complete recursive tree at a pinned commit.
;; data - alist from GitHub_ParseGitHubURL; uses "owner" and "repo".
;; commit - full commit SHA from GitHub_ResolveRef.
;; token - token string, or nil for unauthenticated access.
;; returns - parsed Trees API object; read values with cadr, not cdr.
;;   "sha" is the root tree SHA; "tree" contains wrapped entry objects.
;;   Warns and returns nil on failure or an incomplete (truncated) tree.
;; Fetches the whole repository; path filtering is a separate step.
(defun GitHub_GetTree (data commit token / owner repo headers response status parsed)
  (setq owner (cdr (assoc "owner" data)) repo (cdr (assoc "repo" data)))
  (cond
    ((not
        (and
          (= (type owner) 'STR)
          (/= owner "")
          (= (type repo) 'STR)
          (/= repo "")
          (= (type commit) 'STR)
          (= (strlen commit) 40)
          (not (wcmatch (strcase commit) "*[~0-9A-F]*"))
        )
      )
      (prompt "\nGitHub error: repository and full commit SHA required for tree request.")
      nil
    )
    ((and token (null (setq headers (GitHub_AuthHeaders token "api")))) nil)
    ((null
        (setq response
          (GitHub_RestGet
            (strcat "https://api.github.com/repos/" owner "/" repo "/git/trees/" commit "?recursive=1")
            (append
              '(("Accept" . "application/vnd.github+json") ("X-GitHub-Api-Version" . "2026-03-10"))
              headers
            )
            token
          )
        )
      )
      (prompt "\nGitHub error: unable to request repository tree.")
      nil
    )
    ((/= (setq status (cdr (assoc "status" response))) 200)
      (prompt (strcat "\nGitHub error: repository tree request returned HTTP " (itoa status) "."))
      nil
    )
    (t
      ;; Keep malformed JSON or unexpected response shapes from escaping.
      (setq parsed
        (vl-catch-all-apply
          '(lambda (/ object sha)
            (setq object (GitHub_ParseJSON->List (cdr (assoc "body" response)))
              sha (cadr (assoc "sha" object))
            )
            (if
              (and
                (= (type sha) 'STR)
                (= (strlen sha) 40)
                (not (wcmatch (strcase sha) "*[~0-9A-F]*"))
                (assoc "tree" object)
                (listp (cadr (assoc "tree" object)))
                (assoc "truncated" object)
                (member (cadr (assoc "truncated" object)) '(nil T))
              )
              object
            )
          )
        )
      )
      (cond
        ((or (vl-catch-all-error-p parsed) (null parsed))
          (prompt "\nGitHub error: no readable repository tree returned.")
          nil
        )
        ((cadr (assoc "truncated" parsed))
          (prompt "\nGitHub error: repository tree is incomplete; sync skipped.")
          nil
        )
        (t parsed)
      )
    )
  )
)

;; Checks for a valid GitHub URL
;; url - string, of GitHub URL to check
;; returns - t/nil, of validity
(defun GitHub_IsValidGitHubURL (url / s pos)
  (and
    (= (type url) 'STR)
    (not (wcmatch url "*[ \t\r\n]*"))
    (progn
      (setq s (strcase url))
      (if (wcmatch s "HTTP://*")
        (setq s (substr s 8))
      )
      (if (wcmatch s "HTTPS://*")
        (setq s (substr s 9))
      )
      (setq pos (vl-string-position 47 s))
      (and
        pos
        (member (substr s 1 pos) '("GITHUB.COM" "WWW.GITHUB.COM" "RAW.GITHUBUSERCONTENT.COM"))
        (> (strlen s) (1+ pos))
      )
    )
  )
)

;; Parses a string into a list of substrings based on a delimiter
;; str - string, to split
;; delimiter - string, to use as delimiter for splitting
;; returns - list, of substrings
(defun GitHub_Split (str delimiter / pos result)
  (while (setq pos (vl-string-search delimiter str))
    (setq result (cons (substr str 1 pos) result) str (substr str (+ pos (strlen delimiter) 1)))
  )
  (reverse (cons str result))
)

;; Joins a list of strings into a single string with a delimiter
;; items - list, of strings to join
;; delimiter - string, to use as delimiter between items
;; returns - string, of joined items
(defun GitHub_Join (items delimiter / result item)
  (if items
    (progn
      (setq result (car items))
      (foreach item (cdr items)
        (setq result (strcat result delimiter item))
      )
      result
    )
  )
)

;; Rejects truncated/overlong UTF-8, surrogate code points, and values above U+10FFFF.
;; Inputs: bytes - list of byte integers.
;; Returns: T for canonical UTF-8 byte data; otherwise nil.
(defun GitHub_IsUTF8 (bytes / valid remaining value minimum n)
  (setq valid T remaining 0)
  (foreach n bytes
    (if valid
      (cond
        ((> remaining 0)
          (if (<= 128 n 191)
            (progn
              (setq value (+ (* value 64) (- n 128)) remaining (1- remaining))
              (if (and (= remaining 0) (or (< value minimum) (> value 1114111) (<= 55296 value 57343)))
                (setq valid nil)
              )
            )
            (setq valid nil)
          )
        )
        ((<= 0 n 127))
        ((<= 194 n 223) (setq remaining 1 value (- n 192) minimum 128))
        ((<= 224 n 239) (setq remaining 2 value (- n 224) minimum 2048))
        ((<= 240 n 244) (setq remaining 3 value (- n 240) minimum 65536))
        (t (setq valid nil))
      )
    )
  )
  (and valid (= remaining 0))
)

;; Decodes a percent-escaped byte run as UTF-8. Invalid encodings return nil.
;; A round trip rejects ADO's replacement characters and legacy-engine data loss.
;; Inputs: bytes - list of byte integers.
(defun GitHub_UTF8Text (bytes / stream result array text expected safe n)
  (cond
    ((not (GitHub_IsUTF8 bytes)) nil)
    ((null bytes) "")
    (t
      (setq stream (vl-catch-all-apply 'vlax-create-object '("ADODB.Stream")))
      (if (and stream (not (vl-catch-all-error-p stream)))
        (progn
          (setq result
            (vl-catch-all-apply
              '(lambda ()
                ;; Prefix ASCII so an encoded BOM remains part of the filename.
                (setq bytes (cons 65 bytes)
                  array (vlax-make-safearray 17 (cons 0 (1- (length bytes))))
                  expected ""
                  safe (vl-string->list "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
                )
                (vlax-safearray-fill array bytes)
                (foreach n bytes
                  (setq expected (strcat expected
                      (if (member n safe)
                        (chr n)
                        (strcat "%"
                          (substr "0123456789ABCDEF" (1+ (fix (/ n 16))) 1)
                          (substr "0123456789ABCDEF" (1+ (rem n 16)) 1)
                        )
                      )
                    )
                  )
                )
                (vlax-put-property stream 'Type 1)
                (vlax-invoke stream 'Open)
                (vlax-invoke-method stream 'Write (vlax-make-variant array))
                (vlax-put-property stream 'Position 0)
                (vlax-put-property stream 'Type 2)
                (vlax-put-property stream 'Charset "utf-8")
                (setq text (vlax-invoke-method stream 'ReadText -1))
                (if (equal expected (GitHub_EncodeURLPath text))
                  (substr text 2)
                )
              )
            )
          )
          (vl-catch-all-apply 'vlax-invoke-method (list stream 'Close))
          (vlax-release-object stream)
          (if (not (vl-catch-all-error-p result))
            result
          )
        )
      )
    )
  )
)

;; Decodes URL path escapes once; '+' remains a literal plus sign.
;; Rejects malformed escapes, control characters, backslashes, and invalid UTF-8.
;; Returns decoded text or nil. Makes no file changes or web requests.
(defun GitHub_DecodeURLPart (text / pos size char byte bytes decoded result valid)
  (if (= (type text) 'STR)
    (progn
      (setq pos 1 size (strlen text) result "" valid T)
      (while (and valid (<= pos size))
        (setq char (substr text pos 1))
        (if (= char "%")
          (progn
            (setq bytes nil)
            (while (and valid (<= pos size) (= (substr text pos 1) "%"))
              (if (and
                  (<= (+ pos 2) size)
                  (setq byte (GitHub_HexToInt (substr text (1+ pos) 2)))
                  (>= byte 32)
                  (/= byte 127)
                  (/= byte 92)
                )
                (setq bytes (cons byte bytes) pos (+ pos 3))
                (setq valid nil)
              )
            )
            (if valid
              (if (setq decoded (GitHub_UTF8Text (reverse bytes)))
                (setq result (strcat result decoded))
                (setq valid nil)
              )
            )
          )
          (if (or (< (ascii char) 32) (= (ascii char) 127) (= char "\\"))
            (setq valid nil)
            (setq result (strcat result char) pos (1+ pos))
          )
        )
      )
      (if valid
        result
      )
    )
  )
)

;; Parses GitHub URL into structured metadata, including API endpoint
;; url - string, of GitHub URL to parse
;; returns - list, of structured metadata, else nil if invalid
(defun GitHub_ParseGitHubURL
  (url / clean pos parts host segments owner repo kind ref path api prefix namespace delimiter segment decoded valid)
  ;; Remove query strings and fragments
  (setq clean (if (= (type url) 'STR)
      url
      ""
    )
  )
  (foreach delimiter '("?" "#")
    (if (setq pos (vl-string-search delimiter clean))
      (setq clean (substr clean 1 pos))
    )
  )
  ;; Remove URL scheme
  (if (setq pos (vl-string-search "://" clean))
    (setq clean (substr clean (+ pos 4)))
  )
  ;; Extract hostname and URL segments
  (setq parts (GitHub_Split clean "/") host (strcase (car parts) T) segments nil valid T)
  ;; Decode after splitting, so an escaped separator cannot change owner/repo.
  (foreach segment (vl-remove "" (cdr parts))
    (if (setq decoded (GitHub_DecodeURLPart segment))
      (setq segments (cons decoded segments))
      (setq valid nil)
    )
  )
  (setq segments (reverse segments))
  (if (and valid (>= (length segments) 2))
    (progn
      (setq valid
        (vl-every
          '(lambda (name)
            (and
              (/= name "")
              (not (member name '("." "..")))
              (vl-every
                '(lambda (n)
                  (or (<= 48 n 57) (<= 65 n 90) (<= 97 n 122) (member n '(45 46 95)))
                )
                (vl-string->list name)
              )
            )
          )
          (list (car segments) (cadr segments))
        )
      )
      ;; Encoded slashes in a ref/path have the same meaning as literal slashes.
      (if (cddr segments)
        (setq segments (append (list (car segments) (cadr segments))
            (GitHub_Split (GitHub_Join (cddr segments) "/") "/")
          )
        )
      )
    )
  )
  (if (and
      valid
      (member host '("github.com" "www.github.com" "raw.githubusercontent.com"))
      (>= (length segments) 2)
      (not (vl-some '(lambda (name)
            (member name '("" "." ".."))
          ) segments
        )
      )
      (/= (strcase (cadr segments)) ".GIT")
      (if (= host "raw.githubusercontent.com")
        (if (and (= (caddr segments) "refs") (member (cadddr segments) '("heads" "tags")))
          (>= (length segments) 6)
          (>= (length segments) 4)
        )
        (or
          (= (length segments) 2)
          (and (= (caddr segments) "tree") (>= (length segments) 4))
          (and (= (caddr segments) "blob") (>= (length segments) 5))
        )
      )
    )
    (progn
      (setq owner (car segments) repo (cadr segments) kind "repository" ref nil path nil)
      ;; Remove optional .git suffix from repository name
      (if (eq (strcase (cond
              ((vl-filename-extension repo))
              ("")
            )
          ) ".GIT"
        )
        (setq repo (vl-filename-base repo))
      )
      (cond
        ;; Standard GitHub URLs
        ((member host '("github.com" "www.github.com"))
          (cond
            ((member (caddr segments) '("tree" "blob"))
              (setq kind
                (if (= (caddr segments) "tree")
                  "folder"
                  "file"
                )
                ref (cadddr segments)
                path (GitHub_Join (cddddr segments) "/")
              )
            )
          )
        )
        ;; Raw GitHub file URLs
        ((= host "raw.githubusercontent.com")
          (setq kind "file")
          (if (and (= (caddr segments) "refs") (member (cadddr segments) '("heads" "tags")))
            (setq namespace (cadddr segments)
              ref (car (cddddr segments))
              path (GitHub_Join (cdr (cddddr segments)) "/")
            )
            (setq ref (caddr segments) path (GitHub_Join (cdddr segments) "/"))
          )
        )
      )
      ;; Construct GitHub API endpoint.
      (setq prefix (strcat "https://api.github.com/repos/" owner "/" repo))
      (setq api
        (cond
          ((= kind "repository") prefix)
          ((and path ref)
            (strcat prefix "/contents/" (GitHub_EncodeURLPath path) "?ref=" (GitHub_EncodeURLPath ref))
          )
          (t nil)
        )
      )
      ;; Return structured metadata
      (list
        (cons "type" kind)
        (cons "owner" owner)
        (cons "repo" repo)
        (cons "ref" ref)
        (cons "path" (if path
            (GitHub_Split path "/")
            nil
          )
        )
        (cons "api" api)
        (cons "namespace" namespace)
      )
    )
  )
)

;; Resolves a parsed GitHub URL to a ref, remaining path, and commit SHA.
;; data - list from GitHub_ParseGitHubURL; uses "type", "ref", and "path".
;; refData - list from GitHub_ParseRefs; contains:
;;   "head" - default branch name, e.g. "refs/heads/main".
;;   "refs" - dotted pairs mapping full ref names to commit SHAs.
;; returns - list, e.g.:
;;   (("ref" . "refs/heads/main")
;;    ("path" "lisp" "test.lsp")
;;    ("commit" . "<40-character SHA>"))
;;   "ref" is a full ref name, "HEAD" fallback, or a supplied commit SHA.
;;   "path" is a list of segments after the matched ref; nil for repo URLs.
;;   "commit" is the resolved commit SHA.
;;   On failure, prints a warning and returns nil. Makes no web requests.
(defun GitHub_ResolveRef (data refData / ref path refs head segments prefix match name commit resolvedPath namespace)
  (setq ref (cdr (assoc "ref" data))
    path (cdr (assoc "path" data))
    refs (cdr (assoc "refs" refData))
    namespace (cdr (assoc "namespace" data))
  )
  (cond
    ;; Repository URLs use the advertised default branch.
    ((= (cdr (assoc "type" data)) "repository")
      (setq head (cdr (assoc "head" refData)))
      (setq match (if head
          (assoc head refs)
        )
      )
      (if (null match)
        (setq match (assoc "HEAD" refs))
      )
      (if match
        (setq name (car match) commit (cdr match))
      )
    )
    ;; A full commit SHA needs no branch/tag lookup.
    ((and
        (null namespace)
        (= (type ref) 'STR)
        (= (strlen ref) 40)
        (not (wcmatch (strcase ref) "*[~0-9A-F]*"))
      )
      (setq name ref commit ref resolvedPath path)
    )
    ;; Rebuild the URL tail and keep its longest matching ref.
    ((and ref refs)
      (setq segments (cons ref path))

      (while segments
        (setq prefix
          (if prefix
            (strcat prefix "/" (car segments))
            (car segments)
          )
          segments (cdr segments)
        )
        (setq match
          (if (/= namespace "tags")
            (assoc (strcat "refs/heads/" prefix) refs)
          )
        )
        (if (and (null match) (/= namespace "heads"))
          (setq match (assoc (strcat "refs/tags/" prefix) refs))
        )
        (if match
          (setq name (car match) commit (cdr match) resolvedPath segments)
        )
      )
    )
  )
  (if commit
    (list (cons "ref" name) (cons "path" resolvedPath) (cons "commit" commit))
    (progn
      (prompt "\nGitHub error: unable to resolve URL to a commit.")
    )
  )
)

;; Filters a complete tree to the requested repository, folder, or file.
;; data - GitHub_ParseGitHubURL output; uses "type".
;; resolved - GitHub_ResolveRef output; uses "path" and "commit".
;; tree - GitHub_GetTree output, with the JSON parser's wrapped entries.
;; returns - (("commit" . sha) ("files" file ...)), or warns and returns nil.
;;   Each file has dotted pairs for "path", "sha", "size", and "mode".
;; Paths stay repository-relative. Folders include all regular descendants.
;; Skips symlinks and submodules. An empty "files" list is a valid result.
;; Makes no web requests or local file changes.
(defun GitHub_FilterTree
  (data resolved tree / result kind target prefix commit entries wrapped entry
    path entryType mode sha size files found valid
  )
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (setq kind (cdr (assoc "type" data))
          target (GitHub_Join (cdr (assoc "path" resolved)) "/")
          prefix (if target
            (strcat target "/")
          )
          commit (cdr (assoc "commit" resolved))
        )
        (if
          (and
            (member kind '("repository" "folder" "file"))
            (or (/= kind "file") (and target (/= target "")))
            (= (type commit) 'STR)
            (= (strlen commit) 40)
            (not (wcmatch (strcase commit) "*[~0-9A-F]*"))
            (assoc "tree" tree)
            (listp (cadr (assoc "tree" tree)))
            (assoc "truncated" tree)
            (null (cadr (assoc "truncated" tree)))
          )
          (progn
            (setq entries (cadr (assoc "tree" tree))
              found (or (= kind "repository") (and (= kind "folder") (null target)))
              valid T
            )
            ;; The JSON parser represents an empty array as (nil).
            (if (equal entries '(nil))
              (setq entries nil)
            )
            (foreach wrapped entries
              (setq entry (car wrapped)
                path (cadr (assoc "path" entry))
                entryType (cadr (assoc "type" entry))
                mode (cadr (assoc "mode" entry))
                sha (cadr (assoc "sha" entry))
                size (cadr (assoc "size" entry))
              )
              ;; Reject malformed metadata rather than silently dropping files.
              (if
                (not
                  (and
                    (= (type path) 'STR)
                    (/= path "")
                    (= (type sha) 'STR)
                    (= (strlen sha) 40)
                    (not (wcmatch (strcase sha) "*[~0-9A-F]*"))
                    (or
                      (and
                        (= entryType "blob")
                        (member mode '("100644" "100755" "120000"))
                        (numberp size)
                        (>= size 0)
                      )
                      (and (= entryType "tree") (= mode "040000"))
                      (and (= entryType "commit") (= mode "160000"))
                    )
                  )
                )
                (setq valid nil)
              )
              (if (and (= kind "folder") (= entryType "tree") (= path target))
                (setq found T)
              )
              (if
                (and
                  valid
                  (= entryType "blob")
                  (member mode '("100644" "100755"))
                  (cond
                    ((= kind "repository") T)
                    ((= kind "file") (= path target))
                    ((null target) T)
                    (t (= (substr path 1 (strlen prefix)) prefix))
                  )
                )
                (progn
                  (if (= kind "file")
                    (setq found T)
                  )
                  (setq files
                    (cons (list (cons "path" path) (cons "sha" sha) (cons "size" size) (cons "mode" mode)) files)
                  )
                )
              )
            )
            (if (and valid found)
              (list (cons "commit" commit) (cons "files" (reverse files)))
            )
          )
        )
      )
    )
  )
  (if (or (vl-catch-all-error-p result) (null result))
    (progn
      (prompt "\nGitHub error: requested path is unavailable or tree data is invalid/incomplete.")
      nil
    )
    result
  )
)

;; Checks a repository-relative file path for use in the Windows cache.
;; path - nonempty string using forward slashes between path segments.
;; returns - T if valid, otherwise nil; makes no file changes.
;; Rejects absolute/traversal paths, empty segments, invalid characters,
;; reserved device names, and names Windows may trim or normalize.
;; Checks path spelling only; does not resolve filesystem junctions.
(defun GitHub_IsCachePath (path / valid segment base)
  (and
    (= (type path) 'STR)
    (/= path "")
    (not
      (vl-some
        '(lambda (n)
          (or (< n 32) (= n 127) (member n '(34 42 58 60 62 63 92 124)))
        )
        (vl-string->list path)
      )
    )
    (progn
      (setq valid T)
      (foreach segment (GitHub_Split path "/")
        (setq base (strcase (vl-string-right-trim " " (car (GitHub_Split segment ".")))))
        (if
          (or
            (= segment "")
            (/= segment (vl-string-trim " " segment))
            (= (substr segment (max 1 (strlen segment)) 1) ".")
            (member base '("CON" "PRN" "AUX" "NUL" "CLOCK$" "CONIN$" "CONOUT$"))
            (and
              (= (strlen base) 4)
              (member (substr base 1 3) '("COM" "LPT"))
              ;; Windows also reserves ports with superscript 1, 2, or 3.
              (member (ascii (substr base 4 1)) '(49 50 51 52 53 54 55 56 57 185 178 179))
            )
          )
          (setq valid nil)
        )
      )
      valid
    )
  )
)

;; Creates an empty cache manifest for a resolved source.
;; data - GitHub_ParseGitHubURL output; uses "owner", "repo", and "type".
;; resolved - GitHub_ResolveRef output; uses "ref" and resolved "path".
;; returns - versioned manifest alist, or warns and returns nil.
;; "source" preserves ref/path case; owner/repo are lowercase.
;; "commit" and "files" describe installed content, so they start empty.
;; "checked-at" starts empty; "check-hours" defaults to four hours.
;; Makes no web requests or local file changes; stores no credentials.
(defun GitHub_NewManifest
  (data resolved / result owner repo kind ref path)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (setq owner (cdr (assoc "owner" data))
          repo (cdr (assoc "repo" data))
          kind (cdr (assoc "type" data))
          ref (cdr (assoc "ref" resolved))
          path (cdr (assoc "path" resolved))
        )
        (if
          (and
            (= (type owner) 'STR)
            (/= owner "")
            (= (type repo) 'STR)
            (/= repo "")
            (member kind '("repository" "folder" "file"))
            (= (type ref) 'STR)
            (/= ref "")
            (listp path)
            (not
              (vl-some
                '(lambda (segment)
                  (not (and (= (type segment) 'STR) (/= segment "")))
                )
                path
              )
            )
            (or (/= kind "repository") (null path))
            (or (/= kind "file") path)
          )
          (list
            (cons "version" 1)
            (cons "source"
              (list
                (cons "owner" (strcase owner T))
                (cons "repo" (strcase repo T))
                (cons "type" kind)
                (cons "ref" ref)
                (cons "path" path)
              )
            )
            (cons "commit" nil)
            (cons "checked-at" nil)
            (cons "check-hours" 4.0)
            (cons "files" nil)
          )
        )
      )
    )
  )
  (if (or (vl-catch-all-error-p result) (null result))
    (progn
      (prompt "\nGitHub error: valid source metadata required for a new manifest.")
      nil
    )
    result
  )
)

;; Validates a version-1 cache manifest without reading or changing files.
;; manifest - alist from GitHub_NewManifest or a saved manifest.
;; returns - T if valid, otherwise nil; does not print warnings.
;; Installed files require path, sha, size, mode, and modified fields.
;; "modified" holds vl-file-systime output (seven or eight integers).
;; "checked-at" is nil or an AutoCAD DATE value; zero check-hours is allowed.
;; Rejects extra/duplicate fields, unsafe or duplicate paths, and files
;; outside the source selection. File metadata is not proof of disk contents.
(defun GitHub_IsManifest
  (manifest / result source owner repo kind ref path target prefix commit
    checked hours files seen
  )
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (setq source (cdr (assoc "source" manifest))
          owner (cdr (assoc "owner" source))
          repo (cdr (assoc "repo" source))
          kind (cdr (assoc "type" source))
          ref (cdr (assoc "ref" source))
          path (cdr (assoc "path" source))
          target (GitHub_Join path "/")
          prefix (if target
            (strcat target "/")
          )
          commit (cdr (assoc "commit" manifest))
          checked (cdr (assoc "checked-at" manifest))
          hours (cdr (assoc "check-hours" manifest))
          files (cdr (assoc "files" manifest))
        )
        (and
          (= (length manifest) 6)
          (vl-every '(lambda (key)
              (assoc key manifest)
            )
            '("version" "source" "commit" "checked-at" "check-hours" "files")
          )
          (= (type (cdr (assoc "version" manifest))) 'INT)
          (= (cdr (assoc "version" manifest)) 1)
          (= (length source) 5)
          (vl-every '(lambda (key)
              (assoc key source)
            )
            '("owner" "repo" "type" "ref" "path")
          )
          (= (type owner) 'STR)
          (/= owner "")
          (= owner (strcase owner T))
          (= (type repo) 'STR)
          (/= repo "")
          (= repo (strcase repo T))
          (member kind '("repository" "folder" "file"))
          (= (type ref) 'STR)
          (/= ref "")
          (listp path)
          (vl-every
            '(lambda (segment)
              (and (= (type segment) 'STR) (/= segment "") (null (vl-string-search "/" segment)))
            )
            path
          )
          (or (null path) (GitHub_IsCachePath target))
          (or (/= kind "repository") (null path))
          (or (/= kind "file") path)
          (or
            (null commit)
            (and
              (= (type commit) 'STR)
              (= (strlen commit) 40)
              (not (wcmatch (strcase commit) "*[~0-9A-F]*"))
            )
          )
          (or (null checked) (and (numberp checked) (> checked 0)))
          (numberp hours)
          (>= hours 0)
          (listp files)
          (or commit (null files))
          (vl-every
            '(lambda (file / name sha size mode modified key)
              (setq name (cdr (assoc "path" file))
                sha (cdr (assoc "sha" file))
                size (cdr (assoc "size" file))
                mode (cdr (assoc "mode" file))
                modified (cdr (assoc "modified" file))
              )
              (and
                (= (length file) 5)
                (vl-every '(lambda (field)
                    (assoc field file)
                  )
                  '("path" "sha" "size" "mode" "modified")
                )
                (GitHub_IsCachePath name)
                (= (type sha) 'STR)
                (= (strlen sha) 40)
                (not (wcmatch (strcase sha) "*[~0-9A-F]*"))
                (= (type size) 'INT)
                (>= size 0)
                (member mode '("100644" "100755"))
                (listp modified)
                (member (length modified) '(7 8))
                (vl-every '(lambda (n)
                    (= (type n) 'INT)
                  ) modified
                )
                (<= 1601 (nth 0 modified) 9999)
                (<= 1 (nth 1 modified) 12)
                (<= 0 (nth 2 modified) 7)
                (<= 1 (nth 3 modified) 31)
                (<= 0 (nth 4 modified) 23)
                (<= 0 (nth 5 modified) 59)
                (<= 0 (nth 6 modified) 59)
                (or (= (length modified) 7) (<= 0 (nth 7 modified) 999))
                (cond
                  ((= kind "repository") T)
                  ((= kind "file") (= name target))
                  ((null target) T)
                  (t (= (substr name 1 (strlen prefix)) prefix))
                )
                (not (member (setq key (strcase name)) seen))
                (setq seen (cons key seen))
              )
            )
            files
          )
        )
      )
    )
  )
  (and (not (vl-catch-all-error-p result)) result)
)

;; Keeps real-valued settings as decimal strings on disk to avoid prin1 rounding.
;; The in-memory schema remains unchanged; strings and integers still use prin1.
;; Inputs: manifest - manifest data.
;; Returns: manifest with persistent decimal fields encoded as strings, or nil.
(defun GitHub_EncodeManifest (manifest / data key pair)
  (if (GitHub_IsManifest manifest)
    (progn
      (setq data manifest)
      (foreach key '("checked-at" "check-hours")
        (setq pair (assoc key data))
        (if (= (type (cdr pair)) 'REAL)
          (setq data (subst (cons key (rtos (cdr pair) 2 16)) pair data))
        )
      )
      data
    )
  )
)

;; Accepts decimal wire values and legacy numeric values, then validates the schema.
;; Inputs: data - encoded on-disk manifest data.
;; Returns: validated in-memory manifest, or nil.
(defun GitHub_DecodeManifest (data / key pair number valid)
  (setq valid T)
  (foreach key '("checked-at" "check-hours")
    (setq pair (assoc key data))
    (if (= (type (cdr pair)) 'STR)
      (if (and
          (/= (cdr pair) "")
          (not (wcmatch (cdr pair) "*[~0-9.]*"))
          (setq number (distof (cdr pair) 2))
        )
        (setq data (subst (cons key number) pair data))
        (setq valid nil)
      )
    )
  )
  (if (and valid (GitHub_IsManifest data))
    data
  )
)

;; Compares manifests after serialization. Ownership/file metadata stays exact.
;; Only check time allows 10 ms roundoff; interval allows 1e-12 hours roundoff.
;; Inputs: expected - expected value; actual - current value.
;; Returns: T when source/ownership/settings and checked times agree; otherwise nil.
(defun GitHub_ManifestEqual (expected actual)
  (and
    (GitHub_IsManifest expected)
    (GitHub_IsManifest actual)
    (vl-every
      '(lambda (key)
        (equal (cdr (assoc key expected)) (cdr (assoc key actual)))
      )
      '("version" "source" "commit" "files")
    )
    (equal (cdr (assoc "checked-at" expected)) (cdr (assoc "checked-at" actual)) (/ 0.01 86400.0))
    (equal (cdr (assoc "check-hours" expected)) (cdr (assoc "check-hours" actual)) 1e-12)
  )
)

;; Reads and validates a manifest saved as one line by prin1.
;; filename - full path to the manifest file.
;; returns - manifest alist, or nil if missing, unreadable, or invalid.
;; Missing files are silent; other failures print one warning.
;; Uses UTF-8 with the Unicode Lisp engine, otherwise legacy encoding.
;; Requires prin1 formatting (outer whitespace is allowed) and no extra data.
;; Never evaluates file contents. Closes the file even if reading fails.
(defun GitHub_ReadManifest
  (filename / result stream closed missing engine line parsed)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (cond
          ((not (and (= (type filename) 'STR) (/= filename ""))) nil)
          ((null (vl-file-size filename)) (setq missing T) nil)
          (t
            (setq engine (getvar "LISPSYS")
              stream
              (if (and engine (> engine 0))
                (open filename "r" "utf8")
                (open filename "r")
              )
            )
            (if stream
              (progn
                (setq line (read-line stream))
                ;; Allow a UTF-8 BOM when a text editor added one.
                (if (and line (> (strlen line) 0) (= (ascii (substr line 1 1)) 65279))
                  (setq line (substr line 2))
                )
                (if
                  (and
                    line
                    (null (read-line stream))
                    (setq parsed (read line))
                    ;; read accepts trailing expressions; require a full match.
                    (= (vl-string-trim " \t\r" line) (vl-prin1-to-string parsed))
                    (setq parsed (GitHub_DecodeManifest parsed))
                  )
                  parsed
                )
              )
            )
          )
        )
      )
    )
  )
  (if stream
    (setq closed (vl-catch-all-apply 'close (list stream)))
  )
  (cond
    (missing nil)
    ((or (vl-catch-all-error-p result) (null result) (vl-catch-all-error-p closed))
      (prompt "\nGitHub error: manifest could not be read or validated.")
      nil
    )
    (t result)
  )
)

;; Writes and verifies a temporary manifest beside its intended destination.
;; filename - full destination path; its parent directory must already exist.
;; manifest - valid version-1 manifest data.
;; returns - staged file's full path on success; warns and returns nil on failure.
;; The destination is untouched. Caller must rename or delete the staged file.
;; Uses the same encoding as GitHub_ReadManifest and verifies a full round-trip.
(defun GitHub_StageManifest
  (filename manifest / result directory staged stream engine closed cleanup reason)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (if
          (and
            (= (type filename) 'STR)
            (/= filename "")
            (setq directory (vl-filename-directory filename))
            ;; Require a drive-rooted or UNC path, not a relative directory.
            (or
              (and
                (wcmatch (strcase (substr filename 1 1)) "[A-Z]")
                (= (substr filename 2 1) ":")
                (member (substr filename 3 1) '("/" "\\"))
              )
              (= (substr filename 1 2) "\\\\")
            )
            (vl-file-directory-p directory)
            (not (vl-file-directory-p filename))
            (GitHub_IsManifest manifest)
          )
          (progn
            (setq staged (vl-filename-mktemp "ghman" directory ".tmp")
              engine (getvar "LISPSYS")
              stream
              (if (and engine (> engine 0))
                (open staged "w" "utf8")
                (open staged "w")
              )
            )
            (if stream
              (progn
                (prin1 (GitHub_EncodeManifest manifest) stream)
                (write-line "" stream)
                (close stream)
                (setq stream nil)
                (if (GitHub_ManifestEqual manifest (GitHub_ReadManifest staged))
                  staged
                  (progn
                    (setq reason "manifest round-trip verification failed.")
                    nil
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
    (setq closed (vl-catch-all-apply 'close (list stream)))
  )
  (if (or (vl-catch-all-error-p result) (null result) (vl-catch-all-error-p closed))
    (progn
      (if staged
        (progn
          (setq cleanup
            (vl-catch-all-apply
              '(lambda ()
                (or (null (vl-file-size staged)) (vl-file-delete staged))
              )
            )
          )
          (if (or (vl-catch-all-error-p cleanup) (null cleanup))
            (prompt (strcat "\nGitHub warning: temporary manifest retained at " staged))
          )
        )
      )
      (prompt
        (strcat "\nGitHub error: "
          (cond
            ((vl-catch-all-error-p result)
              (strcat "manifest staging failed: " (vl-catch-all-error-message result))
            )
            (reason reason)
            (t "manifest could not be staged and verified.")
          )
        )
      )
      nil
    )
    result
  )
)

;; Stages, verifies, and installs a manifest using same-directory renames.
;; filename - full destination path; parent directory must already exist.
;; manifest - valid version-1 manifest data.
;; returns - T when installed; nil on failure, with a warning.
;; Keeps the old file at filename.bak until replacement succeeds.
;; An existing backup blocks writing so recovery data is never overwritten.
;; On failure, restores the old file when possible; reports retained backups.
;; An interruption can leave a .bak file requiring recovery.
(defun GitHub_WriteManifest
  (filename manifest / result staged backup hadOld moved installed reported
    reason restored cleanup
  )
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (cond
          ((not (and (= (type filename) 'STR) (/= filename "")))
            (setq reason "full manifest path required.")
            nil
          )
          ((progn
              (setq backup (strcat filename ".bak"))
              (or (vl-file-size backup) (vl-file-directory-p backup))
            )
            (setq reason (strcat "existing manifest backup requires recovery: " backup))
            nil
          )
          ((null (setq staged (GitHub_StageManifest filename manifest)))
            ;; StageManifest already reported this failure.
            (setq reported T)
            nil
          )
          (t
            (setq hadOld (not (null (vl-file-size filename))))
            (and
              (or (not hadOld) (setq moved (vl-file-rename filename backup)))
              (setq installed (vl-file-rename staged filename))
            )
          )
        )
      )
    )
  )
  (cond
    ((and (not (vl-catch-all-error-p result)) result installed)
      (if moved
        (progn
          (setq cleanup (vl-catch-all-apply 'vl-file-delete (list backup)))
          (if (or (vl-catch-all-error-p cleanup) (null cleanup))
            (prompt (strcat "\nGitHub warning: manifest saved; backup retained at " backup))
          )
        )
      )
      T
    )
    (t
      ;; Do not remove a destination that appeared after the failed rename.
      (if moved
        (progn
          (setq restored (vl-catch-all-apply 'vl-file-rename (list backup filename)))
          (if (or (vl-catch-all-error-p restored) (null restored))
            (prompt (strcat "\nGitHub warning: old manifest retained for recovery at " backup))
          )
        )
      )
      (if staged
        (progn
          (setq cleanup
            (vl-catch-all-apply
              '(lambda ()
                (or (null (vl-file-size staged)) (vl-file-delete staged))
              )
            )
          )
          (if (or (vl-catch-all-error-p cleanup) (null cleanup))
            (prompt (strcat "\nGitHub warning: temporary manifest retained at " staged))
          )
        )
      )
      (if (not reported)
        (prompt
          (strcat "\nGitHub error: "
            (if reason
              reason
              "manifest replacement failed."
            )
          )
        )
      )
      nil
    )
  )
)

;; Determines whether a source is due for another remote check.
;; manifest - version-1 manifest, or nil when no usable manifest exists.
;; returns - T when due; nil while a cached source is within its interval.
;; Missing/invalid manifests, no installed commit, or no check time are due.
;; Uses AutoCAD DATE (local Julian days); a backward clock change forces a check.
;; Zero check-hours checks every time. Makes no requests or file changes.
(defun GitHub_ShouldCheck (manifest / checked hours now)
  (cond
    ((not (GitHub_IsManifest manifest)) T)
    ((null (cdr (assoc "commit" manifest))) T)
    ((null (setq checked (cdr (assoc "checked-at" manifest)))) T)
    (t
      (setq hours (cdr (assoc "check-hours" manifest)) now (getvar "DATE"))
      (or (= hours 0) (< (+ now (/ 0.01 86400.0)) checked) (>= (* 24.0 (- now checked)) hours))
    )
  )
)

;; Recursively creates directories for a given path if they do not exist
;; path - string, of directory path to create
;; returns - t if successful or already exists, nil if failed
(defun GitHub_Mkdir (path / parent)
  (setq path (vl-string-right-trim "\\/" path))
  (cond
    ((vl-file-directory-p path) T)
    ((and
        (setq parent (vl-filename-directory path))
        (/= parent "")
        (GitHub_Mkdir parent)
        (or (vl-mkdir path) (vl-file-directory-p path))
      )
    )
  );cond
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Cache identity and REST pacing
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Compact directory key; full source identity is always checked separately.
;; Returns: eight-character cache-directory key.
(defun GitHub_SourceKey (source / a b n digit key)
  (setq a 1 b 7 key "")
  (foreach n (vl-string->list (vl-prin1-to-string source))
    (setq a (rem (+ (* a 257) n) 65521) b (rem (+ (* b 263) n) 65519))
  )
  (foreach n (list a b)
    (setq digit "")
    (repeat 4
      (setq digit (strcat (substr "0123456789ABCDEF" (1+ (rem n 16)) 1) digit) n (fix (/ n 16)))
    )
    (setq key (strcat key digit))
  )
  key
)

;; Describes an existing or prospective cache without creating directories.
;; Inputs: directory - full directory path; manifest - manifest data.
;; Returns: cache paths, manifest, and recovery status.
(defun GitHub_CacheInfo (directory manifest / backup recovery)
  (setq backup (strcat directory "\\manifest.dat.bak"))
  (if (and (null manifest) (vl-file-size backup))
    (setq manifest (GitHub_ReadManifest backup) recovery T)
  )
  (list (cons "directory" directory)
    (cons "files-root" (strcat directory "\\files"))
    (cons "manifest-file" (strcat directory "\\manifest.dat"))
    (cons "manifest" manifest) (cons "recovery" recovery)
  )
)

;; Hash collisions get numbered slots; source identity must match exactly.
;; Unclaimed existing directories are preserved rather than reused.
;; Returns: existing/prospective source cache descriptor, or nil.
(defun GitHub_SourceCache (source / base key slot directory cache manifest found)
  (setq base (strcat *GitHub-Root* "\\sources\\source-") key (GitHub_SourceKey source) slot 0)
  (while (and (not found) (< slot 1000))
    (setq directory (strcat base key (if (= slot 0)
          ""
          (strcat "-" (itoa slot))
        )
      )
    )
    (cond
      ((and (not (vl-file-directory-p directory)) (null (vl-file-size directory)))
        (setq found (GitHub_CacheInfo directory nil))
      )
      ((vl-file-directory-p directory)
        (setq cache
          (GitHub_CacheInfo directory (GitHub_ReadManifest (strcat directory "\\manifest.dat")))
        )
        (setq manifest (cdr (assoc "manifest" cache)))
        (if (and manifest (equal source (cdr (assoc "source" manifest))))
          (setq found cache)
        )
      )
    )
    (setq slot (1+ slot))
  )
  (if (null found)
    (prompt "\nGitHub error: could not allocate a source cache slot.")
  )
  found
)

;; Finds a previously resolved source before making network requests.
;; Inputs: data - parsed URL metadata.
;; Returns: matching installed cache descriptor, or nil.
(defun GitHub_FindCachedSource
  (data / base folder cache manifest source ref short tail matches namespace
    priority checked best bestPriority bestChecked
  )
  (setq base (strcat *GitHub-Root* "\\sources")
    bestPriority -1
    bestChecked -1.0
    namespace (cdr (assoc "namespace" data))
    tail (if (cdr (assoc "ref" data))
      (cons (cdr (assoc "ref" data)) (cdr (assoc "path" data)))
    )
  )
  (if (vl-file-directory-p base)
    (foreach folder (vl-directory-files base "source-*" -1)
      (setq cache
        (GitHub_CacheInfo (strcat base "\\" folder)
          (GitHub_ReadManifest (strcat base "\\" folder "\\manifest.dat"))
        )
      )
      (setq manifest (cdr (assoc "manifest" cache))
        source (cdr (assoc "source" manifest))
        ref (cdr (assoc "ref" source))
      )
      (if manifest
        (progn
          (setq short
            (cond
              ((= (substr ref 1 11) "refs/heads/") (substr ref 12))
              ((= (substr ref 1 10) "refs/tags/") (substr ref 11))
              (t ref)
            )
          )
          (setq matches
            (and
              (= (strcase (cdr (assoc "owner" data)) T) (cdr (assoc "owner" source)))
              (= (strcase (cdr (assoc "repo" data)) T) (cdr (assoc "repo" source)))
              (= (cdr (assoc "type" data)) (cdr (assoc "type" source)))
              (or
                (null namespace)
                (and (= namespace "heads") (= (substr ref 1 11) "refs/heads/"))
                (and (= namespace "tags") (= (substr ref 1 10) "refs/tags/"))
              )
              (or
                (= (cdr (assoc "type" data)) "repository")
                (equal tail (append (GitHub_Split short "/") (cdr (assoc "path" source))))
              )
            )
          )
          (setq priority (if (= (substr ref 1 11) "refs/heads/")
              1
              0
            )
            checked (cdr (assoc "checked-at" manifest))
          )
          (if (null checked)
            (setq checked 0.0)
          )
          (if (and
              matches
              (or (> priority bestPriority) (and (= priority bestPriority) (> checked bestChecked)))
            )
            (setq best cache bestPriority priority bestChecked checked)
          )
        )
      )
    )
  )
  best
)

;; UTC epoch seconds using Windows timezone conversion, including DST.
;; Inputs: none.
;; Returns: UTC epoch seconds, or nil when Windows time conversion fails.
(defun GitHub_UnixTime ( / object result value)
  (setq object (vl-catch-all-apply 'vlax-create-object '("WbemScripting.SWbemDateTime")))
  (if (and object (not (vl-catch-all-error-p object)))
    (progn
      (setq result
        (vl-catch-all-apply
          '(lambda ()
            ;; AutoCAD DATE is midnight-based Julian; OLE starts 1899-12-30.
            (vlax-invoke-method object 'SetVarDate
              (vlax-make-variant (- (getvar "DATE") 2415019.0) 7) :vlax-true
            )
            (setq value (vlax-invoke-method object 'GetVarDate :vlax-false))
            (if (= (type value) 'VARIANT)
              (setq value (vlax-variant-value value))
            )
            (* 86400.0 (- value 25569.0))
          )
        )
      )
      (vlax-release-object object)
      (if (not (vl-catch-all-error-p result))
        result
      )
    )
  )
)

;; Saves only the anonymous blocked-until UTC timestamp, never a token.
;; Invalid state conservatively pauses REST for an hour and is repaired.
;; Returns: anonymous REST deadline, or nil if unavailable.
(defun GitHub_Backoff (until / filename stream result line value closed writing)
  (setq filename (strcat *GitHub-Root* "\\rate-limit.dat"))
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (if (null until)
          (if (vl-file-size filename)
            (if (setq stream (open filename "r"))
              (progn
                (setq line (read-line stream))
                (if (and
                    line
                    (/= line "")
                    (not (wcmatch line "*[~0-9]*"))
                    (null (read-line stream))
                    (> (setq value (atof line)) 0)
                  )
                  value
                )
              )
            )
            0.0
          )
          (progn
            (setq writing T stream (open filename "w"))
            (if stream
              (progn
                (write-line (rtos (+ until 1.0) 2 0) stream)
                until
              )
            )
          )
        )
      )
    )
  )
  (if stream
    (setq closed (vl-catch-all-apply 'close (list stream)))
  )
  (if (or (vl-catch-all-error-p result) (null result) (vl-catch-all-error-p closed))
    (if writing
      (progn
        (prompt "\nGitHub warning: REST backoff could not be saved.")
        until
      )
      (if (setq value (GitHub_UnixTime))
        (GitHub_Backoff (+ value 3600.0))
      )
    )
    result
  )
)

;; REST-only guard. Git refs and raw downloads do not use this quota.
;; The run flag has no credentials; authenticated deadlines are not persisted.
;; Inputs: url - GitHub URL; headers - request-header association list; token - token string or
;; nil.
;; Returns: paced HTTP response, or nil when deferred/failed.
(defun GitHub_RestGet (url headers token / now blocked response status fields remaining reset retry wait)
  (setq now (GitHub_UnixTime))
  (cond
    (*GitHub-RestBlocked* nil)
    ((null now) (prompt "\nGitHub error: could not determine UTC time for REST pacing.") nil)
    ((and (null token) (setq blocked (GitHub_Backoff nil)) (> blocked now))
      (setq *GitHub-RestBlocked* T)
      (prompt "\nGitHub warning: REST refresh deferred until the saved rate-limit reset.")
      nil
    )
    (t
      (setq response (GitHub_WebGet url headers))
      (if response
        (progn
          (setq status (cdr (assoc "status" response))
            fields (cdr (assoc "headers" response))
            remaining (cdr (assoc "x-ratelimit-remaining" fields))
          )
          (if (or (member status '(403 429)) (= remaining "0"))
            (progn
              (setq *GitHub-RestBlocked* T
                wait 60.0
                retry (cdr (assoc "retry-after" fields))
                reset (cdr (assoc "x-ratelimit-reset" fields))
              )
              (if retry
                (setq wait (max wait (atof retry)))
              )
              (if (= remaining "0")
                (setq wait (max wait (if reset
                      (- (atof reset) now)
                      3600.0
                    )
                  )
                )
              )
              (if (null token)
                (GitHub_Backoff (+ now wait))
              )
              (prompt "\nGitHub warning: further REST requests paused for this run.")
            )
          )
        )
      )
      response
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sync preview
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Disk state from the last installed size and modification time.
;; Inputs: root - cache file root; name - repository-relative filename; owned - previous owned-
;; file record or nil.
;; Returns: local state, path, size, and modification-time data.
(defun GitHub_LocalFileState (root name owned / filename size modified state parent blocked)
  (setq filename (strcat root "\\" (vl-string-translate "/" "\\" name))
    parent (vl-filename-directory filename)
  )
  (while (and parent (>= (strlen parent) (strlen root)) (not blocked))
    (if (and (not (vl-file-directory-p parent)) (vl-file-size parent))
      (setq blocked T)
    )
    (if (= (strcase parent) (strcase root))
      (setq parent nil)
      (setq parent (vl-filename-directory parent))
    )
  )
  (setq size (vl-file-size filename)
    modified (if size
      (vl-file-systime filename)
    )
    state
    (cond
      ((or blocked (vl-file-directory-p filename)) "blocked")
      ((null size) "missing")
      ((null owned) "untracked")
      ((or (/= size (cdr (assoc "size" owned))) (not (equal modified (cdr (assoc "modified" owned)))))
        "modified"
      )
      (t "clean")
    )
  )
  (list (cons "state" state) (cons "filename" filename)
    (cons "size" size) (cons "modified" modified)
  )
)

;; Builds actions without changing cached files or manifests.
;; Invalid Windows names, case collisions, and file/directory collisions fail closed.
;; Inputs: inventory - complete source inventory; manifest - manifest data; root - cache file
;; root.
;; Returns: download/keep/remove/conflict lists, or nil.
(defun GitHub_PlanFiles
  (inventory manifest root / result remote owned index oldIndex file name key parent
    old state disk downloads keeps removes forgets conflicts valid
    source kind target prefix commit
  )
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (setq remote (cdr (assoc "files" inventory))
          owned (cdr (assoc "files" manifest))
          valid T
          commit (cdr (assoc "commit" inventory))
          source (cdr (assoc "source" manifest))
          kind (cdr (assoc "type" source))
          target (GitHub_Join (cdr (assoc "path" source)) "/")
          prefix (if target
            (strcat target "/")
          )
        )
        (if (and
            (GitHub_IsManifest manifest)
            (assoc "files" inventory)
            (listp remote)
            (= (type commit) 'STR)
            (= (strlen commit) 40)
            (not (wcmatch (strcase commit) "*[~0-9A-F]*"))
          )
          (progn
            (foreach file owned
              (setq oldIndex (cons (cons (strcase (cdr (assoc "path" file))) file) oldIndex))
            )
            (foreach file remote
              (setq name (cdr (assoc "path" file)))
              (if (and
                  (GitHub_IsCachePath name)
                  (= (type (cdr (assoc "sha" file))) 'STR)
                  (= (strlen (cdr (assoc "sha" file))) 40)
                  (not (wcmatch (strcase (cdr (assoc "sha" file))) "*[~0-9A-F]*"))
                  (= (type (cdr (assoc "size" file))) 'INT)
                  (>= (cdr (assoc "size" file)) 0)
                  (member (cdr (assoc "mode" file)) '("100644" "100755"))
                  (cond
                    ((= kind "repository") T)
                    ((= kind "file") (= name target))
                    ((null target) T)
                    (t (= (substr name 1 (strlen prefix)) prefix))
                  )
                )
                (progn
                  (setq key (strcase name))
                  (if (assoc key index)
                    (setq valid nil)
                  )
                  (setq index (cons (cons key file) index))
                )
                (setq valid nil)
              )
            )
            (foreach file index
              (setq parent (vl-filename-directory (car file)))
              ;; AutoCAD returns "" (truthy), not nil, for a bare filename.
              (while (and parent (/= parent ""))
                (if (assoc (vl-string-translate "\\" "/" parent) index)
                  (setq valid nil)
                )
                (setq parent (vl-filename-directory parent))
              )
            )
            (if valid
              (progn
                (foreach file remote
                  (setq name (cdr (assoc "path" file))
                    key (strcase name)
                    old (cdr (assoc key oldIndex))
                    disk (GitHub_LocalFileState root name old)
                    state (cdr (assoc "state" disk))
                  )
                  (cond
                    ((member state '("blocked" "untracked" "modified"))
                      (setq conflicts (cons (list (cons "path" name) (cons "reason" state)) conflicts))
                    )
                    ((or
                        (= state "missing")
                        (not (equal (cdr (assoc "sha" file)) (cdr (assoc "sha" old))))
                        (not (equal (cdr (assoc "size" file)) (cdr (assoc "size" old))))
                        (not (equal (cdr (assoc "mode" file)) (cdr (assoc "mode" old))))
                      )
                      (setq downloads
                        (cons (append file (list (cons "reason"
                                (if (= state "missing")
                                  (if old
                                    "missing"
                                    "new"
                                  )
                                  "changed"
                                )
                              )
                            )
                          ) downloads
                        )
                      )
                    )
                    (t (setq keeps (cons file keeps)))
                  )
                )
                (foreach file owned
                  (setq name (cdr (assoc "path" file)))
                  (if (null (assoc (strcase name) index))
                    (progn
                      (setq disk (GitHub_LocalFileState root name file) state (cdr (assoc "state" disk)))
                      (cond
                        ((= state "missing") (setq forgets (cons file forgets)))
                        ((= state "clean") (setq removes (cons file removes)))
                        (t
                          (setq conflicts (cons (list (cons "path" name) (cons "reason" (strcat "removed-" state))) conflicts)
                          )
                        )
                      )
                    )
                  )
                )
                (list (cons "download" (reverse downloads)) (cons "keep" (reverse keeps))
                  (cons "remove" (reverse removes)) (cons "forget" (reverse forgets))
                  (cons "conflicts" (reverse conflicts))
                )
              )
            )
          )
        )
      )
    )
  )
  (cond
    ((vl-catch-all-error-p result)
      (prompt (strcat "\nGitHub error: file planning failed: " (vl-catch-all-error-message result)))
      nil
    )
    ((null result)
      (prompt "\nGitHub error: inventory contains invalid or conflicting Windows paths.")
      nil
    )
    (t result)
  )
)

;; Interval/cache lookup, ref resolution, complete inventory, and disk plan.
;; Refresh failures can reuse an installed manifest, never a partial inventory.
;; Inputs: url - GitHub URL; token - token string or nil; force - T to bypass the check
;; interval.
;; Returns: complete sync plan, or nil.
(defun GitHub_PreviewPlan
  (url token force / result data auth cache manifest refs resolved fresh source inventory
    check actions fallback
  )
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (cond
          ((not (and (GitHub_IsValidGitHubURL url) (setq data (GitHub_ParseGitHubURL url))))
            (prompt "\nGitHub error: a repository, folder, or file URL is required.")
            nil
          )
          ((and token (null (setq auth (GitHub_AuthHeaders token "api")))) nil)
          (t
            (setq cache (GitHub_FindCachedSource data)
              manifest (cdr (assoc "manifest" cache))
              fallback (if (cdr (assoc "commit" manifest))
                cache
              )
            )
            (cond
              ((and cache (not force) (not (GitHub_ShouldCheck manifest))) (setq check "interval"))
              (t
                (setq refs (GitHub_GetRefs data token))
                (if refs
                  (setq resolved (GitHub_ResolveRef data refs))
                )
                (if resolved
                  (progn
                    (setq fresh (GitHub_NewManifest data resolved)
                      source (cdr (assoc "source" fresh))
                      cache (GitHub_SourceCache source)
                      manifest (cdr (assoc "manifest" cache))
                    )
                    (if (null manifest)
                      (setq manifest fresh)
                    )
                    (if cache
                      (if (equal (cdr (assoc "commit" resolved)) (cdr (assoc "commit" manifest)))
                        (setq check "unchanged")
                        (if (setq inventory (GitHub_GetTree data (cdr (assoc "commit" resolved)) token))
                          (setq inventory (GitHub_FilterTree data resolved inventory) check "updated")
                        )
                      )
                    )
                  )
                )
              )
            )
            (if (and (null inventory) (not (member check '("interval" "unchanged"))))
              (if fallback
                (progn
                  (setq cache fallback manifest (cdr (assoc "manifest" cache)) check "refresh-failed")
                  (prompt "\nGitHub warning: refresh unavailable; using the previous cached inventory.")
                )
                (setq cache nil)
              )
            )
            (if cache
              (progn
                (if (null inventory)
                  (setq inventory (list (assoc "commit" manifest) (assoc "files" manifest)))
                )
                (if (setq actions (GitHub_PlanFiles inventory manifest (cdr (assoc "files-root" cache))))
                  (append
                    (list
                      (cons "status"
                        (cond
                          ((cdr (assoc "conflicts" actions)) "conflicts")
                          ((cdr (assoc "recovery" cache)) "recovery")
                          ((= check "refresh-failed") "cached")
                          (t "ready")
                        )
                      )
                      (cons "check" check) (cons "cache" cache)
                      (cons "manifest" manifest) (cons "inventory" inventory)
                    )
                    actions
                  )
                )
              )
            )
          )
        )
      )
    )
  )
  (if (vl-catch-all-error-p result)
    (progn
      (prompt "\nGitHub error: preview could not be completed.")
      nil
    )
    result
  )
)

;; Public one-URL preview. Returns counts; leaves cached files and manifests alone.
;; The explicit token is never included in the plan or summary.
(defun GitHub_Preview (url token / plan cache)
  (setq *GitHub-RestBlocked* nil)
  (if (setq plan (GitHub_PreviewPlan url token nil))
    (progn
      (setq cache (cdr (assoc "cache" plan)))
      (list
        (assoc "status" plan) (assoc "check" plan)
        (assoc "commit" (cdr (assoc "inventory" plan)))
        (cons "cache" (cdr (assoc "directory" cache)))
        (cons "download" (length (cdr (assoc "download" plan))))
        (cons "keep" (length (cdr (assoc "keep" plan))))
        (cons "remove" (length (cdr (assoc "remove" plan))))
        (cons "conflicts" (length (cdr (assoc "conflicts" plan))))
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Byte-safe downloads and cache filesystem guards
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Converts a path to UTF-8 URL bytes; slashes stay as path separators.
;; Inputs: text - repository-relative path text.
;; Returns: UTF-8 escaped path, or nil.
(defun GitHub_EncodeURLPath (text / stream result bytes n safe encoded)
  (if (= text "")
    ""
    (progn
      (setq stream (vl-catch-all-apply 'vlax-create-object '("ADODB.Stream")))
      (if (and stream (not (vl-catch-all-error-p stream)))
        (progn
          (setq result
            (vl-catch-all-apply
              '(lambda ()
                (vlax-put-property stream 'Type 2)
                (vlax-put-property stream 'Charset "utf-8")
                ;; ADO Open needs the optional-argument-aware invocation.
                (vlax-invoke stream 'Open)
                (vlax-invoke-method stream 'WriteText text 0)
                (vlax-put-property stream 'Position 0)
                (vlax-put-property stream 'Type 1)
                (vlax-put-property stream 'Position 3)
                (setq bytes (vlax-invoke-method stream 'Read -1)
                  safe (vl-string->list "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
                  encoded ""
                )
                (if (= (type bytes) 'VARIANT)
                  (setq bytes (vlax-variant-value bytes))
                )
                (foreach n (vlax-safearray->list bytes)
                  (setq encoded
                    (strcat encoded
                      (if (member n safe)
                        (chr n)
                        (strcat "%"
                          (substr "0123456789ABCDEF" (1+ (fix (/ n 16))) 1)
                          (substr "0123456789ABCDEF" (1+ (rem n 16)) 1)
                        )
                      )
                    )
                  )
                )
                encoded
              )
            )
          )
          (vl-catch-all-apply 'vlax-invoke-method (list stream 'Close))
          (vlax-release-object stream)
          (if (vl-catch-all-error-p result)
            (progn
              (prompt (strcat "\nGitHub error: URL encoding failed: " (vl-catch-all-error-message result)))
              nil
            )
            result
          )
        )
      )
    )
  )
)

;; Creates a new binary file; never overwrites an existing destination.
;; Verifies both stream size and saved file size against the remote inventory.
;; Inputs: filename - full file path; bytes - byte data; expected - expected byte count.
;; Returns: T after size-verified creation, or nil.
(defun GitHub_WriteBytes (filename bytes expected / stream result created data count)
  (if (and
      (= (type expected) 'INT)
      (>= expected 0)
      (not (vl-file-directory-p filename))
      (null (vl-file-size filename))
    )
    (progn
      (setq stream (vl-catch-all-apply 'vlax-create-object '("ADODB.Stream")))
      (if (and stream (not (vl-catch-all-error-p stream)))
        (progn
          (setq result
            (vl-catch-all-apply
              '(lambda ()
                (setq data (if (= (type bytes) 'VARIANT)
                    (vlax-variant-value bytes)
                    bytes
                  )
                  ;; Empty HTTP byte arrays unwrap to nil in Visual LISP.
                  ;; The expected size must still match before saving.
                  count (if (null data)
                    0
                    (1+ (- (vlax-safearray-get-u-bound data 1) (vlax-safearray-get-l-bound data 1)))
                  )
                )
                (vlax-put-property stream 'Type 1)
                (vlax-invoke stream 'Open)
                (if (> count 0)
                  (vlax-invoke-method stream 'Write bytes)
                )
                (if (and (= count expected) (= (vlax-get-property stream 'Size) expected))
                  (progn
                    (vlax-invoke-method stream 'SaveToFile filename 1)
                    (setq created T)
                    (= (vl-file-size filename) expected)
                  )
                )
              )
            )
          )
          (vl-catch-all-apply 'vlax-invoke-method (list stream 'Close))
          (vlax-release-object stream)
          (if (and (not (vl-catch-all-error-p result)) result)
            T
            (progn
              (if (vl-catch-all-error-p result)
                (prompt (strcat "\nGitHub error: binary stream failed: " (vl-catch-all-error-message result)))
              )
              (if created
                (vl-catch-all-apply 'vl-file-delete (list filename))
              )
              nil
            )
          )
        )
      )
    )
  )
)

;; Uses a commit-pinned raw URL. The token remains an argument/local header only.
;; Inputs: source - canonical source identity; commit - 40-character commit SHA; file - remote
;; file record; filename - full file path; token - token string or nil.
;; Returns: T after a verified commit-pinned download, or nil.
(defun GitHub_DownloadFile (source commit file filename token / headers path response)
  (cond
    ((and token (null (setq headers (GitHub_AuthHeaders token "raw")))) nil)
    ((null (setq path (GitHub_EncodeURLPath (cdr (assoc "path" file)))))
      (prompt "\nGitHub error: could not encode a download path.")
      nil
    )
    ((null
        (setq response
          (GitHub_WebGet
            (strcat "https://raw.githubusercontent.com/"
              (cdr (assoc "owner" source)) "/" (cdr (assoc "repo" source))
              "/" commit "/" path
            )
            headers
          )
        )
      )
      (prompt "\nGitHub error: download request failed.")
      nil
    )
    ((/= (cdr (assoc "status" response)) 200)
      (prompt (strcat "\nGitHub error: download returned HTTP " (itoa (cdr (assoc "status" response))) ".")
      )
      nil
    )
    ((GitHub_WriteBytes filename (cdr (assoc "bytes" response)) (cdr (assoc "size" file))) T)
    (t (prompt "\nGitHub error: downloaded file could not be saved and verified.") nil)
  )
)

;; Resolves a relative path under root and rejects reparse points in its ancestry.
;; No file changes. Long paths fail before staging rather than during replacement.
;; Returns: absolute path without reparse-point ancestry, or nil.
(defun GitHub_SafeFile (root relative / fso object result absolute prefix current kind valid)
  (if (GitHub_IsCachePath relative)
    (progn
      (setq fso (vl-catch-all-apply 'vlax-create-object '("Scripting.FileSystemObject")))
      (if (and fso (not (vl-catch-all-error-p fso)))
        (progn
          (setq result
            (vl-catch-all-apply
              '(lambda ()
                (setq prefix
                  (strcat (vl-string-right-trim "\\" (vlax-invoke-method fso 'GetAbsolutePathName root)) "\\")
                  absolute (vlax-invoke-method fso 'GetAbsolutePathName
                    (strcat prefix (vl-string-translate "/" "\\" relative))
                  )
                  current absolute
                  valid T
                )
                (if (and
                    (< (strlen absolute) 260)
                    (= (strcase (substr absolute 1 (strlen prefix))) (strcase prefix))
                  )
                  (progn
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
                          (if (and (= kind 'GetFile) (/= (strcase current) (strcase absolute)))
                            (setq valid nil)
                          )
                          (vlax-release-object object)
                          (setq object nil)
                        )
                      )
                      (setq current (vlax-invoke-method fso 'GetParentFolderName current))
                    )
                    (if valid
                      absolute
                    )
                  )
                )
              )
            )
          )
          (if object
            (vlax-release-object object)
          )
          (vlax-release-object fso)
          (if (not (vl-catch-all-error-p result))
            result
          )
        )
      )
    )
  )
)

;; Removes only an empty directory inside the managed sources tree.
;; Returns: T if absent or removed empty; otherwise nil.
(defun GitHub_RemoveEmptyDirectory (directory / prefix relative safe fso folder files folders result)
  (setq prefix (strcat (vl-string-right-trim "\\/" *GitHub-Root*) "\\"))
  (if (= (strcase (substr directory 1 (strlen prefix))) (strcase prefix))
    (progn
      (setq relative (vl-string-translate "\\" "/" (substr directory (1+ (strlen prefix)))))
      (if (and
          (wcmatch (strcase relative) "SOURCES/*")
          (setq safe (GitHub_SafeFile *GitHub-Root* relative))
        )
        (progn
          (setq fso (vl-catch-all-apply 'vlax-create-object '("Scripting.FileSystemObject")))
          (if (and fso (not (vl-catch-all-error-p fso)))
            (progn
              (setq result
                (vl-catch-all-apply
                  '(lambda ()
                    (cond
                      ((not (vl-file-directory-p safe)) (null (vl-file-size safe)))
                      (t
                        (setq folder (vlax-invoke-method fso 'GetFolder safe)
                          files (vlax-get-property folder 'Files)
                          folders (vlax-get-property folder 'SubFolders)
                        )
                        (if (and (= (vlax-get-property files 'Count) 0) (= (vlax-get-property folders 'Count) 0))
                          (progn
                            (vlax-release-object files)
                            (setq files nil)
                            (vlax-release-object folders)
                            (setq folders nil)
                            (vlax-release-object folder)
                            (setq folder nil)
                            (vlax-invoke-method fso 'DeleteFolder safe :vlax-false)
                            T
                          )
                        )
                      )
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
          )
        )
      )
    )
  )
)

;; Records installed/staged size and mtime; paths stay repository-relative.
;; Inputs: file - remote file record; filename - full file path.
;; Returns: installed size/time/identity record, or nil.
(defun GitHub_RecordFile (file filename / size modified)
  (setq size (vl-file-size filename) modified (vl-file-systime filename))
  (if (and
      (not (vl-file-directory-p filename))
      (numberp size)
      (= size (cdr (assoc "size" file)))
      modified
    )
    (list (assoc "path" file) (assoc "sha" file) (assoc "size" file)
      (assoc "mode" file) (cons "modified" modified)
    )
  )
)

;; Inputs: filename - full file path; record - installed file record.
;; Returns: T if size/time match the record; otherwise nil.
(defun GitHub_FileMatches (filename record)
  (and
    (not (vl-file-directory-p filename))
    (equal (vl-file-size filename) (cdr (assoc "size" record)))
    (equal (vl-file-systime filename) (cdr (assoc "modified" record)))
  )
)

;; Deletes only recorded transaction files whose size/mtime still match.
;; Empty parents are removed individually; unknown content is retained.
;; Inputs: directory - full directory path; known - recorded transaction files; paths -
;; transaction paths.
;; Returns: cleanup result; retained recovery files are reported.
(defun GitHub_CleanupWork (directory known paths / prefix item filename relative parent safe)
  (setq prefix (strcat directory "\\"))
  (foreach item known
    (setq filename (car item))
    (if (= (strcase (substr filename 1 (strlen prefix))) (strcase prefix))
      (progn
        (setq relative (vl-string-translate "\\" "/" (substr filename (1+ (strlen prefix))))
          safe (GitHub_SafeFile directory relative)
        )
        (if (and safe (GitHub_FileMatches safe (cdr item)))
          (vl-catch-all-apply 'vl-file-delete (list safe))
        )
      )
    )
  )
  (foreach filename (append paths (mapcar 'car known))
    (setq parent (vl-filename-directory filename))
    (while (and
        parent
        (/= parent "")
        (or
          (= (strcase parent) (strcase directory))
          (= (strcase (substr parent 1 (strlen prefix))) (strcase prefix))
        )
      )
      (GitHub_RemoveEmptyDirectory parent)
      (if (= (strcase parent) (strcase directory))
        (setq parent nil)
        (setq parent (vl-filename-directory parent))
      )
    )
  )
  (GitHub_RemoveEmptyDirectory directory)
  (not (vl-file-directory-p directory))
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Applying a sync plan
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Inputs: a - first action plan; b - second action plan.
;; Returns: T when both plans describe the same file actions; otherwise nil.
(defun GitHub_SameActions (a b)
  (vl-every '(lambda (key)
      (equal (cdr (assoc key a)) (cdr (assoc key b)))
    )
    '("download" "keep" "remove" "forget" "conflicts")
  )
)

;; Builds the installed manifest from verified staged files and unchanged files.
;; Inputs: manifest - manifest data; inventory - complete source inventory; root - cache file
;; root; staged - staged-file path map; check - refresh/check result.
;; Returns: proposed installed manifest, or nil.
(defun GitHub_InstalledManifest
  (manifest inventory root staged check / file path filename record records valid data)
  (setq valid T)
  (foreach file (cdr (assoc "files" inventory))
    (setq path (cdr (assoc "path" file)) filename (cdr (assoc (strcase path) staged)))
    (if (null filename)
      (setq filename (GitHub_SafeFile root path))
    )
    (setq record (if filename
        (GitHub_RecordFile file filename)
      )
    )
    (if record
      (setq records (cons record records))
      (setq valid nil)
    )
  )
  (setq data
    (subst (cons "commit" (cdr (assoc "commit" inventory))) (assoc "commit" manifest)
      (subst (cons "files" (reverse records)) (assoc "files" manifest) manifest)
    )
  )
  (if (member check '("updated" "unchanged"))
    (setq data (subst (cons "checked-at" (getvar "DATE")) (assoc "checked-at" data) data))
  )
  (if (and valid (GitHub_IsManifest data))
    data
  )
)

;; Validates the plan again under a source lock before touching installed files.
;; Transaction copies survive a failed rollback for manual recovery.
;; Inputs: plan - validated sync plan; token - token string or nil.
;; Returns: sync status/count summary, including failure/recovery status.
(defun GitHub_ApplyPlan
  (plan token / result cache directory root filename before inventory after check status reason
    parent lock locked work slot pending source commit downloads removals todo file name
    staged stagedFile stageMap oldIndex old disk state original backup target record
    known paths installed moved actions committed rollbackComplete cleanup item safe
    remember rollback summary
  )
  (setq cache (cdr (assoc "cache" plan))
    directory (cdr (assoc "directory" cache))
    root (cdr (assoc "files-root" cache))
    filename (cdr (assoc "manifest-file" cache))
    before (cdr (assoc "manifest" plan))
    inventory (cdr (assoc "inventory" plan))
    check (cdr (assoc "check" plan))
    downloads (cdr (assoc "download" plan))
    removals (cdr (assoc "remove" plan))
    source (cdr (assoc "source" before))
    commit (cdr (assoc "commit" inventory))
    status (cdr (assoc "status" plan))
    lock (strcat directory "\\sync.lock")
    rollbackComplete T
  )
  ;; filePath - transaction file to track. Returns the updated cleanup record list.
  (defun remember (filePath / size modified)
    (setq size (vl-file-size filePath) modified (vl-file-systime filePath))
    (if (and size modified)
      (setq known (cons (cons filePath (list (cons "size" size) (cons "modified" modified))) known))
    )
  )
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (cond
          ((= status "conflicts") (setq reason "local conflicts must be resolved before syncing.") nil)
          ((or
              (= status "recovery")
              (vl-file-size (strcat filename ".bak"))
              (vl-file-directory-p (strcat filename ".bak"))
            )
            (setq status "recovery" reason "a manifest backup requires recovery.")
            nil
          )
          ((null (setq safe (GitHub_SafeFile *GitHub-Root* (strcat "sources/" (vl-filename-base directory))))
            )
            (setq reason "cache path is unsafe or too long.")
            nil
          )
          ((/= (strcase safe) (strcase directory))
            (setq reason "cache directory does not match its source slot.")
            nil
          )
          ((not (GitHub_Mkdir (vl-filename-directory directory)))
            (setq reason "could not create the sources directory.")
            nil
          )
          ((if (vl-file-directory-p directory)
              (not (GitHub_ManifestEqual before (GitHub_ReadManifest filename)))
              (not (vl-mkdir directory))
            )
            (setq reason "cache ownership changed; retry the sync.")
            nil
          )
          ((not (setq locked (vl-mkdir lock)))
            (setq status "busy" reason (strcat "another sync or a stale lock exists at " lock))
            nil
          )
          ((setq pending (vl-directory-files directory "txn-*" -1))
            (setq status "recovery"
              reason (strcat "unfinished transaction requires recovery at " directory "\\" (car pending))
            )
            nil
          )
          (t
            ;; A new cache claims only its source identity, with no owned files.
            (if (null (vl-file-size filename))
              (if (not (GitHub_WriteManifest filename before))
                (setq reason "could not claim the source cache.")
              )
            )
            (if (null reason)
              (progn
                (setq actions (GitHub_PlanFiles inventory before root))
                (if (or (null actions) (not (GitHub_SameActions plan actions)))
                  (setq reason "cache changed after planning; retry the sync.")
                )
              )
            )
            (if (and (null reason) (not (GitHub_Mkdir root)))
              (setq reason "could not create the file cache.")
            )
            (if (and (null reason) (or downloads removals))
              (progn
                (setq slot 0)
                (while (and (null work) (< slot 1000))
                  (setq parent (strcat directory "\\txn-" (itoa (getvar "MILLISECS")) "-" (itoa slot)))
                  (if (vl-mkdir parent)
                    (setq work parent)
                  )
                  (setq slot (1+ slot))
                )
                (if (null work)
                  (setq reason "could not create a staging transaction.")
                  (progn
                    (setq paths (list (strcat work "\\before.dat") (strcat work "\\after.dat")))
                    (if (GitHub_WriteManifest (strcat work "\\before.dat") before)
                      (remember (strcat work "\\before.dat"))
                      (setq reason "could not save the recovery manifest.")
                    )
                    (if downloads
                      (prompt (strcat "\nGitHub: staging " (itoa (length downloads)) " file(s)..."))
                    )
                    (setq todo downloads)
                    (while (and todo (null reason))
                      (setq file (car todo)
                        name (cdr (assoc "path" file))
                        stagedFile (GitHub_SafeFile work (strcat "new/" name))
                      )
                      (if stagedFile
                        (setq paths (cons stagedFile paths))
                      )
                      (if (and
                          stagedFile
                          (GitHub_Mkdir (vl-filename-directory stagedFile))
                          (GitHub_SafeFile work (strcat "new/" name))
                          (GitHub_DownloadFile source commit file stagedFile token)
                        )
                        (progn
                          (setq stageMap (cons (cons (strcase name) stagedFile) stageMap))
                          (remember stagedFile)
                        )
                        (setq reason "downloads did not finish; installed files were preserved.")
                      )
                      (setq todo (cdr todo))
                    )
                  )
                )
              )
            )
            (if (null reason)
              (progn
                (setq actions (GitHub_PlanFiles inventory before root))
                (if (or
                    (null actions)
                    (not (GitHub_SameActions plan actions))
                    (not (GitHub_ManifestEqual before (GitHub_ReadManifest filename)))
                  )
                  (setq reason "cache changed during staging; installed files were preserved.")
                )
              )
            )
            (if (null reason)
              (if (setq after (GitHub_InstalledManifest before inventory root stageMap check))
                (if work
                  (if (GitHub_WriteManifest (strcat work "\\after.dat") after)
                    (remember (strcat work "\\after.dat"))
                    (setq reason "could not save the proposed manifest.")
                  )
                )
                (setq reason "staged files failed inventory verification.")
              )
            )
            (if (null reason)
              (progn
                (foreach file (cdr (assoc "files" before))
                  (setq oldIndex (cons (cons (strcase (cdr (assoc "path" file))) file) oldIndex))
                )
                (setq todo (append downloads removals))
                (while (and todo (null reason))
                  (setq file (car todo)
                    name (cdr (assoc "path" file))
                    old (cdr (assoc (strcase name) oldIndex))
                    target (GitHub_SafeFile root name)
                    disk (if target
                      (GitHub_LocalFileState root name old)
                    )
                    state (cdr (assoc "state" disk))
                  )
                  (cond
                    ((or (null target) (not (member state '("clean" "missing"))))
                      (setq reason "a local file changed before replacement.")
                    )
                    ((and (member file removals) (/= state "clean"))
                      (setq reason "a removal target changed before cleanup.")
                    )
                    (t
                      (if (= state "clean")
                        (progn
                          (setq original (GitHub_SafeFile root (cdr (assoc "path" old)))
                            backup (GitHub_SafeFile work (strcat "backup/" name))
                          )
                          (if backup
                            (setq paths (cons backup paths))
                          )
                          (if (and
                              original
                              backup
                              (GitHub_Mkdir (vl-filename-directory backup))
                              (GitHub_SafeFile work (strcat "backup/" name))
                              (vl-file-rename original backup)
                            )
                            (progn
                              (setq moved (cons (list original backup old) moved) known (cons (cons backup old) known))
                            )
                            (setq reason "could not preserve an owned file for rollback.")
                          )
                        )
                      )
                      (if (and (null reason) (setq stagedFile (cdr (assoc (strcase name) stageMap))))
                        (if (and
                            (GitHub_Mkdir (vl-filename-directory target))
                            (GitHub_SafeFile root name)
                            (vl-file-rename stagedFile target)
                          )
                          (progn
                            (setq record (cdr (assoc (strcase name)
                                  (mapcar '(lambda (entry)
                                      (cons (strcase (cdr (assoc "path" entry))) entry)
                                    )
                                    (cdr (assoc "files" after))
                                  )
                                )
                              )
                            )
                            (setq installed (cons (cons target record) installed))
                          )
                          (setq reason "could not install a staged file.")
                        )
                      )
                    )
                  )
                  (setq todo (cdr todo))
                )
              )
            )
            (if (null reason)
              (if (not
                  (vl-every
                    '(lambda (entry / path)
                      (and
                        (setq path (GitHub_SafeFile root (cdr (assoc "path" entry))))
                        (GitHub_FileMatches path entry)
                      )
                    )
                    (cdr (assoc "files" after))
                  )
                )
                (setq reason "installed files changed before manifest commit.")
              )
            )
            (if (null reason)
              (if (or (GitHub_ManifestEqual before after) (GitHub_WriteManifest filename after))
                (setq committed T)
                (setq reason "manifest commit failed.")
              )
            )
            committed
          )
        )
      )
    )
  )
  ;; Restore new/replaced files first, then their preserved originals.
  (if (and (not committed) (or installed moved))
    (progn
      (foreach item installed
        (setq target (car item) name (cdr (assoc "path" (cdr item))))
        (if (not
            (and (GitHub_SafeFile root name) (GitHub_FileMatches target (cdr item)) (vl-file-delete target))
          )
          (setq rollbackComplete nil)
        )
      )
      (foreach item moved
        (setq original (car item) backup (cadr item) record (caddr item))
        (if (not
            (and
              (GitHub_SafeFile root (cdr (assoc "path" record)))
              (GitHub_FileMatches backup record)
              (null (vl-file-size original))
              (not (vl-file-directory-p original))
              (vl-file-rename backup original)
            )
          )
          (setq rollbackComplete nil)
        )
      )
    )
  )
  (if (and (not committed) locked (not (GitHub_ManifestEqual before (GitHub_ReadManifest filename))))
    (if (and
        (null (vl-file-size filename))
        (GitHub_ManifestEqual before (GitHub_ReadManifest (strcat filename ".bak")))
      )
      (if (not (vl-file-rename (strcat filename ".bak") filename))
        (setq rollbackComplete nil)
      )
      (setq rollbackComplete nil)
    )
  )
  (if (and work (or committed rollbackComplete))
    (setq cleanup (vl-catch-all-apply 'GitHub_CleanupWork (list work known paths)))
  )
  (if (and work (vl-file-directory-p work))
    (prompt (strcat "\nGitHub warning: transaction retained at " work))
  )
  (if locked
    (if (not (GitHub_RemoveEmptyDirectory lock))
      (prompt (strcat "\nGitHub warning: sync lock retained at " lock))
    )
  )
  (cond
    (committed
      (setq status
        (cond
          ((= check "refresh-failed") "cached")
          ((or downloads removals) "synced")
          (t "up-to-date")
        )
      )
    )
    ((not rollbackComplete) (setq status "recovery"))
    ((not (member status '("conflicts" "busy" "recovery"))) (setq status "failed"))
  )
  (if (not committed)
    (prompt
      (strcat "\nGitHub error: "
        (cond
          (reason reason)
          ((vl-catch-all-error-p result) "sync operation failed; recovery data was preserved.")
          (t "sync did not complete.")
        )
      )
    )
  )
  (list (cons "status" status) (cons "check" check)
    (cons "commit" (cdr (assoc "commit" (if committed
            after
            before
          )
        )
      )
    )
    (cons "cache" directory)
    (cons "download" (if committed
        (length downloads)
        0
      )
    )
    (cons "keep" (length (cdr (assoc "keep" plan))))
    (cons "remove" (if committed
        (length removals)
        0
      )
    )
    (cons "conflicts" (length (cdr (assoc "conflicts" plan))))
  )
)

;; Syncs one URL into its isolated cache. Does not execute downloaded code.
;; Inputs: url - GitHub URL; token - token string or nil.
;; Returns: sync status/count summary, or nil.
(defun GitHub_Sync (url token / plan)
  (setq *GitHub-RestBlocked* nil)
  (if (setq plan (GitHub_PreviewPlan url token nil))
    (GitHub_ApplyPlan plan token)
  )
)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Cached AutoLISP loading
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Selects .vlx/.fas/.lsp records in path order, including subfolders.
;; A file source loads its exact file; other sources prefer VLX > FAS > LSP
;; when several formats share a repository-relative basename.
;; Inputs: manifest - manifest data.
;; Returns: ordered loadable file records.
(defun GitHub_SelectLoadFiles (manifest / files index entry name ext key prior rank)
  (if (GitHub_IsManifest manifest)
    (progn
      (setq files (cdr (assoc "files" manifest)))
      (foreach entry files
        (setq name (cdr (assoc "path" entry))
          ext (strcase (cond
              ((vl-filename-extension name))
              ("")
            )
          )
          rank (length (member ext '(".VLX" ".FAS" ".LSP")))
        )
        (if (> rank 0)
          (progn
            (setq key (strcase (substr name 1 (- (strlen name) (strlen ext)))) prior (assoc key index))
            (if (or
                (null prior)
                (> rank (length (member
                      (strcase (vl-filename-extension (cdr (assoc "path" (cdr prior)))))
                      '(".VLX" ".FAS" ".LSP")
                    )
                  )
                )
              )
              (if prior
                (setq index (subst (cons key entry) prior index))
                (setq index (cons (cons key entry) index))
              )
            )
          )
        )
      )
      (vl-sort (mapcar 'cdr index)
        '(lambda (a b)
          (< (strcase (cdr (assoc "path" a))) (strcase (cdr (assoc "path" b))))
        )
      )
    )
  )
)

;; Loads selected entries from GitHub_CacheInfo output; makes no requests.
;; Checks all entries before executing any, then checks each again before load.
;; Returns status, commit, cache, loaded paths, failed path, and per-file values.
;; A nil final value is still success. Runtime errors can leave earlier files loaded.
(defun GitHub_LoadCache
  (cache / result directory root manifest entries todo entry name filename safe
    loaded values value reason failed empty
  )
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (setq directory (cdr (assoc "directory" cache)))
        (cond
          ((not (and
                directory
                (setq safe (GitHub_SafeFile *GitHub-Root* (strcat "sources/" (vl-filename-base directory))))
                (= (strcase safe) (strcase directory))
              )
            )
            (setq reason "cache path is unsafe.")
          )
          ((or
              (vl-file-size (strcat directory "\\manifest.dat.bak"))
              (vl-file-directory-p (strcat directory "\\manifest.dat.bak"))
              (vl-file-size (strcat directory "\\sync.lock"))
              (vl-file-directory-p (strcat directory "\\sync.lock"))
              (vl-directory-files directory "txn-*" -1)
            )
            (setq reason "cache is busy or requires recovery.")
          )
          ((not (and
                (setq manifest (GitHub_ReadManifest (strcat directory "\\manifest.dat")))
                (cdr (assoc "commit" manifest))
                (GitHub_ManifestEqual manifest (cdr (assoc "manifest" cache)))
              )
            )
            (setq reason "installed manifest is missing or changed.")
          )
          (t
            (setq root (strcat directory "\\files") entries (GitHub_SelectLoadFiles manifest))
            (cond
              ((null entries) (setq empty T))
              ((not (vl-every
                    '(lambda (record / path)
                      (and
                        (setq path (GitHub_SafeFile root (cdr (assoc "path" record))))
                        (GitHub_FileMatches path record)
                      )
                    )
                    entries
                  )
                )
                (setq reason "an entry file is missing, modified, or unsafe.")
              )
              (t
                (setq todo entries)
                (while (and todo (null reason))
                  (setq entry (car todo)
                    name (cdr (assoc "path" entry))
                    failed name
                    filename (GitHub_SafeFile root name)
                  )
                  (if (and
                      filename
                      (GitHub_FileMatches filename entry)
                      (not (vl-file-directory-p (strcat directory "\\sync.lock")))
                      (null (vl-file-size (strcat directory "\\manifest.dat.bak")))
                      (null (vl-directory-files directory "txn-*" -1))
                      (GitHub_ManifestEqual manifest (GitHub_ReadManifest (strcat directory "\\manifest.dat")))
                    )
                    (progn
                      ;; Exact extensions avoid search-path or format substitution.
                      ;; AutoCAD handles its normal SECURELOAD/TRUSTEDPATHS checks.
                      (setq value (load filename)
                        loaded (cons filename loaded)
                        values (cons (cons name value) values)
                        failed nil
                      )
                    )
                    (setq reason "cache changed before loading the next entry.")
                  )
                  (setq todo (cdr todo))
                )
              )
            )
          )
        )
      )
    )
  )
  (cond
    (empty (prompt "\nGitHub: no loadable AutoLISP files in this source."))
    ((or reason (vl-catch-all-error-p result))
      (prompt (strcat "\nGitHub error: "
          (cond
            (reason reason)
            (t
              (strcat "could not load " (if failed
                  failed
                  "the selected source"
                )
                ": " (vl-catch-all-error-message result)
              )
            )
          )
        )
      )
    )
  )
  (list (cons "status"
      (cond
        (empty "no-entry-files")
        ((or reason (vl-catch-all-error-p result))
          (if loaded
            "partial"
            "load-failed"
          )
        )
        (t "loaded")
      )
    )
    (cons "commit" (cdr (assoc "commit" manifest))) (cons "cache" directory)
    (cons "loaded" (reverse loaded)) (cons "failed" failed)
    (cons "values" (reverse values))
  )
)

;; Syncs one repository/folder/file URL, then loads its AutoLISP entries.
;; token - token string or nil. Returns a load summary plus sync-status.
;; Failed refreshes may use an intact installed copy. No trust settings are changed.
(defun GitHub_Load (url token / data name sync cache summary)
  (cond
    ((not (and (GitHub_IsValidGitHubURL url) (setq data (GitHub_ParseGitHubURL url))))
      (prompt "\nGitHub error: a repository, folder, or file URL is required.")
      nil
    )
    ((and
        (= (cdr (assoc "type" data)) "file")
        (not (and
            (setq name (GitHub_Join (cdr (assoc "path" data)) "/"))
            (member (strcase (cond
                  ((vl-filename-extension name))
                  ("")
                )
              )
              '(".LSP" ".FAS" ".VLX")
            )
          )
        )
      )
      (prompt "\nGitHub error: the file URL must name a .lsp, .fas, or .vlx file.")
      nil
    )
    ((and token (null (GitHub_AuthHeaders token "api"))) nil)
    (t
      (setq sync (vl-catch-all-apply 'GitHub_Sync (list url token)))
      ;; Do not retain the credential in the caller's scope while executing files.
      (setq token nil)
      (if (vl-catch-all-error-p sync)
        (setq sync nil)
      )
      (cond
        ((member (cdr (assoc "status" sync)) '("busy" "recovery"))
          (prompt "\nGitHub error: loading deferred while the cache is busy or requires recovery.")
          (list (cons "status" "load-failed") (cons "sync-status" (cdr (assoc "status" sync))))
        )
        ((setq cache (GitHub_FindCachedSource data))
          (if (not (member (cdr (assoc "status" sync)) '("synced" "up-to-date" "cached")))
            (prompt "\nGitHub warning: attempting to load the previous cached copy.")
          )
          (setq summary (GitHub_LoadCache cache))
          (append summary (list (cons "sync-status" (cdr (assoc "status" sync)))))
        )
        (t
          (prompt "\nGitHub error: no installed cache is available for this source.")
          (list (cons "status" "load-failed") (cons "sync-status" (cdr (assoc "status" sync))))
        )
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Deferred command loading
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Validates and deduplicates command names before defining any stubs.
;; Names omit the C: prefix and use letters, digits, underscores, or hyphens.
;; Inputs: commands - command names without C:.
;; Returns: normalized unique names, or nil for invalid input.
(defun GitHub_CommandNames (commands / result names name)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
        (if (and
            commands
            (listp commands)
            (vl-every
              '(lambda (item)
                (and
                  (= (type item) 'STR)
                  (<= 1 (strlen item) 255)
                  (not (wcmatch (strcase item) "*[~A-Z0-9_-]*"))
                )
              )
              commands
            )
          )
          (progn
            (foreach name commands
              (setq name (strcase name))
              (if (not (member name names))
                (setq names (cons name names))
              )
            )
            (reverse names)
          )
        )
      )
    )
  )
  (if (and result (not (vl-catch-all-error-p result)))
    result
    (progn
      (prompt "\nGitHub error: supply a nonempty list of command names without C: prefixes.")
      nil
    )
  )
)

;; Runs from a generated C: stub. Loads only the installed file; never syncs.
;; Checks source identity and requires the file to replace the invoking stub.
;; Inputs: directory - full directory path; source - canonical source identity; symbol - C:
;; command symbol.
;; Returns: nothing visible; loads/verifies the cached command and invokes it.
(defun GitHub_AutoloadCommand (directory source symbol / cache manifest before after summary)
  (cond
    (*GitHub-AutoloadBusy* (prompt "\nGitHub error: an autoload file is already being loaded."))
    ((not (and
          (setq manifest (GitHub_ReadManifest (strcat directory "\\manifest.dat")))
          (equal source (cdr (assoc "source" manifest)))
        )
      )
      (prompt "\nGitHub error: autoload cache identity changed or its manifest is missing.")
    )
    (t
      (setq before (eval symbol)
        cache (GitHub_CacheInfo directory manifest)
        summary
        ((lambda (/ *GitHub-AutoloadBusy*)
            (setq *GitHub-AutoloadBusy* T)
            (GitHub_LoadCache cache)
          )
        )
      )
      (if (= (cdr (assoc "status" summary)) "loaded")
        (if (and (setq after (eval symbol)) (not (eq before after)))
          (apply symbol nil)
          (prompt (strcat "\nGitHub error: the cached file did not define " (vl-symbol-name symbol) "."))
        )
      )
    )
  )
  (princ)
)

;; Syncs one explicit file URL and registers deferred C: commands.
;; commands - command-name strings without C: prefixes; token - string or nil.
;; Returns registered/existing names and sync-status; registration preserves definitions.
;; Command use loads only from cache; tokens and URLs are not stored in stubs.
(defun GitHub_Autoload
  (url commands token / data names path sync cache manifest source directory root entry
    filename name symbol registered existing
  )
  (cond
    ((null (setq names (GitHub_CommandNames commands))) nil)
    ((not (and
          (GitHub_IsValidGitHubURL url)
          (setq data (GitHub_ParseGitHubURL url))
          (= (cdr (assoc "type" data)) "file")
          (setq path (GitHub_Join (cdr (assoc "path" data)) "/"))
          (member (strcase (cond
                ((vl-filename-extension path))
                ("")
              )
            )
            '(".LSP" ".FAS" ".VLX")
          )
        )
      )
      (prompt "\nGitHub error: autoload requires an explicit .lsp, .fas, or .vlx file URL.")
      nil
    )
    ((and token (null (GitHub_AuthHeaders token "api"))) nil)
    (t
      (setq sync (vl-catch-all-apply 'GitHub_Sync (list url token)) token nil)
      (if (vl-catch-all-error-p sync)
        (setq sync nil)
      )
      (setq cache (GitHub_FindCachedSource data)
        manifest (cdr (assoc "manifest" cache))
        source (cdr (assoc "source" manifest))
        directory (cdr (assoc "directory" cache))
        root (cdr (assoc "files-root" cache))
      )
      (cond
        ((or
            (member (cdr (assoc "status" sync)) '("busy" "recovery"))
            (null (cdr (assoc "commit" manifest)))
            (cdr (assoc "recovery" cache))
            (not directory)
          )
          (prompt "\nGitHub error: no ready installed file is available for autoload.")
          nil
        )
        ((or
            (vl-file-size (strcat directory "\\manifest.dat.bak"))
            (vl-file-directory-p (strcat directory "\\manifest.dat.bak"))
            (vl-file-size (strcat directory "\\sync.lock"))
            (vl-file-directory-p (strcat directory "\\sync.lock"))
            (vl-directory-files directory "txn-*" -1)
          )
          (prompt "\nGitHub error: autoload cache is busy or requires recovery.")
          nil
        )
        ((not (and
              (setq entry (car (GitHub_SelectLoadFiles manifest)))
              (setq filename (GitHub_SafeFile root (cdr (assoc "path" entry))))
              (GitHub_FileMatches filename entry)
            )
          )
          (prompt "\nGitHub error: autoload entry is missing, modified, or unsafe.")
          nil
        )
        (t
          (if (not (member (cdr (assoc "status" sync)) '("synced" "up-to-date" "cached")))
            (prompt "\nGitHub warning: autoload will use the previous cached copy.")
          )
          (foreach name names
            (setq symbol (read (strcat "C:" name)))
            (if (eval symbol)
              (setq existing (cons name existing))
              (progn
                ;; Construct data, not source text; only validated names reach read.
                (eval (list 'defun symbol '()
                    (list 'GitHub_AutoloadCommand directory (list 'quote source) (list 'quote symbol))
                  )
                )
                (setq registered (cons name registered))
              )
            )
          )
          (list (cons "status" "registered") (cons "commands" (reverse registered))
            (cons "existing" (reverse existing))
            (cons "sync-status" (cdr (assoc "status" sync)))
          )
        )
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; User commands and command-line messages
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; action - operation label; summary - internal result association list.
;; Returns nothing visible; prints a short user-facing result.
(defun GitHub_Report (action summary / status sync loaded failed)
  (setq status (cdr (assoc "status" summary)) sync (cdr (assoc "sync-status" summary)))
  (cond
    ((null summary) (prompt (strcat "\nGitHub: " action " could not complete.")))
    ((= action "Load")
      (setq loaded (length (cdr (assoc "loaded" summary))) failed (cdr (assoc "failed" summary)))
      (cond
        ((= status "loaded")
          (prompt (strcat "\nGitHub: loaded " (itoa loaded) " file(s)"
              (if (= sync "cached")
                " from the offline cache."
                "."
              )
            )
          )
        )
        ((= status "partial")
          (prompt (strcat "\nGitHub: loaded " (itoa loaded) " file(s); stopped at "
              (if failed
                failed
                "an unavailable entry"
              ) "."
            )
          )
        )
        ((= status "no-entry-files"))
        (t (prompt "\nGitHub: no files were loaded."))
      )
    )
    ((= action "Autoload")
      (prompt (strcat "\nGitHub: registered "
          (itoa (length (cdr (assoc "commands" summary)))) " deferred command(s); "
          (itoa (length (cdr (assoc "existing" summary)))) " already defined."
        )
      )
    )
    (t
      (prompt (strcat "\nGitHub: " action " - " status
          ". Download: " (itoa (cdr (assoc "download" summary)))
          "; keep: " (itoa (cdr (assoc "keep" summary)))
          "; remove: " (itoa (cdr (assoc "remove" summary)))
          "; conflicts: " (itoa (cdr (assoc "conflicts" summary))) "."
        )
      )
    )
  )
  (princ)
)

;; url - repository, folder, or file URL; token - token string or nil.
;; Prints the sync plan without installing files; returns nothing visible.
(defun GitHubPreview (url token)
  (if (not *GitHub-Disabled*)
    (GitHub_Report "Preview" (GitHub_Preview url token))
    (prompt "\nGitHub: uninstalled in this drawing. Restart AutoCAD.")
  )
  (princ)
)

;; url - repository, folder, or file URL; token - token string or nil.
;; Syncs without loading code, prints counts, and returns nothing visible.
(defun GitHubSync (url token)
  (if (not *GitHub-Disabled*)
    (GitHub_Report "Sync" (GitHub_Sync url token))
    (prompt "\nGitHub: uninstalled in this drawing. Restart AutoCAD.")
  )
  (princ)
)

;; url - repository, folder, or file URL; token - token string or nil.
;; Syncs and loads eligible files, prints a summary, and returns nothing visible.
(defun GitHubLoad (url token)
  (if (not *GitHub-Disabled*)
    (GitHub_Report "Load" (GitHub_Load url token))
    (prompt "\nGitHub: uninstalled in this drawing. Restart AutoCAD.")
  )
  (princ)
)

;; url - explicit file URL; commands - names without C:; token - string or nil.
;; Registers deferred commands, prints counts, and returns nothing visible.
(defun GitHubAutoload (url commands token)
  (if (not *GitHub-Disabled*)
    (GitHub_Report "Autoload" (GitHub_Autoload url commands token))
    (prompt "\nGitHub: uninstalled in this drawing. Restart AutoCAD.")
  )
  (princ)
)

;; action - "Load", "Sync", or "Preview"; prompts for a URL.
;; Returns nothing visible. Interactive calls use anonymous/public access.
(defun GitHub_Command (action / url *error*)
  ;; message - native error text. Returns nothing visible; cancellation exits quietly.
  (defun *error* (message)
    (if (not (wcmatch (strcase message) "*CANCEL*,*QUIT*,*BREAK*"))
      (prompt (strcat "\nGitHub: " message))
    )
    (princ)
  )
  (setq url (getstring T "\nGitHub URL: "))
  (if (/= url "")
    (cond
      ((= action "Load") (GitHubLoad url nil))
      ((= action "Sync") (GitHubSync url nil))
      (t (GitHubPreview url nil))
    )
    (prompt "\nGitHub: cancelled.")
  )
  (princ)
)

;; No inputs. Prompts for a URL and loads its files; returns nothing visible.
(defun C:GITHUBLOAD ()
  (GitHub_Command "Load")
  (princ)
)

;; No inputs. Prompts for a URL and syncs its files; returns nothing visible.
(defun C:GITHUBSYNC ()
  (GitHub_Command "Sync")
  (princ)
)

;; No inputs. Prompts for a URL and displays its plan; returns nothing visible.
(defun C:GITHUBPREVIEW ()
  (GitHub_Command "Preview")
  (princ)
)

;; No inputs. Lists user commands and the cache location; returns nothing visible.
(defun C:GITHUBHELP ()
  (prompt "\n3Ding GitHub")
  (prompt "\n  GITHUBLOAD       Sync and load a GitHub URL.")
  (prompt "\n  GITHUBSYNC       Update cached files without loading.")
  (prompt "\n  GITHUBPREVIEW    Show planned downloads and conflicts.")
  (prompt "\n  GITHUBSTATUS     Show installation and cache locations.")
  (prompt "\n  GITHUBINSTALL    Install for this Windows user.")
  (prompt "\n  GITHUBCLEARCACHE Remove downloaded files and cache metadata.")
  (prompt "\n  GITHUBUNINSTALL  Remove the installation and all tool data.")
  (if (not C:GITHUBINSTALL)
    (prompt "\n  Load Install.lsp to enable setup/removal commands.")
  )
  (princ)
)

(prompt "\n3Ding GitHub ready. Type GITHUBHELP for commands.")
(princ)
