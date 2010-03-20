versions := *
override versions := $(patsubst %/,%,$(dir $(wildcard $(addsuffix /GNUmakefile,$(versions)) $(addsuffix /src/GNUmakefile,$(versions)))))
goals := all $(filter-out %/all $(shell sed '/^[a-zA-Z_][-a-zA-Z0-9_]*:/!d;s/:.*//;s:.*:& %/&:' $(MAKEFILE_LIST)),$(MAKECMDGOALS))
unexport versions goals

define dive
$(MAKE) -C $(@D) $(if $(filter --,$(MAKEFLAGS))$(filter $(firstword $(MAKEFLAGS)),$(subst =,,$(firstword $(MAKEFLAGS)))),-)$(MAKEFLAGS) $(@F)
endef
define no-need-install
! { [ -e $(@D)/miniruby ] && $(@D)/miniruby -e 'exit RUBY_REVISION > `ruby-#{RUBY_VERSION} -e "p RUBY_REVISION"`.to_i'; }
endef

$(foreach goal,$(goals),$(eval $(value goal): $$(versions:=/$(value goal))))
$(foreach subdir,$(versions),$(eval $(value subdir)/%:; $$(call dive)))

up: $(addsuffix /up,$(versions))
	$(if $(wildcard .svn),svn up)
#$(foreach subdir,$(versions),$(eval $(value subdir)/up:; svn up --accept postpone $$(@D)))
$(foreach subdir,$(versions),$(eval $(value subdir)/up:; +$(MAKE) -$(MAKEFLAGS) -C $$(@D) UPDATE_PREREQ= up))

resolved:
	@PWD= resolve-conflict $(versions)

stat:
	! svn $@ $(versions) | grep '^C'

edit:
	$(EDITOR) `svn stat $(versions) | sed -n 's/^C//p'`

sudo-install: stable/sudo-install trunk/sudo-install
stable/sudo-install trunk/sudo-install:
	@$(call no-need-install) || $(call dive)
