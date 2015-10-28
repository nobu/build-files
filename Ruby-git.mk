V := $(shell [ -t 1 ] && echo 1)
ifeq ($(if $(V),$(V),0),0)
Q = @
ECHO = :
else
Q =
ECHO = @echo
endif

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
backupopt = --dereference

all:
up: up-remote up-local .force
up-remote: fetch rebase .force
up-local: .force

fetch: .force
	$(Q) git fetch
	$(Q) $(if $(wildcard $(gitdir)/svn),git svn fetch)

#	$(Q) $(if $(wildcard $(gitdir)/svn),cp -p `find refs/remotes/origin -maxdepth 1 -type f` refs/heads/)

rebase: $(addprefix rebase-,$(branches)) .force

define rebasecmd
.PHONY: rebase-$(1)
rebase-$(1): .force
	git rebase origin$(if $(filter-out master,$(1)),/$(1)) $(1)
endef
$(foreach branch,$(branches),$(eval $(call rebasecmd,$(branch))))

branches: .force
	echo $(branches)

backup: $(backup) .force

$(backup): $(gitdir) gc
	tar $(backuparg) $(backupopt) -cjf $@ $(backupdir)

gc: .force
	du -s $(gitdir)
	git gc
	du -s $(gitdir)

.PHONY: .force fetch rebase branch backup gc
.force:
