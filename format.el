(require 'org)

(add-hook 'org-mode-hook (lambda () (setf fill-column 120)))

(defun fmt/fill-org-paragraph (p)
  (save-excursion
    (goto-char (org-element-begin p))
    (org-fill-paragraph)))

(defun fmt/within-special-block-p (elem)
  (eq 'special-block (org-element-type (org-element-property :parent elem))))

(defun fmt/fill-org-buffer ()
  (interactive)
  (font-lock-ensure)
  (let* ((ast (org-element-parse-buffer))
         (paragraphs (reverse (cl-remove-if #'fmt/within-special-block-p (org-element-map ast 'paragraph #'identity)))))
    (mapc #'fmt/fill-org-paragraph paragraphs)))

(defun fmt/format-org-file (f)
  (save-excursion
    (find-file f)
    (fmt/fill-org-buffer)
    (when (buffer-modified-p)
      (save-buffer)
      (message "Formatting %s..." f))))

(defun fmt/format-org-directory (dir)
  (mapc #'fmt/format-org-file (directory-files-recursively dir "\\.org$")))
