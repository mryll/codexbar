PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

install:
	install -Dm755 codexbar $(DESTDIR)$(BINDIR)/codexbar

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/codexbar

.PHONY: install uninstall
