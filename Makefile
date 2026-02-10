PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

install:
	install -Dm755 codex-usage $(DESTDIR)$(BINDIR)/codex-usage

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/codex-usage

.PHONY: install uninstall
