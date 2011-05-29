#!/usr/bin/make -f

SRC_DIR=$(CURDIR)
SHELL=/bin/bash

INSTALL_DIR=install -d -o root -g root -m 755
INSTALL_FILE=install -o root -g root -m 644
INSTALL_PROGRAM=install -o root -g root -m 755

RM_FILE=rm -f
RM_DIR=rmdir -p --ignore-fail-on-non-empty

DESTDIR=
PREFIX=/usr/local
ETCDIR=/etc/x2go
BINDIR=$(PREFIX)/bin
SBINDIR=$(PREFIX)/sbin
LIBDIR=$(PREFIX)/lib/x2go
MANDIR=$(PREFIX)/share/man
SHAREDIR=$(PREFIX)/share/x2go

BIN_SCRIPTS=$(shell cd bin && ls)
SBIN_SCRIPTS=$(shell cd sbin && ls)
LIB_FILES=$(shell cd lib && ls)

all:

build:

install: install_scripts install_config install_man install_version

install_scripts:
	$(INSTALL_DIR) $(DESTDIR)$(BINDIR)
	$(INSTALL_DIR) $(DESTDIR)$(SBINDIR)
	$(INSTALL_DIR) $(DESTDIR)$(LIBDIR)
	$(INSTALL_PROGRAM) bin/*                $(DESTDIR)$(BINDIR)/
	$(INSTALL_PROGRAM) sbin/*               $(DESTDIR)$(SBINDIR)/
	$(INSTALL_FILE) lib/*                   $(DESTDIR)$(LIBDIR)/

install_config:
	$(INSTALL_DIR) $(DESTDIR)$(ETCDIR)
	$(INSTALL_DIR) $(DESTDIR)$(ETCDIR)/x2gosql
	$(INSTALL_DIR) $(DESTDIR)$(ETCDIR)/x2gosql/passwords
	$(INSTALL_FILE) etc/x2goserver.conf     $(DESTDIR)$(ETCDIR)/
	$(INSTALL_FILE) etc/x2gosql/sql         $(DESTDIR)$(ETCDIR)/x2gosql

install_man:
	$(INSTALL_DIR) $(DESTDIR)$(MANDIR)
	$(INSTALL_DIR) $(DESTDIR)$(MANDIR)/man8
	$(INSTALL_FILE) man/man8/*.8           $(DESTDIR)$(MANDIR)/man8
	gzip -f $(DESTDIR)$(MANDIR)/man8/x2go*.8

install_version:
	$(INSTALL_DIR) $(DESTDIR)$(SHAREDIR)
	$(INSTALL_DIR) $(DESTDIR)$(SHAREDIR)/versions
	$(INSTALL_FILE) VERSION.x2goserver     $(DESTDIR)$(SHAREDIR)/versions/VERSION.x2goserver

uninstall: uninstall_scripts uninstall_config uninstall_man uninstall_version

uninstall_scripts:
	for file in $(BIN_SCRIPTS); do $(RM_FILE) $(DESTDIR)$(BINDIR)/$$file; done
	for file in $(SBIN_SCRIPTS); do $(RM_FILE) $(DESTDIR)$(SBINDIR)/$$file; done
	for file in $(LIB_FILES); do $(RM_FILE) $(DESTDIR)$(LIBDIR)/$$file; done
	$(RM_DIR) $(DESTDIR)$(LIBDIR)

uninstall_config:
	$(RM_FILE) $(DESTDIR)$(ETCDIR)/x2goserver.conf
	$(RM_FILE) $(DESTDIR)$(ETCDIR)/x2gosql/sql
	$(RM_DIR)  $(DESTDIR)$(ETCDIR)
	$(RM_DIR)  $(DESTDIR)$(ETCDIR)/x2gosql/passwords
	$(RM_DIR)  $(DESTDIR)$(ETCDIR)/x2gosql

uninstall_man:
	for file in $(BIN_SCRIPTS); do $(RM_FILE) $(DESTDIR)$(MANDIR)/man8/$$file.8.gz; done
	for file in $(SBIN_SCRIPTS); do $(RM_FILE) $(DESTDIR)$(MANDIR)/man8/$$file.8.gz; done
	$(RM_DIR)  $(DESTDIR)$(MANDIR)

uninstall_version:
	$(RM_FILE) $(DESTDIR)$(SHAREDIR)/versions/VERSION.x2goserver
	$(RM_DIR)  $(DESTDIR)$(SHAREDIR)/versions
