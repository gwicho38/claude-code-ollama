.PHONY: install uninstall test link

PREFIX ?= /usr/local

install: ## Install claude-local to PREFIX/bin
	@echo "Installing claude-local to $(PREFIX)/bin..."
	@install -d $(PREFIX)/bin
	@install -m 755 bin/claude-local $(PREFIX)/bin/claude-local
	@echo "Done. Run 'claude-local' to get started."

uninstall: ## Remove claude-local from PREFIX/bin
	@rm -f $(PREFIX)/bin/claude-local
	@echo "Removed claude-local from $(PREFIX)/bin"

link: ## Symlink claude-local for development
	@ln -sf $(CURDIR)/bin/claude-local $(PREFIX)/bin/claude-local
	@echo "Linked $(PREFIX)/bin/claude-local -> $(CURDIR)/bin/claude-local"

test: ## Test connectivity to configured Ollama instance
	@bin/claude-local --test

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
