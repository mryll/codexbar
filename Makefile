PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
OMARCHY_PLUGIN_DIR ?= $(HOME)/.config/omarchy/plugins

install:
	install -Dm755 codexbar "$(DESTDIR)$(BINDIR)/codexbar"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/codexbar"

# Symlink the Omarchy shell plugin. The shell does not watch symlinked dirs:
# after editing files under omarchy/, run `omarchy restart shell`.
# Needs the codexbar binary on PATH (e.g. `make install PREFIX=~/.local`).
install-omarchy:
	@command -v codexbar >/dev/null 2>&1 || \
		echo "warning: codexbar not found on PATH — the widget will show an explicit error until it is installed (make install PREFIX=~/.local)"
	mkdir -p "$(OMARCHY_PLUGIN_DIR)"
	ln -sfT "$(abspath .)" "$(OMARCHY_PLUGIN_DIR)/mryll.codexbar"
	@echo 'Installed. Add { "id": "mryll.codexbar" } to the bar layout in ~/.config/omarchy/shell.json'

uninstall-omarchy:
	rm -f "$(OMARCHY_PLUGIN_DIR)/mryll.codexbar"

.PHONY: install uninstall install-omarchy uninstall-omarchy
