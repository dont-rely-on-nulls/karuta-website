.PHONY: build clean

PREFIX ?= ./public
export ENVIRONMENT ?= dev

build:
	@mkdir -p $(PREFIX)
	@emacs --batch \
		--eval "(setq debug-on-error t)" \
		--load publish.el \
		2>&1 | tee build.log

clean:
	@rm -rf public/ build.log
	@echo "✓ Cleaned"
