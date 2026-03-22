.PHONY: install uninstall test link

PREFIX ?= /usr/local

install: ## Install claude-ollama to PREFIX/bin
	@echo "Installing claude-ollama to $(PREFIX)/bin..."
	@install -d $(PREFIX)/bin
	@install -m 755 bin/claude-ollama $(PREFIX)/bin/claude-ollama
	@echo "Done. Run 'claude-ollama' to get started."

uninstall: ## Remove claude-ollama from PREFIX/bin
	@rm -f $(PREFIX)/bin/claude-ollama
	@echo "Removed claude-ollama from $(PREFIX)/bin"

link: ## Symlink claude-ollama for development
	@ln -sf $(CURDIR)/bin/claude-ollama $(PREFIX)/bin/claude-ollama
	@echo "Linked $(PREFIX)/bin/claude-ollama -> $(CURDIR)/bin/claude-ollama"

test: ## Test connectivity to configured Ollama instance
	@bin/claude-ollama --test

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
