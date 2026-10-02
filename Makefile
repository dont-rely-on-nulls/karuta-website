SHELL := bash
.SHELLFLAGS := -euo pipefail -c
.DELETE_ON_ERROR:

export ENVIRONMENT ?= dev
EMACS ?= emacs
PORT ?= 8000

# publish.el always writes to ./public, so this is not configurable.
OUT_DIR := public
SOURCES := publish.el $(shell find org static -type f)

.PHONY: build serve clean FORCE

build: $(OUT_DIR)/index.html

# One publish.el run writes the whole site; index.html stands in for all of it.
$(OUT_DIR)/index.html: $(SOURCES) $(OUT_DIR)/.environment
	@$(EMACS) --batch \
		--eval "(setq debug-on-error t)" \
		--load publish.el \
		2>&1 | tee build.log

# Only rewritten when ENVIRONMENT changes, so switching dev/prod forces a rebuild.
$(OUT_DIR)/.environment: FORCE | $(OUT_DIR)
	@[[ "$$(cat $@ 2>/dev/null)" == "$(ENVIRONMENT)" ]] || echo "$(ENVIRONMENT)" > $@

$(OUT_DIR):
	@mkdir -p $@

serve: build
	python3 -m http.server --directory $(OUT_DIR) $(PORT)

clean:
	@rm -rf $(OUT_DIR) build.log
	@echo "✓ Cleaned"
