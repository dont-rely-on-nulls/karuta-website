;;; publish.el --- Org-publish Karuta's Website -*- lexical-binding: t; -*-

;;; Commentary:
;;;
;;; Build the Karuta website from Org-mode sources.
;;; Usage:
;;;   Interactive: M-x eval-buffer, then M-x org-publish-all
;;;   CLI:         emacs --batch --load publish.el
;;;
;;; Pages are written in Org.  Layout comes from special blocks: a block
;;; named after an HTML element (#+begin_section, #+begin_h1, ...) becomes
;;; that element, any other name becomes a <div> with that class.  Block
;;; parameters add classes and an id: "#+begin_section .hero #top".
;;; Small pieces of markup (eyebrows, buttons, cards) are the macros in
;;; `org-export-global-macros' below.

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
(defvar roam-dir (expand-file-name "codex" org-dir))

(defvar out-dir (expand-file-name "public" root-dir))
(defvar out-url (if (string= (getenv "ENVIRONMENT") "dev")
                    (concat out-dir "/")
                  "https://karuta-lang.org/"))

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

;;; HTML fragments
(defvar html-head   (slurp (expand-file-name "header.html" static-html-dir)))
(defvar html-nav    (slurp (expand-file-name "nav.html" static-html-dir)))
(defvar html-footer (slurp (expand-file-name "footer.html" static-html-dir)))

;;; Org keywords
(defun drn/get-org-keyword (filepath keyword)
  "Extract value of KEYWORD (e.g. \"PDF\") from FILEPATH, or nil."
  (with-temp-buffer
    (insert-file-contents filepath)
    (goto-char (point-min))
    (when (re-search-forward
           (format "^#\\+%s:[ \t]*\\(.*\\)$" (regexp-quote keyword)) nil t)
      (let ((val (string-trim (match-string 1))))
        (unless (string-empty-p val) val)))))

(defun drn/get-org-title (filepath)
  "Extract #+TITLE: from FILEPATH."
  (or (drn/get-org-keyword filepath "TITLE")
      (file-name-base filepath)))

(defun drn/get-org-date (filepath)
  "Extract #+DATE: from FILEPATH."
  (let ((date (or (drn/get-org-keyword filepath "DATE") "")))
    (if (string-match "^[0-9T:-]*" date) (match-string 0 date) "")))

(defun drn/format-date (date)
  "Format an ISO DATE like 2026-09-24 as \"24 Sep 2026\"."
  (if (string-match "^\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)" date)
      (format "%d %s %s"
              (string-to-number (match-string 3 date))
              (aref ["Jan" "Feb" "Mar" "Apr" "May" "Jun"
                     "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"]
                    (1- (string-to-number (match-string 2 date))))
              (match-string 1 date))
    date))

;;; Blog posts
(defun drn/blog-post (filepath)
  "Return a plist describing the blog post at FILEPATH."
  (list :slug    (file-name-base filepath)
        :title   (drn/get-org-title filepath)
        :date    (drn/get-org-date filepath)
        :tag     (car (split-string (or (drn/get-org-keyword filepath "FILETAGS") "") ":" t))
        :excerpt (or (drn/get-org-keyword filepath "DESCRIPTION") "")
        :kana    (or (drn/get-org-keyword filepath "KANA") "")
        :sample  (drn/get-org-keyword filepath "SAMPLE")))

(defun drn/blog-posts ()
  "Return all blog posts, newest first."
  (sort (mapcar #'drn/blog-post
                (seq-remove (lambda (f)
                              (let ((name (file-name-nondirectory f)))
                                (or (string-prefix-p "." name)
                                    (string= name "index.org"))))
                            (drn/directory-files blog-dir)))
        (lambda (a b) (string> (plist-get a :date) (plist-get b :date)))))

(defun drn/post-card (post)
  "Return the karuta card linking to POST."
  (format "<a class=\"pcard\" href=\"/blog/%s.html\"><img src=\"/static/img/card-blank.webp\" alt=\"\" aria-hidden=\"true\"><span class=\"jp\" aria-hidden=\"true\">%s</span><span class=\"pcard-in\"><time datetime=\"%s\">%s</time><h3>%s</h3><p>%s</p><span class=\"tag\">%s</span></span></a>"
          (plist-get post :slug) (plist-get post :kana)
          (plist-get post :date) (drn/format-date (plist-get post :date))
          (plist-get post :title) (plist-get post :excerpt) (or (plist-get post :tag) "")))

(defun drn/blog-deck (limit)
  "Return the deck of post cards as an Org HTML snippet.
LIMIT is a string; when it is a number, show only that many posts."
  (let ((posts (drn/blog-posts))
        (n (string-to-number (or limit ""))))
    (when (> n 0)
      (setq posts (seq-take posts n)))
    (format "@@html:<div class=\"deck\">%s</div>@@"
            (mapconcat #'drn/post-card posts ""))))

;;; Markup macros, available in every page
(setq org-export-global-macros
      '(("acc"       . "@@html:<span class=\"acc\">$1</span>@@")
        ("eyebrow"   . "@@html:<span class=\"eyebrow\">$1</span>@@")
        ("h2"        . "@@html:<h2>$1</h2>@@")
        ("h3"        . "@@html:<h3>$1</h3>@@")
        ("a"         . "@@html:<a href=\"$1\">$2</a>@@")
        ("btn"       . "@@html:<a class=\"btn $1\" href=\"$2\">$3</a>@@")
        ("badge"     . "@@html:<span class=\"s-badge\">$1</span>@@")
        ("proc"      . "@@html:<div class=\"proc\"><i></i><span><b>$1</b> = $2</span><s>$3</s></div>@@")
        ("grab"      . "@@html:<button class=\"grab\" aria-pressed=\"false\"><img src=\"/static/img/$1-tori.webp\" alt=\"Grabbing card, written in hiragana\" width=\"600\" height=\"849\" loading=\"lazy\"><span class=\"grab-cap\">Take the card</span></button>@@")
        ("term-head" . "@@html:<div class=\"row\"><span class=\"eyebrow\">Terminal</span><button class=\"copy\" data-copy=\"$1\">Copy</button></div>@@")
        ("deck"      . "(eval (drn/blog-deck $1))")))

;;; Export backend
(defconst karuta/html-tags
  '("section" "aside" "article" "nav" "header" "footer" "main" "div" "span"
    "h1" "h2" "h3" "blockquote" "button" "time" "figure")
  "Special blocks with these names export as the element itself.")

(defconst karuta/inline-tags
  '("h1" "h2" "h3" "blockquote" "span" "button" "time")
  "Elements whose text is not wrapped in <p>.")

(defun karuta/block-selectors (params)
  "Split PARAMS like \".hero #top\" into (CLASSES . ID)."
  (let (classes id)
    (dolist (token (split-string (or params "")))
      (cond ((string-prefix-p "." token) (push (substring token 1) classes))
            ((string-prefix-p "#" token) (setq id (substring token 1)))))
    (cons (nreverse classes) id)))

(defun karuta/special-block (block contents _info)
  "Export special BLOCK holding CONTENTS as an element or a classed div."
  (let* ((type (downcase (org-element-property :type block)))
         (tag-p (member type karuta/html-tags))
         (tag (if tag-p type "div"))
         (selectors (karuta/block-selectors (org-element-property :parameters block)))
         (attrs (org-export-read-attribute :attr_html block))
         (classes (delq nil (append (unless tag-p (list type))
                                    (car selectors)
                                    (list (plist-get attrs :class))))))
    (when classes
      (setq attrs (plist-put attrs :class (string-join classes " "))))
    (when (cdr selectors)
      (setq attrs (plist-put attrs :id (cdr selectors))))
    (let ((attr-string (org-html--make-attribute-string attrs)))
      (format "<%s%s>%s</%s>\n"
              tag
              (if (string-empty-p attr-string) "" (concat " " attr-string))
              (string-trim (or contents ""))
              tag))))

(defun karuta/bare-paragraph-p (paragraph)
  "Non-nil when PARAGRAPH should export without a <p> around it.
That is a paragraph inside an inline element, or one holding only
markup: links, images, macros and line breaks."
  (let ((parent (org-export-get-parent paragraph)))
    (or (and (eq (org-element-type parent) 'special-block)
             (member (downcase (org-element-property :type parent)) karuta/inline-tags))
        (seq-every-p (lambda (child)
                       (if (stringp child)
                           (string-blank-p child)
                         (memq (org-element-type child) '(export-snippet link line-break))))
                     (org-element-contents paragraph)))))

(defun karuta/paragraph (paragraph contents info)
  "Export PARAGRAPH, leaving out <p> where `karuta/bare-paragraph-p' says so."
  (if (karuta/bare-paragraph-p paragraph)
      (string-trim contents)
    (org-html-paragraph paragraph contents info)))

(defun karuta/link (link desc info)
  "Export LINK; images with the deco class are hidden from screen readers."
  (let ((html (org-html-link link desc info)))
    (if (string-match-p "<img[^>]*class=\"[^\"]*\\bdeco\\b" html)
        (replace-regexp-in-string "alt=\"[^\"]*\"" "alt=\"\" aria-hidden=\"true\"" html t t)
      html)))

(defconst karuta/token-regexp
  (rx (or (group "%" (* nonl))
          (group "'" (* (not (any "'\n"))) "'")
          (group (or ":-" "?-" "|" (seq "/" (+ digit))))
          (group symbol-start (any "A-Z_") (* (any "A-Za-z0-9_")))
          (group symbol-start (any "a-z") (* (any "A-Za-z0-9_")))))
  "Comments, quoted atoms, operators, variables and atoms.")

(defun karuta/highlight (code)
  "Return CODE as HTML with Karuta tokens wrapped in colour classes."
  (let ((case-fold-search nil)
        (pos 0)
        (out '()))
    (while (string-match karuta/token-regexp code pos)
      (let ((start (match-beginning 0))
            (end (match-end 0))
            (class (cond ((match-beginning 1) "k-c")
                         ((match-beginning 2) "k-a")
                         ((match-beginning 3) "k-o")
                         ((match-beginning 4) "k-v")
                         (t "k-a"))))
        (push (org-html-encode-plain-text (substring code pos start)) out)
        (push (format "<span class=\"%s\">%s</span>"
                      class (org-html-encode-plain-text (substring code start end)))
              out)
        (setq pos end)))
    (push (org-html-encode-plain-text (substring code pos)) out)
    (apply #'concat (nreverse out))))

(defun karuta/src-block (block contents info)
  "Export Karuta source BLOCK as a highlighted <pre>; others as usual."
  (if (equal (org-element-property :language block) "karuta")
      (format "<pre>%s</pre>\n"
              (karuta/highlight (string-trim-right (org-element-property :value block))))
    (org-html-src-block block contents info)))

(defun karuta/post-p (info)
  "Non-nil when the file being exported (per INFO) is a blog post."
  (let ((file (plist-get info :input-file)))
    (and file
         (file-in-directory-p file blog-dir)
         (not (string= (file-name-nondirectory file) "index.org")))))

(defun karuta/inner-template (contents info)
  "Wrap blog posts (per INFO) in the post layout; other CONTENTS as usual."
  (if (not (karuta/post-p info))
      (org-html-inner-template contents info)
    (let ((post (drn/blog-post (plist-get info :input-file))))
      (format "<div class=\"wrap\"><article class=\"post\">
<a class=\"back\" href=\"/blog/\">← All posts</a>
<h1>%s</h1>
<div class=\"meta\"><time datetime=\"%s\">%s</time><b>%s</b>%s</div>
<div class=\"body\">%s</div>
<img class=\"deco orn\" src=\"/static/img/flower-a.webp\" alt=\"\" aria-hidden=\"true\">
</article></div>"
              (plist-get post :title)
              (plist-get post :date) (drn/format-date (plist-get post :date))
              (or (plist-get post :tag) "")
              (if (plist-get post :sample) "<span class=\"sample\">Sample post</span>" "")
              contents))))

(org-export-define-derived-backend 'karuta-html 'html
  :translate-alist '((special-block  . karuta/special-block)
                     (paragraph      . karuta/paragraph)
                     (link           . karuta/link)
                     (src-block      . karuta/src-block)
                     (inner-template . karuta/inner-template)))

(defun karuta/publish-to-html (plist filename pub-dir)
  "Publish FILENAME to PUB-DIR with the Karuta backend, using PLIST."
  (org-publish-org-to 'karuta-html filename ".html" plist pub-dir))

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
  (let* ((rss-file (expand-file-name "rss.xml" (expand-file-name "blog" out-dir)))
         (blog-url (concat out-url "blog/"))
         (now (format-time-string "%a, %d %b %Y %H:%M:%S %z")))
    (with-temp-buffer
      (insert "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
      (insert "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n")
      (insert "  <channel>\n")
      (insert "    <title>Karuta — Blog</title>\n")
      (insert (format "    <link>%s</link>\n" blog-url))
      (insert (format "    <atom:link href=\"%srss.xml\" rel=\"self\" type=\"application/rss+xml\"/>\n" blog-url))
      (insert "    <description>Latest blog posts from Karuta</description>\n")
      (insert "    <language>en</language>\n")
      (insert (format "    <lastBuildDate>%s</lastBuildDate>\n" now))
      (dolist (post (drn/blog-posts))
        (let ((url (concat blog-url (plist-get post :slug) ".html")))
          (insert "    <item>\n")
          (insert (format "      <title>%s</title>\n" (org-html-encode-plain-text (plist-get post :title))))
          (insert (format "      <link>%s</link>\n" url))
          (insert (format "      <guid isPermaLink=\"true\">%s</guid>\n" url))
          (insert (format "      <pubDate>%sT00:00:00Z</pubDate>\n" (plist-get post :date)))
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
(defun drn/site-preamble (info)
  "Return the nav, marking the link to the page in INFO as current."
  (let* ((file (file-relative-name (plist-get info :input-file) org-dir))
         (page (cond ((string-prefix-p "blog/" file) "posts")
                     ((string= file "about.org") "about")
                     ((string= file "sakura.org") "sakura"))))
    (if page
        (replace-regexp-in-string (format "data-page=\"%s\"" page)
                                  "aria-current=\"page\"" html-nav t t)
      html-nav)))

(defvar site-postamble html-footer)

;;; org-publish project
(setq org-publish-project-alist
      `(("site"
         :base-directory ,org-dir
         :base-extension "org"
         :publishing-directory ,out-dir
         :publishing-function karuta/publish-to-html
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
         :html-preamble drn/site-preamble
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
