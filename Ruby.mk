RUBYOPT =
PWD := $(shell pwd)

define cvs_srcs
$(addprefix $(1),$(shell cut -d/ -f2 $(1)CVS/Entries | grep -e '\.[chy]$$' | sort))
endef
define svn_srcs
$(subst .svn/text-base/,,$(patsubst %.svn-base,%,$(wildcard $(filter-out ./,$(dir $(1))).svn/text-base/$(call or,$(notdir $(1)),*.[chy]).svn-base)))
endef
define git_srcs
$(shell $(GIT) ls-files $(1) $(2) $(3) | grep -v '^ext/')
endef

or = $(if $(1),$(1),$(2))

CVS = cvs -f
SVN = svn
GIT = git
GIT_SVN = $(GIT) svn
svn-up = update
svn-up-options = --accept postpone
GITSVN = git svn
ifneq ($(wildcard .svn/entries),)
UPDATE_REVISION = $(VCS) info $(@D) | \
	sed -n \
	-e 's,^URL:.*/branches/\([^/]*\)$$,\#define RUBY_BRANCH_NAME "\1",p' \
	-e 's/.*Rev:/\#define RUBY_REVISION/p'

VCS = $(SVN)
SRCS := $(call svn_srcs,include/ruby/) $(call svn_srcs,*.[chy]) \
	$(call svn_srcs,*.ci) $(call svn_srcs,insns.def) \
	$(call svn_srcs,*.def) $(call svn_srcs,missing/) \
	$(call svn_srcs,enc/) $(call svn_srcs,win32/)
SRCS := $(wildcard $(SRCS))
else ifneq ($(wildcard .git),)
UPDATE_REVISION = git log -n 1 --grep='^ *git-svn-id:' $(@D) | \
	sed -e '$$!d' -e '/ *git-svn-id: */!d' -e 's///' \
	-e 's,.*/branches/\([^/]*\)@\([0-9][0-9]*\) .*,\#define RUBY_BRANCH_NAME "\1"/\#define RUBY_REVISION \2,' \
	-e 's,.*/trunk@\([0-9][0-9]*\) .*,\#define RUBY_REVISION \1,' | tr / '\012'
ORIGIN_URL := $(shell git config remote.origin.url)
ifeq ($(patsubst /%,/,$(patsubst file:%,%,$(ORIGIN_URL))),/)
UPDATE_PREREQ := update-prereq
endif

SRCS := $(call git_srcs,include/ruby/) $(call git_srcs,*.[chy])\
	$(call git_srcs,*.ci) $(call git_srcs,insns.def) \
	$(call git_srcs,*.def) $(call git_srcs,missing/) \
        $(call git_srcs,enc/) $(call git_srcs,win32/)
SRCS := $(wildcard $(SRCS))
  ifneq ($(wildcard .git/svn),)
VCS = $(GIT_SVN)
VCSUP = $(VCS) rebase $(gitsvnup-options)
#  else ifeq ($(patsubst +%,+,$(shell git config remote.origin.fetch)),+)
#GIT_ORIGIN = $(shell git config remote.origin.url)
#VCS = $(GIT)
#VCSUP = $(MAKE) -C "$(GIT_ORIGIN)" gitup-options=$(gitup-options) up
  else
VCS = $(GIT)
VCSUP = $(VCS) pull
  endif
else ifneq ($(wildcard CVS/Entries),)
VCS = $(CVS)
SRCS := $(call cvs_srcs) $(call cvs_srcs,missing/) $(call cvs_srcs,win32/)
else
SRCS := $(wildcard *.h $(filter-out parse.c,*.c) parse.y missing/*.[ch] win32/win32.[ch] win32/dir.h)
endif
TESTS ?= $(if $(wildcard .tests),$(shell cat .tests),$(EXTS))

VCSUP ?= $(VCS) $(call or,$(value $(subst  ,-,$(VCS))up),up) $(value $(subst  ,-,$(VCS))up-options)

nonexec :=
print-database :=
keep-going :=
$(foreach mflags,$(filter-out --%,$(filter -%,$(MFLAGS) $(MAKEFLAGS))),\
$(if $(filter $(subst n,,$(mflags)),$(mflags)),,$(eval nonexec := t))\
$(if $(filter $(subst p,,$(mflags)),$(mflags)),,$(eval print-database := t))\
$(if $(filter $(subst k,,$(mflags)),$(mflags)),,$(eval keep-going := t))\
)

ifeq ($(TERM),dumb)
tty :=
else
tty := $(shell sh -c "test -t 2 && echo tty")
endif

SETTITLE := $(call or,$(if $(tty),$(shell sh -c "type -p settitle"),$(shell echo ': -*- compilation -*-' 1>&2)),:)
define MESSAGE
$(if $(nonexec),,@$(SETTITLE) making $(if $(2),$(2),$@))
$(if $(nonexec),,@echo ")<=== $(1) $(if $(2),$(2),$@) ===>$(if $(nonexec),,")
endef
STARTING = $(call MESSAGE,{{{starting,$(1))
FINISHED = $(call MESSAGE,}}}finished,$(1))
CMDSTARTING = $(if $(filter $@,$(MAKECMDGOALS)),,$(call STARTING,$(1)))
CMDFINISHED = $(if $(filter $@,$(MAKECMDGOALS)),$(call FINISHED,$(1)))

ifeq ($(print-database),)
TOPMAKE = $(MAKE)
else
TOPMAKE =
endif

CMDVARS := $(filter-out subdirs=%,$(-*-command-variables-*- :=))
MFLAGS := $(if $(EXTOUT),EXTOUT=$(EXTOUT)) $(if $(RDOCOUT),RDOCOUT=$(RDOCOUT))
makeflags := $(patsubst -w%,-%,-$(filter-out --%,$(MAKEFLAGS)))
make-default = $(if $(nonexec),,$(make-precommand) $(if $(wildcard $(1)/.env),$(1)/.env -C $(1))) \
	$(MAKE) $(if $(if $(nonexec),,$(wildcard $(1)/.env)),,-C $(1))
config-default = cd $(@D); \
	sh $(if $(wildcard $@), $(shell sed -n 's/^srcdir=//p' $@),$(PWD))/$(CONFIGURE) \
	   $(if $(wildcard $@), $(shell sed -n 's/^s,@configure_args@,\(.*\),;t t$$/\1/p' $@))

nmake := $(shell which nmake 2>&1)
bcc32 := $(shell which bcc32 2>&1)
ifneq ($(nmake),)
make-mswin32 = $(if $(nonexec),,@echo $(call make-default,$(1));) cd $(1); unset MAKEFLAGS; \
	       $(strip exec $(if $(nonexec),,$(make-precommand)) ./.env nmake -l $(makeflags) $(MFLAGS))
#make-mswin32 = nmake -C"$(1)" -l $(filter-out --%,$(MAKEFLAGS)) $(MFLAGS)
configure-mswin32 = win32/Makefile.sub
config-mswin32 = cd $(@D); \
	$(if $(wildcard $@), $(shell sed -n 's/^srcdir=//p' $@),$(PWD))/win32/configure.bat
endif
ifneq ($(bcc32),)
make-bccwin32 = $(if $(nonexec),,@echo $(call make-default,$(1));) cd $(1); unset MAKEFLAGS; \
		$(strip exec $(if $(nonexec),,$(make-precommand)) ./.env make $(subst k,,$(makeflags)) $(MFLAGS))
#make-bccwin32 = bmake -C"$(1)" $(filter-out --%,$(MAKEFLAGS)) $(MFLAGS)
configure-bccwin32 = bcc32/Makefile.sub
config-bccwin32 = cd $(@D); \
	$(if $(wildcard $@), $(shell sed -n 's/^srcdir=//p' $@),$(PWD))/bcc32/configure.bat
endif
common.mk := $(wildcard common.mk)
configure-default = Makefile.in $(common.mk) $(subdir)/config.status
submake = $(strip $(call $(if $(make-$(target)),make-$(target),make-default),$(@D)) $(CMDVARS))

AUTOCONF = autoconf
RM = rm -f

ifndef subdirs
subdirs := $(wildcard */Makefile .[^.]*/Makefile)
subdirs += $(filter-out djgpp/config.status,$(wildcard */config.status .[^.]*/config.status))
else
subdirs := $(wildcard $(subdirs))
endif
subdirs := $(sort $(patsubst %/,%,$(dir $(subdirs))))
ostype = $(word 2,$(subst -, ,$1))
target = $(call ostype,$(@D))

BISON = bison
CONFIGURE_IN := $(wildcard configure.in)
CONFIGURE = $(CONFIGURE_IN:.in=)
PARSE_Y := $(wildcard parse.y)
KEYWORDS := $(call or,$(wildcard defs/keywords),$(wildcard keywords))
LEX_C := $(if $(KEYWORDS),lex.c)
RIPPER := $(if $(wildcard ext/ripper/depend),ripper)
PREREQ = .force $(CONFIGURE) $(PARSE_Y:.y=.c) $(LEX_C) revision.h .revision.time
ifndef RUBY
NATIVEARCH := $(patsubst %/Makefile,%,$(shell grep -l '^PREP *= *miniruby' $(subdirs:=/Makefile) /dev/null))
DEFAULTARCH := $(word 1, $(filter $(ARCH) .$(ARCH),$(NATIVEARCH)) $(NATIVEARCH))
MINIRUBY := $(DEFAULTARCH)/miniruby
export BASERUBY ?= /usr/bin/ruby
export RUBYLIB = .$(if $(EXTOUT),:$(EXTOUT)/common:$(EXTOUT)/$(DEFAULTARCH)):$(PWD)/lib
export RUBY := $(if $(BASERUBY),$(BASERUBY),$(if $(patsubst /%,,$(MINIRUBY)),$(PWD)/$(MINIRUBY) -I $(RUBYLIB),$(MINIRUBY)))
endif
#subdirs := $(filter-out $(DEFAULTARCH),$(subdirs)) $(DEFAULTARCH)

PAGER ?= less
ifeq ($(origin MAKEFILE_LIST),undefined)
MAKEFILE_LIST := $(wildcard GNUmakefile Makefile makefile $(MAKEFILES))
endif
EXTOUT ?= ../ext
RDOCOUT ?= $(EXTOUT)/rdoc
RBCONFIG ?= ./.rbconfig.time
export EXTOUT RDOCOUT RBCONFIG
INSTALLED_LIST ?= $(EXTOUT)/.installed.list
localgoals := $(shell sed -n '/^[A-Za-z0-9_][-A-Za-z0-9_./]*:[^=]/s/:.*//p' $(MAKEFILE_LIST))
localgoals := $(localgoals) $(shell sed -n '/^[A-Za-z0-9_][-A-Za-z0-9_./]*:$$/s/:.*//p' $(MAKEFILE_LIST))
localgoals := $(sort $(localgoals))
localgoals := $(filter-out all,$(localgoals))
goals := $(filter-out $(localgoals) $(PREREQ),$(call or,$(MAKECMDGOALS),all))
cmdgoals := $(filter-out $(subdirs:=/%),$(goals))
subdir-goals := $(filter $(subdirs:=/%),$(goals))

.pre-%:
	$(call STARTING,$*)
.post-%:
	$(call FINISHED,$*)

all:

debug:
	+$(MAKE) optflags=-O0

$(MINIRUBY): $(PREREQ) $(dir $(MINIRUBY))Makefile .pre-host-miniruby
	@$(call SETTITLE,making $(@F) in $(@D))
	+$(submake) $(if $(TOPMAKE),,TOPMAKE=$(MAKE)) $(@F)
	$(call FINISHED,host-miniruby)

#$(filter-out $(MINIRUBY),$(subdir-goals)): prereq
#	@$(call SETTITLE,making $(@F) in $(@D))
#	$(submake) $(@F)

#$(addprefix %/,$(cmdgoals)): prereq
#	@$(call SETTITLE,making $(@F) in $(@D))
#	$(submake) $(filter $(MAKECMDGOALS),$(cmdgoals))

define subdircmd
$(if $(configure-$(call ostype,$(1))),
$(1)/config.status: $(value configure-$(call ostype,$(1))) $(common.mk) $(1)/Makefile
$(1)/Makefile:;
,
$(1)/config.status: $(CONFIGURE)
$(1)/Makefile: $$(configure-default)
	cd $$(@D); $(if $(wildcard $(1)/.env),./.env) sh config.status
)

$(1)/config.status: make-precommand += time

$(1)/config.status:
	@$$(SETTITLE) making $$(@F) in $$(@D)
	-$$(submake) TOPMAKE=$(value TOPMAKE) $$(@F)

$(1)/%: prereq .force
	@$$(SETTITLE) making $$(@F) in $$(@D)
	+$$(submake) TOPMAKE=$(value TOPMAKE) $$(mflags) $$(@F)
endef
$(foreach subdir,$(subdirs),$(eval $(call subdircmd,$(subdir))))

phony-filter := TAGS builtpack% $(shell grep -e ^incs: -e ^srcs: common.mk | sed s/:.*$$//)
phony-filter += $(shell sed '/\.force$$/!d;/^[a-zA-Z][-a-zA-Z0-9]*[a-zA-Z0-9]:/!d;s/:.*//' $(MAKEFILE_LIST))
prereq-filter = prereq .pre-prereq $(PREREQ) $(RIPPER) config Makefile $(MINIRUBY) $(phony-filter)
subdir-filter = $(subdirs:=/%) $(localgoals) $(PREREQ)
$(foreach goal,all $(filter-out $(prereq-filter),$(MAKECMDGOALS)),$(eval $(value goal): prereq))
$(foreach goal,all $(filter-out $(subdirs:=/%) $(phony-filter),$(MAKECMDGOALS)),$(eval $(value goal): .pre-$(value goal)))
$(foreach goal,all $(filter-out $(subdir-filter),$(MAKECMDGOALS)),$(eval $(value goal): $$(subdirs:=/$(value goal))))
$(foreach goal,$(filter-out $(phony-filter),$(cmdgoals)),$(eval $(value goal):\; $$(FINISHED)))

prereq: .pre-prereq .do-prereq $(PREREQ) config Makefile $(RIPPER) .post-prereq
	@-sync
prereq: MAKEFLAGS += --no-print-directory

resolved:
	@PWD= resolve-conflict

#miniruby:;

Makefiles: Makefile

Makefile: .pre-Makefile $(subdirs:=/Makefile) .post-Makefile

config: .pre-config $(subdirs:=/config.status) .post-config

rbconfig: prereq .pre-rbconfig $(subdirs:=/$(RBCONFIG:./%=%)) .post-rbconfig

%.c: %.y
	+{ sed '/^@/d' Makefile.in; sed 's/{[.;]*$$([a-zA-Z0-9_]*)}//g' common.mk; } | \
	$(MAKE) -f - srcdir=. CHDIR=cd VPATH=include/ruby YACC="$(BISON) -y" YFLAGS="$(YFLAGS)" $@
	$(CMDFINISHED)

configure: configure.in
	+$(AUTOCONF)

prereq-targets := $(shell grep -e '^up:' -e '^prereq:' -e '/revision\.h:' common.mk | \
		    sed -e 's/:.*//;s/^/.do-/;s,.*/,,')
ifneq ($(prereq-targets),)
$(prereq-targets):
	@{ sed 's/@[A-Z][A-Z_0-9]*@//g' Makefile.in; sed 's/{[.;]*$$([a-zA-Z0-9_]*)}//g' common.mk; } | \
	$(MAKE) -f - srcdir=. VPATH=include/ruby MKFILES="" PREP="" WORKDIRS="" \
	CHDIR=cd MAKEDIRS='mkdir -p' BASERUBY="$(RUBY)" MINIRUBY="$(RUBY)" RUBY="$(RUBY)" RBCONFIG="" \
	ENC_MK=.top-enc.mk REVISION_FORCE=PHONY PROGRAM="" VCSUP="$(VCSUP)" VCS="$(VCS)" \
	$(filter-out prereq,$(patsubst .do-%,%,$@)) \
	$(if $(filter-out revision.h,$@),prereq)
else
.do-up:
ifeq ($(filter .do-up,$(prereq-targets)),)
	env LC_TIME=C $(VCSUP)
ifeq ($(filter revision.h,$(prereq-targets)),)
	-@$(RM) revision.h
endif
endif
endif

up: up-remote up-local
.do-up-remote: .do-up .force

up-remote: $(UPDATE_PREREQ) .do-up-remote .force

up-local: prereq .force

.do-prereq:

host-miniruby: $(MINIRUBY)

lex.c: $(KEYWORDS)

ripper_hdrdir = $(if $(wildcard include/ruby/ruby.h),top_srcdir,hdrdir)
ripper: .force
	$(CMDSTARTING)
	$(if $(TOPMAKE),$(MAKE),$(MAKE)) -C ext/ripper -f depend $(ripper_hdrdir)=../.. srcdir=. RUBY="$(RUBY)"
	$(FINISHED)

revision.h: .force

ifeq ($(filter revision.h,$(prereq-targets)),)
revision.h:
	@LC_MESSAGES=C $(UPDATE_REVISION) > "$@.tmp"
	@if test -f "$@" -a -s "$@.tmp" && diff -u "$@" "$@.tmp" > /dev/null 2>&1; then \
	    rm -f "$@.tmp"; \
	else \
	    mv -f "$@.tmp" "$@"; \
	fi
	touch .revision.time
#	@! fgrep revision.h version.h > /dev/null || $(BASERUBY) tool/revup.rb
endif

help: .force
	@$(MAKE) -f common.mk $@

update-prereq: .force
	$(MAKE) -C $(patsubst file:%,%,$(ORIGIN_URL)) up

up: .do-up revision.h .force

UP: .force
	@echo $(VCSUP) $(UPS); \
	while $(VCSUP) $(UPS) | tee makeup.log | $(PAGER) +/^C; \
	      grep ^C makeup.log; do \
	    sleep 1; \
	done; \
	rm -f makeup.log

tags: TAGS .force

TAGS: $(SRCS)
	etags -lc $(wildcard $(patsubst template/%.tmpl,%,$(SRCS)))

sudo-install:
ifneq ($(wildcard $(EXTOUT)),)
	sudo $(MAKE) prereq-targets= install
endif

install-prereq: .force
	@exit > $(INSTALLED_LIST)
#	@MAKE=$(MAKE) touch install-prereq
#	@rm -f install-prereq

install: install-nodoc
install-nodoc: install-comm install-arch
install-arch install-comm: mflags := \
	INSTALLED_LIST='$(EXTOUT)/.installed.list' \
	CLEAR_INSTALLED_LIST=PHONY

install-arch install-comm:
install-arch: install-prereq $(subdirs:=/install-arch)
install-comm: install-prereq $(DEFAULTARCH)/install-comm
install-local: install-bin install-lib install-man
install-bin: install-prereq $(subdirs:=/install-bin)
install-lib: install-prereq $(DEFAULTARCH)/install-lib
install-man: install-prereq $(DEFAULTARCH)/install-man
install-ext: install-ext-arch install-ext-comm
install-ext-arch: install-prereq $(subdirs:=/install-ext-arch)
install-ext-comm: install-prereq $(DEFAULTARCH)/install-lib
install-doc: $(DEFAULTARCH)/install-doc
install-rdoc: $(DEFAULTARCH)/install-rdoc

pre-install-local: $(subdirs:=/pre-install-local)
post-install-local: $(subdirs:=/post-install-local)
pre-install-ext: $(subdirs:=/pre-install-ext)
post-install-ext: $(subdirs:=/post-install-ext)

check: prereq .pre-check test test-all .post-check .force
test: prereq .pre-test $(subdirs:=/test) .post-test .force
test-all: prereq .pre-test-all $(subdirs:=/test-all) .post-test-all .force
test test-all:; sync
try: $(DEFAULTARCH)/miniruby try.rb
	$(DEFAULTARCH)/miniruby try.rb

ifeq ($(tty),)
oneline = echo "$(2)"; exec $(1)
else
oneline = exec $(1) 2>&1 | oneline -p"$(2): " -e"$(3)"
endif
transsrcs := $(addprefix src/,$(filter-out enc/trans/transdb.c,$(wildcard enc/trans/*.c)))
builttargets := $(addprefix builtpack-,$(subdirs))
builtpack: .pre-builtpack builtpack-common $(builttargets) .post-builtpack
#builtdirs := $(notdir $(foreach d,$(subdirs),$(shell readlink $(value d))))
#$(addprefix builtpack-,common $(builtdirs))::; @echo $(patsubst builtpack-%,packing %,$@)
builtpack-%: dir = $(patsubst builtpack-.%,.%,$@)
builtpack-%: real = $(notdir $(shell readlink $(dir)))
builtpack-%: arch = $(shell sed -n '/CONFIG\["arch"\]/s/.*= "\(.*\)"$$/\1/p' "$(dir)/rbconfig.rb")
builtpack-common:
	@$(call oneline,tar -C .. -c$(if $(tty),v)jf ../built-common.tar.bz2 \
	$(transsrcs) ext/common/ $(patsubst ../%,%,$(wildcard $(RDOCOUT))) \
	ext/include/ruby,packing common,done)
$(builttargets):
	@$(if $(arch),\
	$(call oneline,tar -C .. -c$(if $(tty),v)jf ../built-$(real).tar.bz2 ext/$(arch) ext/include/$(arch) \
	$(real),packing $(dir),done),\
	echo '$(dir) is not built')

.PHONY: .force
.force:

