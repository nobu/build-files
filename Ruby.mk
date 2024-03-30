RUBYOPT =
PWD := $(shell pwd)

ifneq ($(filter notintermediate,$(.FEATURES)),)
DOT_WAIT = .WAIT
endif

ifneq ($(wildcard src/Makefile.in),)
srcdir = src
srcdir_prefix = src/
Makefile.in = src/Makefile.in
else
srcdir_prefix := $(dir $(wildcard src/ruby.c))
srcdir := $(if $(srcdir_prefix),$(patsubst %/,%,$(srcdir_prefix)),.)
Makefile.in = $(firstword $(wildcard template/Makefile.in Makefile.in))
endif
in-srcdir := $(if $(srcdir_prefix),cd $(srcdir) &&)

define cvs_srcs
$(addprefix $(srcdir_prefix)$(1),$(shell cut -d/ -f2 $(srcdir_prefix)$(1)CVS/Entries | grep '\.[chy]$$' | sort))
endef
define svn_srcs
$(subst .svn/text-base/,,$(patsubst %.svn-base,%,$(wildcard $(filter-out ./,$(dir $(srcdir_prefix)$(1))).svn/text-base/$(call or,$(notdir $(1)),*.[chy]).svn-base)))
endef
define git_srcs
$(shell $(in-srcdir) $(GIT) ls-files $(1) $(2) $(3) | grep -v -e '^ext/' -e '^test/' -e '^spec/')
endef

V = 0
ifeq ($(V),0)
export ECHO = @echo
export Q = @
else
export ECHO = @:
export Q =
endif

or = $(if $(1),$(1),$(2))

CVS := $(if $(shell command -v cvs 2>&-),cvs -f)
SVN := $(if $(shell command -v svn 2>&-),svn)
GIT := $(if $(shell command -v git 2>&-),git)
GIT_SVN := $(if $(GIT),$(GIT) -C $(srcdir) svn)
svn-up = update
svn-up-options = --accept postpone
git-up = pull --no-edit --rebase
ifneq ($(and $(SVN),$(wildcard $(srcdir)/.svn/entries)),)
UPDATE_REVISION = cd $(srcdir) && $(VCS) info $(@D) | \
	sed -n \
	-e 's,^URL:.*/branches/\([^/]*\)$$,\#define RUBY_BRANCH_NAME "\1",p' \
	-e 's/.*Rev:/\#define RUBY_REVISION/p'

VCS = $(SVN)
VCSRESET = $(VCS) revert $(srcdir)
SRCS := $(call svn_srcs,include/ruby/) $(call svn_srcs,*.[chy]) \
	$(call svn_srcs,*.ci) $(call svn_srcs,insns.def) \
	$(call svn_srcs,*.def) $(call svn_srcs,ccan) \
	$(call svn_srcs,missing/) \
	$(call svn_srcs,enc/) $(call svn_srcs,win32/)
SRCS := $(wildcard $(SRCS))
else ifneq ($(and $(GIT),$(wildcard $(srcdir)/.git)),)
ORIGIN_URL := $(shell $(in-srcdir) git config remote.origin.url)
ifeq ($(patsubst /%,/,$(patsubst file:%,%,$(ORIGIN_URL))),/)
UPDATE_PREREQ_LOCAL := update-prereq-local
UPDATE_PREREQ := update-prereq
endif

SRCS := $(call git_srcs,include/ruby/) $(call git_srcs,*.[cy]) \
	$(call git_srcs,*.ci *.inc) \
	$(call git_srcs,*.def) $(call git_srcs,ccan) \
	$(call git_srcs,missing/ internal/ template/) \
	$(call git_srcs,enc/) $(call git_srcs,win32/) \
	$(call git_srcs,*.h) \
	$(addprefix prism/,$(notdir $(patsubst %.erb,%,$(call git_srcs,'prism/templates/*.[ch].erb')))) \
	$(call git_srcs,prism/util/*.[ch]) \
	$(empty)
SRCS := $(wildcard $(SRCS))
RBSRCS := $(call git_srcs,*.rb) \
	$(patsubst prism/templates/%.erb,%,$(call git_srcs,'prism/templates/*.rb.erb')) \
	$(empty)
  ifneq ($(if $(wildcard .git/svn),$(shell test -L .git/svn || echo .git/svn)),)
VCS = $(GIT_SVN)
VCSUP = $(VCS) rebase $(gitsvnup-options)
VCSCOMMIT = $(VCS) svn dcommit
UPDATE_REVISION = $(in-srcdir) git log -n 1 --grep='^ *git-svn-id:' $(@D) | \
	sed -e '$$!d' -e '/ *git-svn-id: */!d' -e 's///' \
	-e 's,.*/branches/\([^/]*\)@\([0-9][0-9]*\) .*,\#define RUBY_BRANCH_NAME "\1"/\#define RUBY_REVISION \2,' \
	-e 's,.*/trunk@\([0-9][0-9]*\) .*,\#define RUBY_REVISION \1,' | tr / '\012'
before-up := $(shell git status --porcelain | sed '/^?/d;s/.*/stash-save/;q')
after-up := $(before-up:-save=-pop)
#  else ifeq ($(patsubst +%,+,$(shell git config remote.origin.fetch)),+)
#GIT_ORIGIN = $(shell git config remote.origin.url)
#VCS = $(GIT)
#VCSUP = $(MAKE) -C "$(GIT_ORIGIN)" gitup-options=$(gitup-options) up
  else
VCS = $(GIT)
VCSUP = $(VCS) -C $(srcdir) $(git-up)
    ifneq ($(wildcard .git/svn),)
POST_UP1 = $(GIT) -C $(srcdir) $(git-up)
POST_UP2 = $(GIT_SVN) rebase
    endif
VCSCOMMIT = $(VCS) push
  endif
VCSRESET = $(GIT) -C $(srcdir) checkout -f
UPDATE_REVISION = $(BASERUBY) -C $(srcdir) tool/file2lastrev.rb -q --revision.h
else ifneq ($(and $(CVS),$(wildcard $(srcdir)/CVS/Entries)),)
VCS = $(CVS)
SRCS := $(call cvs_srcs) $(call cvs_srcs,missing/) $(call cvs_srcs,win32/)
else
SRCS := $(wildcard $(srcdir_prefix)*.h $(filter-out $(srcdir_prefix)parse.c,$(srcdir_prefix)*.c) $(srcdir_prefix)parse.y $(srcdir_prefix)missing/*.[ch] $(srcdir_prefix)win32/win32.[ch] $(srcdir_prefix)win32/dir.h $(srcdir_prefix)prism/*.[ch] $(srcdir_prefix)prism/util/*.[ch])
endif
ifeq ($(if $(VCS),$(shell command -v $(firstword $(VCS)) 2>/dev/null),none),)
VCS :=
endif

TESTS ?= $(if $(wildcard .tests),$(shell cat .tests),$(EXTS))

VCSUP ?= $(VCS) $(call or,$(value $(subst  ,-,$(VCS))up),up) $(value $(subst  ,-,$(VCS))up-options)
before-up ?=
after-up ?=

nonexec :=
print-database :=
keep-going :=
$(foreach mflags,$(filter-out --%,$(filter -%,$(MFLAGS) $(MAKEFLAGS))),\
$(if $(findstring n,$(mflags)),$(eval nonexec := t))\
$(if $(findstring p,$(mflags)),$(eval print-database := t))\
$(if $(findstring k,$(mflags)),$(eval keep-going := t))\
)

RUBY_PROGRAM_VERSION := $(shell sed -n 's/^\#define RUBY_VERSION "\([0-9][.0-9]*\)"/\1/p' $(srcdir_prefix)version.h /dev/null)
MAJOR := $(word 1,$(subst ., ,$(RUBY_PROGRAM_VERSION)))
MINOR := $(word 2,$(subst ., ,$(RUBY_PROGRAM_VERSION)))

ifeq ($(TERM),dumb)
tty :=
else
tty := $(shell sh -c "test -t 2 && echo tty")
endif

SETTITLE := $(if $(tty),$(shell command -v settitle 2>&-))
ifeq ($(SETTITLE),)
SETTITLE := echo ": -*- compilation -*-"
ENDTITLE :=
else
ENDTITLE := && $(SETTITLE)
endif
define MESSAGE
$(if $(nonexec),,@$(SETTITLE) making $(if $(2),$(2),$@))
$(if $(nonexec),,@echo ")<=== $(1) $(if $(2),$(2),$@) ===>$(if $(nonexec),,")
endef
STARTING = $(call MESSAGE,{{{starting,$(1))
FINISHED = $(call MESSAGE,}}}finished,$(1))$(ENDTITLE)
MAKECMDGOALS := $(patsubst q,prereq,$(MAKECMDGOALS))
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
make-default = $(if $(nonexec),,$(make-precommand)) \
	$(MAKE) -C $(1)
config-default = cd $(@D); \
	sh $(if $(wildcard $@), $(shell sed -n 's/^srcdir=//p' $@),$(PWD))/$(CONFIGURE) \
	   $(if $(wildcard $@), $(shell sed -n 's/^s,@configure_args@,\(.*\),;t t$$/\1/p' $@))

nmake := $(shell command -v nmake 2>&-)
bcc32 := $(shell command -v bcc32 2>&-)
ifneq ($(nmake),)
make-mswin32 = cd "$(1)" && \
	$(basename $(firstword $(wildcard "$(1)/.run.cmd" "$(1)/run.cmd"))) nmake -l \
	$(if $(filter-out %=% -%,$(firstword $(MAKEFLAGS))),-)$(filter-out subdirs=% -j% --%,$(MAKEFLAGS))
configure-mswin32 = $(srcdir_prefix)win32/Makefile.sub
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
common.mk := $(wildcard $(srcdir_prefix)common.mk)
ifeq ($(common.mk),)
common.mk := $(wildcard defs/common.mk)
endif
ifeq ($(common.mk),)
common.mk := $(wildcard common.mk)
endif
configure-default = $(Makefile.in) $(common.mk) $(subdir)/config.status
submake = $(strip $(call $(if $(make-$(target)),make-$(target),make-default),$(@D)) $(CMDVARS))

AUTOCONF = autoconf
RM = rm -f

ifndef subdirs
subdirs := $(wildcard */Makefile .[^.]*/Makefile)
subdirs += $(if $(subdirs),,$(wildcard .*-*/Makefile))
subdirs += $(filter-out djgpp/config.status,$(wildcard */config.status .[^.]*/config.status))
else
subdirs := $(wildcard $(subdirs))
endif
subdirs := $(sort $(patsubst %/,%,$(dir $(subdirs))))
ostype = $(word 2,$(subst ., ,$(subst _, ,$(subst -, ,$1))))
target = $(call ostype,$(@D))

BISON := $(wildcard tool/lrama/exe/lrama)
ifeq ($(BISON),)
BISON = bison
else
BISON := $(BASERUBY) $(PWD)/$(BISON)
endif
CONFIGURE_IN := $(firstword $(wildcard $(srcdir_prefix)configure.ac $(srcdir_prefix)configure.in))
CONFIGURE = $(CONFIGURE_IN:.in=)
PARSE_Y := $(wildcard $(srcdir_prefix)parse.y)
KEYWORDS := $(call or,$(wildcard $(srcdir_prefix)defs/keywords),$(wildcard $(srcdir_prefix)keywords))
LEX_C := $(if $(KEYWORDS),$(srcdir_prefix)lex.c)
ID_H := $(if $(shell grep '/^id\.h:/' $(common.mk)),$(srcdir_prefix)$(ID_H))
RIPPER := $(notdir $(dir $(wildcard $(srcdir_prefix)ext/ripper/depend)))
PREREQ = .force $(CONFIGURE) $(PARSE_Y:.y=.c) $(LEX_C) $(ID_H) revision.h .revision.time
ifndef RUBY
NATIVEARCH := $(patsubst %/Makefile,%,$(shell grep -l '^PREP *= *miniruby' $(subdirs:=/Makefile) /dev/null))
DEFAULTARCH := $(word 1, $(filter $(ARCH) .$(ARCH),$(NATIVEARCH)) $(NATIVEARCH))
MINIRUBY := $(DEFAULTARCH)/miniruby
ORIG_RUBYLIB := $(RUBYLIB)
export BASERUBY ?= ruby$(shell sed '/.* BASERUBY must be[^0-9.]*/!d;s///;s/ .*//;s/\.$$//;s/\.0$$//;q' $(CONFIGURE_IN) $(wildcard tool/missing-baseruby.bat))
export RUBYLIB = .$(if $(EXTOUT),:$(EXTOUT)/common:$(EXTOUT)/$(DEFAULTARCH)):$(PWD)/lib
export RUBY := $(if $(BASERUBY),$(BASERUBY),$(if $(patsubst /%,,$(MINIRUBY)),$(PWD)/$(MINIRUBY) -I $(RUBYLIB),$(MINIRUBY)))
endif
#subdirs := $(filter-out $(DEFAULTARCH),$(subdirs)) $(DEFAULTARCH)

PAGER ?= less
MAKEFILE_LIST := $(sort $(wildcard $(MAKEFILE_LIST) GNUmakefile Makefile makefile $(Makefile.in) $(common.mk) $(MAKEFILES)))
EXTOUT ?= $(if $(filter .,$(srcdir)),../ext,.ext)
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

.pre-%/%:
	$(call STARTING,$*)
.pre-%:
	$(call STARTING,$*)
.post-%:
	$(call FINISHED,$*)
.post-%/%:
	$(call FINISHED,$*)

all:

debug:
	+$(MAKE) optflags=-O0

q: prereq

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
	+cd $$(@D) && exec sh config.status
)

# $(1)/config.status: make-precommand += time

$(1)/config.status:
	@$$(SETTITLE) making $$(@F) in $$(@D)
	-RUBY= $$(submake) TOPMAKE=$(value TOPMAKE) $$(@F)

$(1)/%: prereq .force
	@$$(SETTITLE) making $$(@F) in $$(@D)
	+$$(submake) TOPMAKE=$(value TOPMAKE) $$(mflags) $$(@F)

$(1)/inst: .force
	@{ \
	  echo include GNUmakefile; \
	  echo 'install-everything: clean-docs install; $$$$(CP) $$$$(INSTALLED_LIST) $$$$(DESTDIR)/'; \
	  echo 'install: clean-destdir'; \
	  echo 'clean-destdir:; -$$$$(Q) $$$$(RMALL) $$$$(DESTDIR)/'; \
	} | \
	$$(MAKE) -C $$(@D) -f - prereq-targets= install-everything INSTRUBY_OPTS='--install=dbg --debug-symbols=dSYM'
endef
$(foreach subdir,$(subdirs),$(eval $(call subdircmd,$(subdir))))

phony-targets = all main prog
phony-filter := TAGS builtpack% $(if $(common.mk),$(shell sed -n '/^incs:/s/:.*$$//p;/^srcs:/s/:.*$$//p;/^change/s/:.*$$//p' $(common.mk)))
phony-filter += $(shell sed '/\.force$$/!d;/^[a-zA-Z][-a-zA-Z0-9]*[a-zA-Z0-9]:/!d;s/:.*//' $(MAKEFILE_LIST))
phony-filter += $(shell sed -n 's/^\.PHONY://p' $(MAKEFILE_LIST))
phony-filter := $(sort $(phony-filter))
prereq-filter = prereq .pre-prereq $(PREREQ) $(RIPPER) config Makefile $(MINIRUBY) $(phony-filter)
subdir-filter = $(subdirs:=/%) $(localgoals) $(PREREQ)
$(foreach goal,$(phony-targets) $(filter-out $(prereq-filter),$(MAKECMDGOALS)),$(eval $(value goal): prereq))
$(foreach goal,$(phony-targets) $(filter-out $(subdirs:=/%) $(phony-filter),$(MAKECMDGOALS)),$(eval $(value goal): .pre-$(value goal)))
$(foreach goal,$(phony-targets) $(filter-out $(subdir-filter) $(phony-filter),$(MAKECMDGOALS)),$(eval $(value goal): $$(subdirs:=/$(value goal))))
$(foreach goal,$(sort $(phony-targets) $(filter-out $(phony-filter),$(cmdgoals))),$(eval $(value goal):\; $$(call FINISHED,$(value goal))))

none:
.PHONY: none

# prereq: clean-revision.time
clean-revision.time:
	$(RM) .revision.time

prereq: .post-prereq

.post-prereq: .do-prereq $(RIPPER)

Makefile: $(PREREQ)

resolved:
	@PWD= resolve-conflict

#miniruby:;

Makefiles: Makefile

Makefile: .pre-Makefile .post-Makefile
$(subdirs:=/Makefile): .pre-Makefile
.post-Makefile: $(subdirs:=/Makefile)

.pre-Makefile: config

config: .pre-config .post-config
reconfig: .pre-config .post-reconfig

.pre-config: prereq
.post-config: .pre-config
.post-reconfig: $(subdirs:=/reconfig)
config.status: $(subdirs:=/config.status)
$(subdirs:=/config.status): .post-config

rbconfig: $(if $(VCS),prereq) .pre-rbconfig $(subdirs:=/$(RBCONFIG:./%=%)) .post-rbconfig

%.c: %.y
	+{ \
	  sed '/^@/d' $(Makefile.in); \
	  $(if $(common.mk),sed 's/{[.;]*$$([a-zA-Z0-9_]*)}//g' $(common.mk);) \
	} | \
	$(MAKE) -f - srcdir=$(srcdir) CHDIR=cd VPATH=include/ruby BISON="$(BISON)" YACC="$(BISON) -y" YFLAGS="$(YFLAGS)" \
		CPP="$(CPP)" COUTFLAG=-o NULLCMD=: V=1 $@
	$(CMDFINISHED)

$(srcdir_prefix)configure: $(CONFIGURE_IN)
	+$(AUTOCONF)

prereq-targets := $(if $(common.mk),$(shell sed \
		    -e 's/^\$$(DOT_WAIT)//' \
		    -e '/^incs:/ba' -e '/^srcs:/ba' -e '/^prereq:/ba' -e '/\/revision\.h:/ba' -e '/^change:/ba' -e d \
		    -e :a -e 's/:.*//;s/^/.do-/;s,.*/,,' $(common.mk)) \
		    $(shell sed -n '/^update-[a-z][a-z]*:/s/:.*//p' $(Makefile.in)))
prereq-targets := $(sort $(prereq-targets))
# prereq-targets := $(subst revision.h,$(srcdir_prefix)revision.h,$(prereq-targets))
prereq-targets := $(filter-out revision.h $(srcdir_prefix)revision.h,$(prereq-targets))

ifneq ($(VCS),)
ifneq ($(prereq-targets),)
$(foreach target,$(prereq-targets),$(if $(filter .do-%,$(target)),$(eval $(patsubst .do-%,%,$(value target)):$(value target))))

prereq.status := $(wildcard $(srcdir_prefix)tool/prereq.status)
$(prereq-targets):
	$(if $(wildcard revision.h),,$(RM) .revision.time)
	$(Q)+ touch $(srcdir)/.top-enc.mk $(srcdir)/noarch-fake.rb 2>/dev/null || true
	$(Q) $(if $(prereq.status), \
	sed -f $(prereq.status) $(wildcard $(srcdir_prefix)defs/gmake.mk) $(Makefile.in) $(common.mk),\
	{ \
	  sed 's/^@.*@$$//;s/@[A-Z][A-Z_0-9]*@//g' $(wildcard $(srcdir_prefix)defs/gmake.mk) $(Makefile.in); \
	  $(if $(common.mk),sed 's/{[.;]*$$([a-zA-Z0-9_]*)}//g' $(common.mk);) \
	}) | \
	$(MAKE) -C $(srcdir) -f - srcdir=. top_srcdir=. VPATH=include/ruby MKFILES="" PREP="" WORKDIRS="" \
	CHDIR=cd MAKEDIRS='mkdir -p' HAVE_BASERUBY=yes \
	BOOTSTRAPRUBY="$(RUBY)" BASERUBY="$(RUBY)" MINIRUBY="$(RUBY)" RUBY="$(RUBY)" RBCONFIG="" \
	ENC_MK=.top-enc.mk REVISION_FORCE=PHONY PROGRAM="" BISON="$(BISON)" \
	VCSUP="$(VCSUP)" VCS="$(VCS)" BOOTSTRAPRUBY_COMMAND="$(RUBY)" \
	PATH_SEPARATOR=: CROSS_COMPILING=no ECHO=$(ECHO) Q=$(Q) MAJOR=$(MAJOR) MINOR=$(MINOR) \
	DOT_WAIT=$(DOT_WAIT) CONFIGURE=configure -orevision.h \
	$(filter-out prereq,$(patsubst .do-%,%,$@)) \
	$(if $(filter-out $(srcdir_prefix)revision.h,$@),$(srcdir_prefix).revision.time prereq)
	$(Q) $(RM) $(srcdir)/.top-enc.mk $(srcdir)/noarch-fake.rb
endif

PULL_REQUEST_HEADS = 'refs/remotes/github/pull/*/head'
GIT_LATEST_HEAD = git -C $(srcdir) for-each-ref --sort=-version:refname --format='%(refname:short)'

prev-head:
	$(if $(filter git,$(VCS)),$(eval prev_head := $(shell git -C $(srcdir) log -1 --format=%H HEAD)))
	$(if $(prev_head),@ echo HEAD = $(prev_head))

latest-pr = $(patsubst github/pull/%/head,%,$(shell $(GIT_LATEST_HEAD) --count=1 $(PULL_REQUEST_HEADS)))

last-pr:
	$(eval last_pr := $(call latest-pr))
	$(if $(last_pr),,\
		$(eval PULL_REQUEST_HEADS := $(subst ?/,/,$(PULL_REQUEST_HEADS))) \
		$(eval last_pr := $(call latest-pr)))
	$(if $(last_pr),@echo LAST-PR = $(last_pr))

GIT_LOG_EXCLUDES = test/prism/ test/yarp/

.do-up: $(before-up) prev-head last-pr
	$(call or,$(in-srcdir),env) LC_TIME=C $(VCSUP)
	@if git log -1 --format=%B FETCH_HEAD | grep -q -F '[ci skip]' || \
	    git log -1 --format=%s FETCH_HEAD | grep -q '^\[DOC\]'; \
	then \
	    upstream=`git for-each-ref --format='%(upstream:short)' --points-at=FETCH_HEAD | grep ^origin/`; \
	    case "$$upstream" in \
	    origin/*) git push all "$$upstream:$${upstream#origin/}"; \
	    esac; \
	fi
	git -C $(srcdir) fetch usual
	$(if $(POST_UP1),-$(call or,$(in-srcdir),env) LC_TIME=C $(POST_UP1))
	$(if $(POST_UP2),-$(call or,$(in-srcdir),env) LC_TIME=C $(POST_UP2))
	$(if $(filter $(srcdir_prefix)revision.h,$(prereq-targets)),,-@$(RM) $(srcdir_prefix)revision.h)
	@ rm -f $(srcdir_prefix)ChangeLog.orig $(srcdir_prefix)changelog.tmp
	$(if $(if $(filter git,$(VCS)),$(prev_head)),git -C $(srcdir) log -p --reverse \
		--perl-regexp --author='^(?!dependabot)' \
		$(prev_head)..HEAD -- $(addprefix ':(exclude)',$(GIT_LOG_EXCLUDES)))
	$(call new-pr,$(last_pr)..)

new-pr:
	$(call new-pr,$(call or,$(PR),$(call latest-pr)))

define new-pr
	env RUBYLIB=$(ORIG_RUBYLIB) git -C $(srcdir) view-pullrequest $(1)
endef

stash-save:
	$(in-srcdir) $(GIT) stash save
stash-pop:
	$(in-srcdir) $(GIT) stash pop

up: up-remote update-rubyspec up-local .force
$(if $(after-up),$(after-up),.do-up-remote): .do-up
.do-up-remote: $(before-up) .do-up $(after-up) .post-prereq .force

up-remote: $(UPDATE_PREREQ_LOCAL) .do-up-remote .force
update-rubyspec: prereq

ifneq ($(UPDATE_PREREQ_LOCAL),)
up-local: .do-up-remote
endif
up-local: prereq .force
endif

.do-prereq: .pre-prereq
.pre-prereq: $(if $(filter up,$(MAKECMDGOALS)),.do-up)

host-miniruby: $(MINIRUBY)

lex.c: $(KEYWORDS)

ripper: $($(filter .do-srcs,$(prereq-targets)),ripper_srcs,.do-prereq)

ripper_hdrdir = $(if $(wildcard $(srcdir_prefix)include/ruby/ruby.h),top_srcdir,hdrdir)
ripper_srcs: .force
	$(CMDSTARTING)
	$(MAKE) -C $(srcdir_prefix)ext/ripper -f depend \
		Q=$(Q) ECHO=$(ECHO) $(ripper_hdrdir)=../.. VPATH=../.. srcdir=. \
		RUBY="$(RUBY)" PATH_SEPARATOR=:
	$(FINISHED)

revision.h: .force
.revision.time: .force

#ifeq ($(filter $(srcdir_prefix)revision.h,$(prereq-targets)),)
$(srcdir_prefix)revision.h:
	@{ RUBYLIB="$ORIG_RUBYLIB" LC_MESSAGES=C $(UPDATE_REVISION); } > "$@.tmp"
	@if test -f "$@" -a -s "$@.tmp" && diff -u "$@" "$@.tmp" > /dev/null 2>&1; then \
	    rm -f "$@.tmp"; \
	else \
	    mv -f "$@.tmp" "$@"; \
	fi
	touch .revision.time
#	@! fgrep revision.h version.h > /dev/null || $(BASERUBY) tool/revup.rb
#endif

help: .force
	@$(MAKE) -f common.mk MESSAGE_BEGIN='@for line in' MESSAGE_END='; do echo "$$$$line"; done' $@

update-prereq: .force
	$(MAKE) -C $(patsubst file:%,%,$(ORIGIN_URL)) up

update-prereq-local: $(UPDATE_PREREQ) .force

up: revision.h .force

UP: .force
	@echo $(VCSUP) $(UPS); \
	while $(VCSUP) $(UPS) | tee makeup.log | $(PAGER) +/^C; \
	      grep ^C makeup.log; do \
	    sleep 1; \
	done; \
	rm -f makeup.log

tags: TAGS .force

TAGS: $(SRCS)
	@echo updating $@
	@tmp=$$(mktemp); \
	trap 'rm -f "$$tmp"' 0; \
	{ \
	$(GIT) grep -h --no-line-number -o '^ *# *define  *RBIMPL_ATTR_[A-Z_]*(*' | \
	sed 's/^ *# *define *//;/_H$$/d;y/(/+/' | sort -u && \
	echo 'NORETURN+'; \
	} > "$$tmp" && \
	ctags -e -I@"$$tmp" --langmap=c:+.y.ci.inc.def $(filter %.c %.h %.y %.ci %.inc %.def,$(SRCS))
	@etags -a -lruby $(call git_srcs,*.rb)

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

reset:
	$(VCSRESET)
	$(MAKE) prereq

exam: prereq .pre-exam test test-all test-rubyspec .post-exam .force
check: prereq .pre-check test test-all .post-check .force
test: prereq .pre-test $(subdirs:=/test) .post-test .force
test-all: prereq .pre-test-all $(subdirs:=/test-all) .post-test-all .force
test-rubyspec: prereq .pre-test-rubyspec $(subdirs:=/test-rubyspec) .post-test-rubyspec .force
try: $(DEFAULTARCH)/miniruby try.rb
	$(DEFAULTARCH)/miniruby try.rb

ifneq ($(wildcard $(srcdir_prefix)tool/vcs.rb),)
VCSCOMMIT := $(BASERUBY) $(if $(srcdir_prefix),-C $(srcdir_prefix)) -I./tool -rvcs -e 'VCS.detect(".").commit'
endif
commit:
	$(VCSCOMMIT)
shit: exam commit

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

.PHONY: ChangeLog
ChangeLog: RUBYLIB=$(ORIG_RUBYLIB)
ChangeLog:
	$(ECHO) Generating $@
	-$(Q) $(BASERUBY) -Itool/lib -rvcs \
	-e 'VCS.detect(ARGV[0]).export_changelog("@", nil, nil, ARGV[1])' \
	. $@
