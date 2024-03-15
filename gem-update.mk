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

highlight := $(subst 33,93,$(shell tput setaf 3))
reset := $(subst 93,,$(highlight))
doing = @echo $(highlight)$(@D)$(reset)

srcdirs := $(dir $(wildcard */.git))

master = $(shell $(GIT) -C $(1) for-each-ref --count=1 '--format=%(refname:short)' refs/heads/master refs/heads/main)

%/.status.:
	@$(GIT) -C $(@D) status --porcelain 2>&1 | sed 's|^|$(@D): |'

%/.fetch.:
	@$(doing)
	@$(GIT) -C $(@D) fetch 2>&1 | sed 's|^|$(@D): |'

%/.master.:
	@$(GIT) -C $(@D) checkout $(call master,$(@D)) 2>&1 | \
	sed '/^Your branch is up to date/d;/^Already on /d;s|^|$(@D): |'

%/.update.: %/.master.
	@$(GIT) -C $(@D) rebase 2>&1 | sed '/ up to date\.$$/d;s|^|$(@D): |'

%/.reset.: %/.master.
	@$(GIT) -C $(@D) reset --hard 2>&1 | sed 's|^|$(@D): |'

%/.drypurge.:
	@MAKE='$(MAKE)' $(GIT) -C $(@D) clean -dfxn $(purge-opts) 2>&1 | \
	sed 's!^\(Would remove\|Removing\) !&$(@D)/!'

%/.purge.:
	@MAKE='$(MAKE)' $(GIT) -C $(@D) clean -dfx$(nonexec) $(purge-opts) 2>&1 | \
	sed 's!^\(Would remove\|Removing\) !&$(@D)/!'

%/.checkout.:
	@MAKE='$(MAKE)' $(GIT) -C $(@D) checkout -f 2>&1 | sed 's|^|$(@D): |'

ops := $(shell sed -n 's|^%/\.\(.*\)\.:.*|\1|p' $(MAKEFILE_LIST))

max-sessions = 6
ifeq ($(intcmp $(max-sessions),$(subst -j,,$(filter -j%,$(MFLAGS))),gt),gt)
ops := $(filter-out fetch,$(ops))
fetch: MFLAGS := $(filter-out -j% --jobserver-%,$(MFLAGS))
fetch: MAKEFLAGS := $(filter-out -j% --jobserver-%,$(MAKEFLAGS))
fetch:
	@$(MAKE) -s $(MFLAGS) highlight='$(highlight)' reset='$(reset)' -j$(max-sessions) fetch

#	@for dir in $(srcdirs); do echo $$'\e[93m'$$dir$$'\e[m'; $(GIT) -C $$dir fetch 2>&1 | sed "s|^|$$dir: |"; done
endif

$(foreach op,$(ops),\
$(eval $(value op): $$(addsuffix .$(value op).,$$(srcdirs)))\
)

dry-purge: drypurge
up: fetch .WAIT master .WAIT update

.PHONEY: $(foreach op,$(ops),$(addsuffix .$(op).,$(srcdirs)))
