inside-work-tree := $(git rev-parse --is-inside-work-tree)
ifeq ($(inside-work-tree),true)
branches := $(shell git branch -l | sort | sed 's/\*//')
gitdir = .git
backupdir = $(gitdir)
backup = git.tar.bz2
backuparg =
else
gitdir = .
backupdir := $(notdir $(shell pwd))
backup = ../$(backupdir).tar.bz2
backuparg = -C ..
endif

all: up backup
up: fetch rebase

fetch:
	git fetch
	$(if $(wildcard $(gitdir)/svn),git svn fetch)

rebase: $(addprefix rebase-,$(branches))

define rebasecmd
rebase-$(1):
	git rebase origin$(if $(filter-out master,$(1)),/$(1)) $(1)
endef
$(foreach branch,$(branches),$(eval $(call rebasecmd,$(branch))))

branches:; echo $(branches)

backup: $(backup)

$(backup): $(gitdir) gc
	tar $(backuparg) -cjf $@ $(backupdir)

gc:
	du -s $(gitdir)
	git gc --prune
	du -s $(gitdir)
