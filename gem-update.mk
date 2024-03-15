#!/bin/sh
_=; exec ${MAKE-make} -s -C "${0%/*}" -f "${0##*/}" "$@"

GIT := $(if $(shell command -v git 2>&-),git)
nonexec :=
print-database :=
keep-going :=
$(foreach mflags,$(filter-out --%,$(filter -%,$(MFLAGS) $(MAKEFLAGS))),\
$(if $(findstring n,$(mflags)),$(eval nonexec := n))\
$(if $(findstring p,$(mflags)),$(eval print-database := p))\
$(if $(findstring k,$(mflags)),$(eval keep-going := k))\
)

srcdirs := $(dir $(wildcard */.git))

master = $(shell $(GIT) -C $(1) for-each-ref --count=1 '--format=%(refname:short)' refs/heads/master refs/heads/main)

%/.status.:
	@$(GIT) -C $(@D) status --porcelain | sed 's|^|$(@D): |'

%/.fetch.: .WAIT
	@$(GIT) -C $(@D) fetch | sed 's|^|$(@D): |'

%/.master.:
	@$(GIT) -C $(@D) checkout $(call master,$(@D)) 2>&1 | \
	sed '/^Your branch is up to date/d;/^Already on /d;s|^|$(@D): |'

%/.update.: %/.master.
	@$(GIT) -C $(@D) rebase | sed 's|^|$(@D): |'

%/.drypurge.:
	@MAKE='$(MAKE)' $(GIT) -C $(@D) clean -dfxn $(purge-opts) | \
	sed 's!^\(Would remove\|Removing\) !&$(@D)/!'

%/.purge.:
	@MAKE='$(MAKE)' $(GIT) -C $(@D) clean -dfx$(nonexec) $(purge-opts) | \
	sed 's!^\(Would remove\|Removing\) !&$(@D)/!'

%/.checkout.:
	@MAKE='$(MAKE)' $(GIT) -C $(@D) checkout -f |& sed 's|^|$(@D): |'

ops := $(shell sed -n 's|^%/\.\(.*\)\.:.*|\1|p' $(MAKEFILE_LIST))

$(foreach op,$(ops),\
$(eval $(value op): $$(addsuffix .$(value op).,$$(srcdirs)))\
)

dry-purge: drypurge

.PHONEY: $(foreach op,$(ops),$(addsuffix .$(op).,$(srcdirs)))
