;;; publish.el --- Org-publish DrN's Website -*- lexical-binding: t; -*-

;;; Commentary:
;;;
;;; Build the Don't Rely on Nulls website from Org-mode sources.
;;; Usage:
;;;   Interactive: M-x eval-buffer, then M-x org-publish-all
;;;   CLI:         emacs --batch --load publish.el

;;; Code:

(require 'citeproc)
(require 'find-lisp)
(require 'htmlize)
(require 'org)
(require 'org-roam)
(require 'ox)
(require 'ox-html)
(require 'ox-publish)
(require 'ox-rss)
(require 'seq)

;;; Global org-mode settings
(setq org-confirm-babel-evaluate nil)
(setq org-export-use-babel t)
(setq org-src-preserve-indentation t)
(setq org-src-fontify-natively t)
(setq make-backup-files nil)
(setq org-html-validation-link nil)
(setq org-html-head-include-scripts nil)
(setq org-html-head-include-default-style nil)
(setq org-html-doctype "html5")
(setq org-html-html5-fancy t)
(setq org-html-divs '((preamble  "header" "preamble")
                      (content   "main"   "content")
                      (postamble "footer" "postamble")))

;;; Paths
(defvar root-dir (expand-file-name (or (getenv "PWD") default-directory)))
(defvar static-dir (expand-file-name "static" root-dir))
(defvar static-html-dir (expand-file-name "html" static-dir))
(defvar static-img-dir (expand-file-name "img" static-dir))
(defvar static-css-dir (expand-file-name "css" static-dir))
(defvar org-dir (expand-file-name "org" root-dir))
(defvar blog-dir (expand-file-name "blog" org-dir))
(defvar presentations-dir (expand-file-name "presentations" org-dir))
(defvar roam-dir (expand-file-name "codex" org-dir))

(defvar out-dir (expand-file-name "public" root-dir))
(defvar out-url (if (string= (getenv "ENVIRONMENT") "dev")
                    (concat out-dir "/")
                  "https://www.dontrelynulls.org/"))

(defun drn/directory-files (dir)
  (directory-files dir 't "\\.org$"))

;;; Utility: read file content as string
(defun slurp (path)
  "Return file content of PATH as string, or \"\" if missing."
  (if (file-exists-p path)
      (with-temp-buffer
        (insert-file-contents path)
        (buffer-string))
    ""))

;;; HTML fragments, replaces %ROOT% with the following:
;;;   On dev -> out-dir
;;;   On prod -> "https://www.dontrelynulls.org"
(defvar root-href (if (string= (getenv "ENVIRONMENT") "dev")
                      (directory-file-name out-dir)
                    (directory-file-name out-url)))
(defvar html-head   (slurp (expand-file-name "header.html" static-html-dir)))
(defvar html-nav    (replace-regexp-in-string
                     "%ROOT%" root-href
                     (slurp (expand-file-name "nav.html" static-html-dir)) t t))
(defvar html-footer (replace-regexp-in-string
                     "%ROOT%" root-href
                     (slurp (expand-file-name "footer.html" static-html-dir)) t t))

;;; Blog listing
(defun drn/get-org-title (filepath)
  "Extract #+TITLE: from FILEPATH."
  (with-temp-buffer
    (insert-file-contents filepath)
    (goto-char (point-min))
    (if (re-search-forward "^#\\+TITLE:\s*\\(.*\\)$" nil t)
        (string-trim-right (match-string 1))
      (file-name-base filepath))))

(defun drn/get-org-date (filepath)
  "Extract #+DATE: from FILEPATH."
  (with-temp-buffer
    (insert-file-contents filepath)
    (goto-char (point-min))
    (if (re-search-forward "^#\\+DATE:\s*\\([0-9T:-]*\\)" nil t)
        (match-string 1)
      "")))

(defun drn/generate-blog-list ()
  "Return HTML list of blog posts, sorted anti-chronologically."
  (let* ((files (drn/directory-files blog-dir))
         (entries '()))
    (dolist (f files)
      (let* ((fname (file-name-nondirectory f))
             (slug (file-name-sans-extension fname)))
        (unless (or (string-prefix-p "." fname)
                    (string= slug "index"))
          (let ((title (drn/get-org-title f))
                (date  (drn/get-org-date f)))
            (push (list date title slug) entries)))))
    (setq entries (sort entries (lambda (a b) (string> (car a) (car b)))))
    (mapconcat
     (lambda (e)
        (format "\n    <article class=\"blog-post\">\n      <h2 class=\"post-title-link\"><a href=\"/blog/%s.html\">%s</a></h2>\n      <time datetime=\"%s\">%s</time>\n    </article>"
                (nth 2 e) (nth 1 e) (nth 0 e) (nth 0 e)))
     entries "")))

(defun drn/get-org-keyword (filepath keyword)
  "Extract value of KEYWORD (e.g. \"PDF\") from FILEPATH, or nil."
  (with-temp-buffer
    (insert-file-contents filepath)
    (goto-char (point-min))
    (when (re-search-forward
           (format "^#\\+%s:[ \t]*\\(.*\\)$" (regexp-quote keyword)) nil t)
      (let ((val (string-trim (match-string 1))))
        (unless (string-empty-p val) val)))))

(defun drn/generate-presentation-list ()
  "Return HTML list of presentations, sorted anti-chronologically.
Each presentation Org file supplies #+TITLE:, #+DATE: and #+AUTHOR:.
Entries link to the presentation's own page."
  (let* ((files (drn/directory-files presentations-dir))
         (entries '()))
    (dolist (f files)
      (let* ((fname (file-name-nondirectory f))
             (slug (file-name-sans-extension fname)))
        (unless (or (string-prefix-p "." fname)
                    (string= slug "index"))
          (let ((title (drn/get-org-title f))
                (date  (drn/get-org-date f))
                (author (drn/get-org-keyword f "AUTHOR")))
            (push (list date title author slug) entries)))))
    (setq entries (sort entries (lambda (a b) (string> (car a) (car b)))))
    (mapconcat
     (lambda (e)
       (let ((author-html (if (nth 2 e)
                              (format " by: <span class=\"presenter\">\"%s\"</span>" (nth 2 e))
                            "")))
         (format "\n    <article class=\"blog-card\">\n      <h2><a href=\"/presentations/%s.html\">%s</a></h2>\n      <time datetime=\"%s\">%s</time>%s\n    </article>"
                 (nth 3 e) (nth 1 e) (nth 0 e) (nth 0 e) author-html)))
     entries "")))

;;; org-roam
(setq org-roam-directory roam-dir)
(setq org-roam-db-location (expand-file-name "org-roam.db" roam-dir))

(defun notes/sync-db-if-ci ()
  "Sync org-roam DB in CI."
  (when (string= (or (getenv "IS_CI") "") "1")
    (message "CI: syncing org-roam database...")
    (org-roam-db-sync)))

(defun notes/insert-backlinks (backend)
  "Add backlinks section to roam notes before export, targets BACKEND."
  (when (org-roam-node-at-point)
    (goto-char (point-max))
    (let ((backlinks (org-roam-backlinks-get (org-roam-node-at-point))))
      (when backlinks
        (insert "\n* Backlinks\n")
        (dolist (bl backlinks)
          (let ((sn (org-roam-backlink-source-node bl)))
            (insert (format "- [[file:%s][%s]]\n"
                            (file-name-nondirectory (org-roam-node-file sn))
                            (org-roam-node-title sn)))))))))

(add-hook 'org-export-before-processing-functions
          (lambda (backend) (notes/insert-backlinks backend)))

;;; RSS
;;; Generate a combined RSS 2.0 feed from blog posts
(defun drn/generate-rss-feed (&rest _)
  "Write a combined RSS 2.0 feed to blog/rss.xml after site build."
  (let* ((files (drn/directory-files blog-dir))
         (entries '())
         (rss-file (expand-file-name "rss.xml" (expand-file-name "blog" out-dir)))
         (blog-url (concat out-url "blog/"))
         (now (format-time-string "%a, %d %b %Y %H:%M:%S %z")))
    ;; Collect post data
    (dolist (f files)
      (let* ((fname (file-name-nondirectory f))
             (slug (file-name-sans-extension fname)))
        (unless (or (string-prefix-p "." fname)
                    (string= slug "index"))
          (let ((title (drn/get-org-title f))
                (date  (drn/get-org-date f)))
            (when (and title date)
              (push (list date title slug) entries))))))
    (setq entries (sort entries (lambda (a b) (string> (car a) (car b)))))
    ;; Build RSS XML
    (with-temp-buffer
      (insert "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
      (insert "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n")
      (insert "  <channel>\n")
      (insert "    <title>Don't Rely on Nulls — Blog</title>\n")
      (insert (format "    <link>%s</link>\n" blog-url))
      (insert (format "    <atom:link href=\"%srss.xml\" rel=\"self\" type=\"application/rss+xml\"/>\n" blog-url))
      (insert "    <description>Latest blog posts from Don't Rely on Nulls</description>\n")
      (insert "    <language>en</language>\n")
      (insert (format "    <lastBuildDate>%s</lastBuildDate>\n" now))
      (dolist (e entries)
        (let* ((date  (car e))
               (title (nth 1 e))
               (slug  (nth 2 e))
               (url   (concat blog-url slug ".html"))
               (pubdate (format "%sT00:00:00Z" date)))
          (insert "    <item>\n")
          (insert (format "      <title>%s</title>\n" (org-html-encode-plain-text title)))
          (insert (format "      <link>%s</link>\n" url))
          (insert (format "      <guid isPermaLink=\"true\">%s</guid>\n" url))
          (insert (format "      <pubDate>%s</pubDate>\n" pubdate))
          (insert "    </item>\n")))
      (insert "  </channel>\n")
      (insert "</rss>\n")
      (make-directory (file-name-directory rss-file) t)
      (write-region (point-min) (point-max) rss-file))
    (message "RSS feed written to %s" rss-file)))

;;; Post-process: fix relative paths based on page depth
(defun drn/fix-relative-paths (&rest _)
  "Rewrite 'static/' paths in HTML files to be depth-aware.
Replaces 'static/' with '../static/' based on page depth from root."
  (let ((html-files (directory-files-recursively out-dir "\\.html$")))
    (dolist (f html-files)
      (let ((rel  (file-relative-name f out-dir)))
        (setq rel (file-name-directory rel))
        (let ((depth (if rel
                         (with-temp-buffer
                           (insert rel)
                           (how-many "/" (point-min) (point-max)))
                       0))
              (prefix ""))
          (dotimes (_ depth)
            (setq prefix (concat prefix "../")))
          (with-temp-buffer
            (insert-file-contents f)
            (goto-char (point-min))
            (while (re-search-forward "\\(\\(?:href\\|src\\)=\"\\)static/" nil t)
              (replace-match (concat "\\1" prefix "static/")))
            (write-region (point-min) (point-max) f))
          (when (> depth 0)
            (message "Fixed paths in %s (depth=%d)" f depth)))))))

;;; Completion function that runs both RSS and path fixes
(defun drn/on-site-complete (&rest _)
  "Run post-build tasks: RSS feed and path fixing."
  (drn/generate-rss-feed)
  (drn/fix-relative-paths))

;;; Preamble and postamble
(defvar site-preamble html-nav)

(defvar site-postamble html-footer)

;;; org-publish project
(setq org-publish-project-alist
      `(("site"
         :base-directory ,org-dir
         :base-extension "org"
         :publishing-directory ,out-dir
         :publishing-function org-html-publish-to-html
         :recursive t

         :with-creator t
         :with-tags t
         :with-title t
         :with-author t
         :with-date t
         :with-toc nil
         :section-numbers nil
         :headline-levels 5
         :exclude-tags ("noexport")

         :html-head ,html-head
         :html-preamble ,site-preamble
         :html-postamble ,site-postamble
          :completion-function drn/on-site-complete)

        ("images"
         :base-directory ,static-img-dir
         :base-extension "png\\|jpg\\|jpeg\\|gif\\|svg\\|ico\\|webp"
         :publishing-directory ,(expand-file-name "img" (expand-file-name "static" out-dir))
         :recursive t
         :publishing-function org-publish-attachment)

        ("css"
         :base-directory ,static-css-dir
         :base-extension "css"
         :publishing-directory ,(expand-file-name "css" (expand-file-name "static" out-dir))
         :recursive t
         :publishing-function org-publish-attachment)

        ("all" :components ("css" "images" "site"))))

;;; Build
(notes/sync-db-if-ci)
(org-publish-all t)

(message "Website build complete!")

(provide 'publish)
;;; publish.el ends here
