include config.mk

build_arch := $(shell releng/detect-arch.sh)
ios_arm64eoabi_target := $(shell test -d /Applications/Xcode-11.7.app && echo build/robber-ios-arm64eoabi/usr/lib/pkgconfig/robber-core-1.0.pc)
test_args := $(addprefix -p=,$(tests))

HELP_FUN = \
	my (%help, @sections); \
	while(<>) { \
		if (/^([\w-]+)\s*:.*\#\#(?:@([\w-]+))?\s(.*)$$/) { \
			$$section = $$2 // 'options'; \
			push @sections, $$section unless exists $$help{$$section}; \
			push @{$$help{$$section}}, [$$1, $$3]; \
		} \
	} \
	$$target_color = "\033[32m"; \
	$$variable_color = "\033[36m"; \
	$$reset_color = "\033[0m"; \
	print "\n"; \
	print "\033[31mUsage:$${reset_color} make $${target_color}TARGET$${reset_color} [$${variable_color}VARIABLE$${reset_color}=value]\n\n"; \
	print "Where $${target_color}TARGET$${reset_color} specifies one or more of:\n"; \
	print "\n"; \
	for (@sections) { \
		print "  /* $$_ */\n"; $$sep = " " x (23 - length $$_->[0]); \
		printf("  $${target_color}%-23s$${reset_color}    %s\n", $$_->[0], $$_->[1]) for @{$$help{$$_}}; \
		print "\n"; \
	} \
	print "And optionally also $${variable_color}VARIABLE$${reset_color} values:\n"; \
	print "  $${variable_color}PYTHON$${reset_color}                     Absolute path of Python interpreter including version suffix\n"; \
	print "  $${variable_color}NODE$${reset_color}                       Absolute path of Node.js binary\n"; \
	print "\n"; \
	print "For example:\n"; \
	print "  \$$ make $${target_color}python-macos $${variable_color}PYTHON$${reset_color}=/usr/local/bin/python3.6\n"; \
	print "  \$$ make $${target_color}node-macos $${variable_color}NODE$${reset_color}=/usr/local/bin/node\n"; \
	print "\n";

help:
	@LC_ALL=C perl -e '$(HELP_FUN)' $(MAKEFILE_LIST)


include releng/robber.mk

distclean: clean-submodules
	rm -rf build/
	rm -rf deps/

clean: clean-submodules
	rm -f build/*-clang*
	rm -f build/*-pkg-config
	rm -f build/*-stamp
	rm -f build/*.rc
	rm -f build/*.tar.bz2
	rm -f build/*.txt
	rm -f build/robber-version.h
	rm -rf build/robber-*-*
	rm -rf build/robber_thin-*-*
	rm -rf build/fs-*-*
	rm -rf build/ft-*-*
	rm -rf build/tmp-*-*
	rm -rf build/tmp_thin-*-*
	rm -rf build/fs-tmp-*-*
	rm -rf build/ft-tmp-*-*

clean-submodules:
	cd robber-gum && git clean -xfd
	cd robber-core && git clean -xfd
	cd robber-python && git clean -xfd
	cd robber-node && git clean -xfd
	cd robber-tools && git clean -xfd


define make-ios-env-rule
build/robber-env-ios-$1.rc: releng/setup-env.sh build/robber-version.h
	@if [ $1 != $$(build_machine) ]; then \
		cross=yes; \
	else \
		cross=no; \
	fi; \
	for machine in $$(build_machine) ios-$1; do \
		if [ ! -f build/robber-env-$$$$machine.rc ]; then \
			ROBBER_HOST=$$$$machine \
			ROBBER_CROSS=$$$$cross \
			ROBBER_PREFIX="$$(abspath build/robber-ios-$1/usr)" \
			ROBBER_ASAN=$$(ROBBER_ASAN) \
			XCODE11="$$(XCODE11)" \
			./releng/setup-env.sh || exit 1; \
		fi \
	done
endef

$(eval $(call make-ios-env-rule,arm64))
$(eval $(call make-ios-env-rule,arm64e))
$(eval $(call make-ios-env-rule,arm64eoabi))
$(eval $(call make-ios-env-rule,x86_64-simulator))
$(eval $(call make-ios-env-rule,arm64-simulator))

build/robber-ios-%/usr/lib/pkgconfig/robber-gum-1.0.pc: build/robber-env-ios-%.rc build/.robber-gum-submodule-stamp
	. build/robber-env-ios-$*.rc; \
	builddir=build/tmp-ios-$*/robber-gum; \
	if [ ! -f $$builddir/build.ninja ]; then \
		$(call meson-setup,ios-$*) \
			--prefix /usr \
			$(robber_gum_flags) \
			robber-gum $$builddir || exit 1; \
	fi \
		&& $(MESON) compile -C $$builddir \
		&& DESTDIR="$(abspath build/robber-ios-$*)" $(MESON) install -C $$builddir
	@touch $@
build/robber-ios-%/usr/lib/pkgconfig/robber-core-1.0.pc: build/.robber-core-submodule-stamp build/robber-ios-%/usr/lib/pkgconfig/robber-gum-1.0.pc
	. build/robber-env-ios-$*.rc; \
	builddir=build/tmp-ios-$*/robber-core; \
	if [ ! -f $$builddir/build.ninja ]; then \
		$(call meson-setup,ios-$*) \
			--prefix /usr \
			$(robber_core_flags) \
			-Dassets=installed \
			robber-core $$builddir || exit 1; \
	fi \
		&& $(MESON) compile -C $$builddir \
		&& DESTDIR="$(abspath build/robber-ios-$*)" $(MESON) install -C $$builddir
	@touch $@


gum-macos: build/robber-macos-$(build_arch)/lib/pkgconfig/robber-gum-1.0.pc ##@gum Build for macOS
gum-ios: build/robber-ios-arm64/usr/lib/pkgconfig/robber-gum-1.0.pc ##@gum Build for iOS
gum-watchos: build/robber_thin-watchos-arm64/lib/pkgconfig/robber-gum-1.0.pc ##@gum Build for watchOS
gum-tvos: build/robber_thin-tvos-arm64/lib/pkgconfig/robber-gum-1.0.pc ##@gum Build for tvOS
gum-android-x86: build/robber-android-x86/lib/pkgconfig/robber-gum-1.0.pc ##@gum Build for Android/x86
gum-android-x86_64: build/robber-android-x86_64/lib/pkgconfig/robber-gum-1.0.pc ##@gum Build for Android/x86-64
gum-android-arm: build/robber-android-arm/lib/pkgconfig/robber-gum-1.0.pc ##@gum Build for Android/arm
gum-android-arm64: build/robber-android-arm64/lib/pkgconfig/robber-gum-1.0.pc ##@gum Build for Android/arm64

define make-gum-rules
build/$1-%/lib/pkgconfig/robber-gum-1.0.pc: build/$1-env-%.rc build/.robber-gum-submodule-stamp
	. build/$1-env-$$*.rc; \
	builddir=build/$2-$$*/robber-gum; \
	if [ ! -f $$$$builddir/build.ninja ]; then \
		$$(call meson-setup-for-env,$1,$$*) \
			--prefix $$(ROBBER)/build/$1-$$* \
			$$(robber_gum_flags) \
			robber-gum $$$$builddir || exit 1; \
	fi; \
	$$(MESON) install -C $$$$builddir || exit 1
	@touch -c $$@
endef
$(eval $(call make-gum-rules,robber,tmp))
$(eval $(call make-gum-rules,robber_thin,tmp_thin))

ifeq ($(build_arch), arm64)
check-gum-macos: build/robber-macos-arm64/lib/pkgconfig/robber-gum-1.0.pc build/robber-macos-arm64e/lib/pkgconfig/robber-gum-1.0.pc ##@gum Run tests for macOS
	build/tmp-macos-arm64/robber-gum/tests/gum-tests $(test_args)
	runner=build/tmp-macos-arm64e/robber-gum/tests/gum-tests; \
	if $$runner --help &>/dev/null; then \
		$$runner $(test_args); \
	fi
else
check-gum-macos: build/robber-macos-x86_64/lib/pkgconfig/robber-gum-1.0.pc
	build/tmp-macos-x86_64/robber-gum/tests/gum-tests $(test_args)
endif


core-macos: build/robber-macos-$(build_arch)/lib/pkgconfig/robber-core-1.0.pc ##@core Build for macOS
core-ios: build/robber-ios-arm64/usr/lib/pkgconfig/robber-core-1.0.pc ##@core Build for iOS
core-watchos: build/robber_thin-watchos-arm64/lib/pkgconfig/robber-core-1.0.pc ##@core Build for watchOS
core-tvos: build/robber_thin-tvos-arm64/lib/pkgconfig/robber-core-1.0.pc ##@core Build for tvOS
core-android-x86: build/robber-android-x86/lib/pkgconfig/robber-core-1.0.pc ##@core Build for Android/x86
core-android-x86_64: build/robber-android-x86_64/lib/pkgconfig/robber-core-1.0.pc ##@core Build for Android/x86-64
core-android-arm: build/robber-android-arm/lib/pkgconfig/robber-core-1.0.pc ##@core Build for Android/arm
core-android-arm64: build/robber-android-arm64/lib/pkgconfig/robber-core-1.0.pc ##@core Build for Android/arm64

build/tmp-macos-arm64/robber-core/.robber-ninja-stamp: build/.robber-core-submodule-stamp build/robber-macos-arm64/lib/pkgconfig/robber-gum-1.0.pc
	. build/robber-env-macos-arm64.rc; \
	builddir=$(@D); \
	if [ ! -f $$builddir/build.ninja ]; then \
		$(call meson-setup,macos-arm64) \
			--prefix $(ROBBER)/build/robber-macos-arm64 \
			$(robber_core_flags) \
			-Dhelper_modern=$(ROBBER)/build/tmp-macos-arm64e/robber-core/src/robber-helper \
			-Dhelper_legacy=$(ROBBER)/build/tmp-macos-arm64/robber-core/src/robber-helper \
			-Dagent_modern=$(ROBBER)/build/tmp-macos-arm64e/robber-core/lib/agent/robber-agent.dylib \
			-Dagent_legacy=$(ROBBER)/build/tmp-macos-arm64/robber-core/lib/agent/robber-agent.dylib \
			robber-core $$builddir || exit 1; \
	fi
	@touch $@
build/tmp-macos-arm64e/robber-core/.robber-ninja-stamp: build/.robber-core-submodule-stamp build/robber-macos-arm64e/lib/pkgconfig/robber-gum-1.0.pc
	. build/robber-env-macos-arm64e.rc; \
	builddir=$(@D); \
	if [ ! -f $$builddir/build.ninja ]; then \
		$(call meson-setup,macos-arm64e) \
			--prefix $(ROBBER)/build/robber-macos-arm64e \
			$(robber_core_flags) \
			-Dhelper_modern=$(ROBBER)/build/tmp-macos-arm64e/robber-core/src/robber-helper \
			-Dhelper_legacy=$(ROBBER)/build/tmp-macos-arm64/robber-core/src/robber-helper \
			-Dagent_modern=$(ROBBER)/build/tmp-macos-arm64e/robber-core/lib/agent/robber-agent.dylib \
			-Dagent_legacy=$(ROBBER)/build/tmp-macos-arm64/robber-core/lib/agent/robber-agent.dylib \
			robber-core $$builddir || exit 1; \
	fi
	@touch $@
build/tmp-macos-x86_64/robber-core/.robber-ninja-stamp: build/.robber-core-submodule-stamp build/robber-macos-x86_64/lib/pkgconfig/robber-gum-1.0.pc
	. build/robber-env-macos-x86_64.rc; \
	builddir=$(@D); \
	if [ ! -f $$builddir/build.ninja ]; then \
		$(call meson-setup,macos-x86_64) \
			--prefix $(ROBBER)/build/robber-macos-x86_64 \
			$(robber_core_flags) \
			-Dhelper_modern=$(ROBBER)/build/tmp-macos-x86_64/robber-core/src/robber-helper \
			-Dagent_modern=$(ROBBER)/build/tmp-macos-x86_64/robber-core/lib/agent/robber-agent.dylib \
			robber-core $$builddir || exit 1; \
	fi
	@touch $@
build/tmp-android-x86/robber-core/.robber-ninja-stamp: build/.robber-core-submodule-stamp build/robber-android-x86/lib/pkgconfig/robber-gum-1.0.pc
	if [ "$(ROBBER_AGENT_EMULATED)" == "yes" ]; then \
		agent_emulated_legacy=$(ROBBER)/build/tmp-android-arm/robber-core/lib/agent/robber-agent.so; \
	fi; \
	. build/robber-env-android-x86.rc; \
	builddir=$(@D); \
	if [ ! -f $$builddir/build.ninja ]; then \
		$(call meson-setup,android-x86) \
			--prefix $(ROBBER)/build/robber-android-x86 \
			$(robber_core_flags) \
			-Dagent_emulated_legacy=$$agent_emulated_legacy \
			robber-core $$builddir || exit 1; \
	fi
	@touch $@
build/tmp-android-x86_64/robber-core/.robber-ninja-stamp: build/.robber-core-submodule-stamp build/robber-android-x86_64/lib/pkgconfig/robber-gum-1.0.pc
	if [ "$(ROBBER_AGENT_EMULATED)" == "yes" ]; then \
		agent_emulated_modern=$(ROBBER)/build/tmp-android-arm64/robber-core/lib/agent/robber-agent.so; \
		agent_emulated_legacy=$(ROBBER)/build/tmp-android-arm/robber-core/lib/agent/robber-agent.so; \
	fi; \
	. build/robber-env-android-x86_64.rc; \
	builddir=$(@D); \
	if [ ! -f $$builddir/build.ninja ]; then \
		$(call meson-setup,android-x86_64) \
			--prefix $(ROBBER)/build/robber-android-x86_64 \
			$(robber_core_flags) \
			-Dhelper_modern=$(ROBBER)/build/tmp-android-x86_64/robber-core/src/robber-helper \
			-Dhelper_legacy=$(ROBBER)/build/tmp-android-x86/robber-core/src/robber-helper \
			-Dagent_modern=$(ROBBER)/build/tmp-android-x86_64/robber-core/lib/agent/robber-agent.so \
			-Dagent_legacy=$(ROBBER)/build/tmp-android-x86/robber-core/lib/agent/robber-agent.so \
			-Dagent_emulated_modern=$$agent_emulated_modern \
			-Dagent_emulated_legacy=$$agent_emulated_legacy \
			robber-core $$builddir || exit 1; \
	fi
	@touch $@
build/tmp-android-arm/robber-core/.robber-ninja-stamp: build/.robber-core-submodule-stamp build/robber-android-arm/lib/pkgconfig/robber-gum-1.0.pc
	. build/robber-env-android-arm.rc; \
	builddir=$(@D); \
	if [ ! -f $$builddir/build.ninja ]; then \
		$(call meson-setup,android-arm) \
			--prefix $(ROBBER)/build/robber-android-arm \
			$(robber_core_flags) \
			robber-core $$builddir || exit 1; \
	fi
	@touch $@
build/tmp-android-arm64/robber-core/.robber-ninja-stamp: build/.robber-core-submodule-stamp build/robber-android-arm64/lib/pkgconfig/robber-gum-1.0.pc
	. build/robber-env-android-arm64.rc; \
	builddir=$(@D); \
	if [ ! -f $$builddir/build.ninja ]; then \
		$(call meson-setup,android-arm64) \
			--prefix $(ROBBER)/build/robber-android-arm64 \
			$(robber_core_flags) \
			-Dhelper_modern=$(ROBBER)/build/tmp-android-arm64/robber-core/src/robber-helper \
			-Dhelper_legacy=$(ROBBER)/build/tmp-android-arm/robber-core/src/robber-helper \
			-Dagent_modern=$(ROBBER)/build/tmp-android-arm64/robber-core/lib/agent/robber-agent.so \
			-Dagent_legacy=$(ROBBER)/build/tmp-android-arm/robber-core/lib/agent/robber-agent.so \
			robber-core $$builddir || exit 1; \
	fi
	@touch $@
build/tmp_thin-%/robber-core/.robber-ninja-stamp: build/.robber-core-submodule-stamp build/robber_thin-%/lib/pkgconfig/robber-gum-1.0.pc
	. build/robber_thin-env-$*.rc; \
	builddir=$(@D); \
	if [ ! -f $$builddir/build.ninja ]; then \
		$(call meson-setup-thin,$*) \
			--prefix $(ROBBER)/build/robber_thin-$* \
			$(robber_core_flags) \
			robber-core $$builddir || exit 1; \
	fi
	@touch $@

ifeq ($(ROBBER_AGENT_EMULATED), yes)
legacy_agent_emulated_dep := build/tmp-android-arm/robber-core/.robber-agent-stamp
modern_agent_emulated_dep := build/tmp-android-arm64/robber-core/.robber-agent-stamp
endif

build/robber-macos-x86_64/lib/pkgconfig/robber-core-1.0.pc: build/tmp-macos-x86_64/robber-core/.robber-helper-and-agent-stamp
	@rm -f build/tmp-macos-x86_64/robber-core/src/robber-data-{helper,agent}*
	. build/robber-env-macos-x86_64.rc && $(MESON) install -C build/tmp-macos-x86_64/robber-core
	@touch $@
build/robber-macos-arm64/lib/pkgconfig/robber-core-1.0.pc: build/tmp-macos-arm64/robber-core/.robber-helper-and-agent-stamp build/tmp-macos-arm64e/robber-core/.robber-helper-and-agent-stamp
	@rm -f build/tmp-macos-arm64/robber-core/src/robber-data-{helper,agent}*
	. build/robber-env-macos-arm64.rc && $(MESON) install -C build/tmp-macos-arm64/robber-core
	@touch $@
build/robber-macos-arm64e/lib/pkgconfig/robber-core-1.0.pc: build/tmp-macos-arm64/robber-core/.robber-helper-and-agent-stamp build/tmp-macos-arm64e/robber-core/.robber-helper-and-agent-stamp
	@rm -f build/tmp-macos-arm64e/robber-core/src/robber-data-{helper,agent}*
	. build/robber-env-macos-arm64e.rc && $(MESON) install -C build/tmp-macos-arm64e/robber-core
	@touch $@
build/robber-android-x86/lib/pkgconfig/robber-core-1.0.pc: build/tmp-android-x86/robber-core/.robber-helper-and-agent-stamp $(legacy_agent_emulated_dep)
	@rm -f build/tmp-android-x86/robber-core/src/robber-data-{helper,agent}*
	. build/robber-env-android-x86.rc && $(MESON) install -C build/tmp-android-x86/robber-core
	@touch $@
build/robber-android-x86_64/lib/pkgconfig/robber-core-1.0.pc: build/tmp-android-x86/robber-core/.robber-helper-and-agent-stamp build/tmp-android-x86_64/robber-core/.robber-helper-and-agent-stamp $(legacy_agent_emulated_dep) $(modern_agent_emulated_dep)
	@rm -f build/tmp-android-x86_64/robber-core/src/robber-data-{helper,agent}*
	. build/robber-env-android-x86_64.rc && $(MESON) install -C build/tmp-android-x86_64/robber-core
	@touch $@
build/robber-android-arm/lib/pkgconfig/robber-core-1.0.pc: build/tmp-android-arm/robber-core/.robber-helper-and-agent-stamp
	@rm -f build/tmp-android-arm/robber-core/src/robber-data-{helper,agent}*
	. build/robber-env-android-arm.rc && $(MESON) install -C build/tmp-android-arm/robber-core
	@touch $@
build/robber-android-arm64/lib/pkgconfig/robber-core-1.0.pc: build/tmp-android-arm/robber-core/.robber-helper-and-agent-stamp build/tmp-android-arm64/robber-core/.robber-helper-and-agent-stamp
	@rm -f build/tmp-android-arm64/robber-core/src/robber-data-{helper,agent}*
	. build/robber-env-android-arm64.rc && $(MESON) install -C build/tmp-android-arm64/robber-core
	@touch $@
build/robber_thin-%/lib/pkgconfig/robber-core-1.0.pc: build/tmp_thin-%/robber-core/.robber-ninja-stamp
	. build/robber_thin-env-$*.rc && $(MESON) install -C build/tmp_thin-$*/robber-core
	@touch $@

build/tmp-macos-%/robber-core/.robber-helper-and-agent-stamp: build/tmp-macos-%/robber-core/.robber-ninja-stamp
	. build/robber-env-macos-$*.rc && ninja -C build/tmp-macos-$*/robber-core src/robber-helper lib/agent/robber-agent.dylib
	@touch $@
build/tmp-macos-%/robber-core/.robber-agent-stamp: build/tmp-macos-%/robber-core/.robber-ninja-stamp
	. build/robber-env-macos-$*.rc && ninja -C build/tmp-macos-$*/robber-core lib/agent/robber-agent.dylib
	@touch $@
build/tmp-android-%/robber-core/.robber-helper-and-agent-stamp: build/tmp-android-%/robber-core/.robber-ninja-stamp
	. build/robber-env-android-$*.rc && ninja -C build/tmp-android-$*/robber-core src/robber-helper lib/agent/robber-agent.so
	@touch $@
build/tmp-android-%/robber-core/.robber-agent-stamp: build/tmp-android-%/robber-core/.robber-ninja-stamp
	. build/robber-env-android-$*.rc && ninja -C build/tmp-android-$*/robber-core lib/agent/robber-agent.so
	@touch $@

ifeq ($(build_arch), arm64)
check-core-macos: build/robber-macos-arm64/lib/pkgconfig/robber-core-1.0.pc build/robber-macos-arm64e/lib/pkgconfig/robber-core-1.0.pc ##@core Run tests for macOS
	build/tmp-macos-arm64/robber-core/tests/robber-tests $(test_args)
	runner=build/tmp-macos-arm64e/robber-core/tests/robber-tests; \
	if $$runner --help &>/dev/null; then \
		$$runner $(test_args); \
	fi
else
check-core-macos: build/robber-macos-x86_64/lib/pkgconfig/robber-core-1.0.pc
	build/tmp-macos-x86_64/robber-core/tests/robber-tests $(test_args)
endif


python-macos: build/tmp-macos-$(build_arch)/robber-$(PYTHON_NAME)/.robber-stamp ##@python Build Python bindings for macOS

define make-python-rule
build/$2-%/robber-$$(PYTHON_NAME)/.robber-stamp: build/.robber-python-submodule-stamp build/$1-%$(PYTHON_PREFIX)/lib/pkgconfig/robber-core-1.0.pc
	. build/$1-env-$$*.rc; \
	builddir=$$(@D); \
	if [ ! -f $$$$builddir/build.ninja ]; then \
		$$(call meson-setup-for-env,$1,$$*) \
			--prefix $$(ROBBER)/build/$1-$$*$(PYTHON_PREFIX) \
			$$(ROBBER_FLAGS_COMMON) \
			-Dpython=$$(PYTHON) \
			-Dpython_incdir=$$(PYTHON_INCDIR) \
			robber-python $$$$builddir || exit 1; \
	fi; \
	$$(MESON) install -C $$$$builddir || exit 1
	@touch $$@
endef
$(eval $(call make-python-rule,robber,tmp))
$(eval $(call make-python-rule,robber_thin,tmp_thin))

check-python-macos: python-macos ##@python Test Python bindings for macOS
	export PYTHONPATH="$(shell pwd)/build/robber-macos-$(build_arch)/lib/$(PYTHON_NAME)/site-packages" \
		&& cd robber-python \
		&& $(PYTHON) -m unittest discover


node-macos: build/robber-macos-$(build_arch)/lib/node_modules/robber ##@node Build Node.js bindings for macOS

define make-node-rule
build/$1-%/lib/node_modules/robber: build/$1-%/lib/pkgconfig/robber-core-1.0.pc build/.robber-node-submodule-stamp
	@$$(NPM) --version &>/dev/null || (echo -e "\033[31mOops. It appears Node.js is not installed.\nCheck PATH or set NODE to the absolute path of your Node.js binary.\033[0m"; exit 1;)
	export PATH=$$(NODE_BIN_DIR):$$$$PATH ROBBER=$$(ROBBER) \
		&& cd robber-node \
		&& rm -rf robber-0.0.0.tgz build node_modules \
		&& $$(NPM) install \
		&& $$(NPM) pack \
		&& rm -rf ../$$@/ ../$$@.tmp/ \
		&& mkdir -p ../$$@.tmp/build/ \
		&& tar -C ../$$@.tmp/ --strip-components 1 -x -f robber-0.0.0.tgz \
		&& rm robber-0.0.0.tgz \
		&& mv build/Release/robber_binding.node ../$$@.tmp/build/ \
		&& rm -rf build \
		&& mv node_modules ../$$@.tmp/ \
		&& mv ../$$@.tmp ../$$@
endef
$(eval $(call make-node-rule,robber,tmp))
$(eval $(call make-node-rule,robber_thin,tmp_thin))

define run-node-tests
	export PATH=$3:$$PATH ROBBER=$2 \
		&& cd robber-node \
		&& git clean -xfd \
		&& $5 install \
		&& $4 \
			--expose-gc \
			../build/$1/lib/node_modules/robber/node_modules/.bin/_mocha \
			-r ts-node/register \
			--timeout 60000 \
			test/*.ts
endef
check-node-macos: node-macos ##@node Test Node.js bindings for macOS
	$(call run-node-tests,robber-macos-$(build_arch),$(ROBBER),$(NODE_BIN_DIR),$(NODE),$(NPM))


tools-macos: build/tmp-macos-$(build_arch)/robber-tools-$(PYTHON_NAME)/.robber-stamp ##@tools Build CLI tools for macOS

define make-tools-rule
build/$2-%/robber-tools-$$(PYTHON_NAME)/.robber-stamp: build/.robber-tools-submodule-stamp build/$2-%/robber-$$(PYTHON_NAME)/.robber-stamp
	. build/$1-env-$$*.rc; \
	builddir=$$(@D); \
	if [ ! -f $$$$builddir/build.ninja ]; then \
		$$(call meson-setup-for-env,$1,$$*) \
			--prefix $$(ROBBER)/build/$1-$$* \
			-Dpython=$$(PYTHON) \
			robber-tools $$$$builddir || exit 1; \
	fi; \
	$$(MESON) install -C $$$$builddir || exit 1
	@touch $$@
endef
$(eval $(call make-tools-rule,robber,tmp))
$(eval $(call make-tools-rule,robber_thin,tmp_thin))

check-tools-macos: tools-macos ##@tools Test CLI tools for macOS
	export PYTHONPATH="$(shell pwd)/build/robber-macos-$(build_arch)/lib/$(PYTHON_NAME)/site-packages" \
		&& cd robber-tools \
		&& $(PYTHON) -m unittest discover


.PHONY: \
	distclean clean clean-submodules git-submodules git-submodule-stamps \
	gum-macos \
		gum-ios gum-watchos gum-tvos \
		gum-android-x86 gum-android-x86_64 \
		gum-android-arm gum-android-arm64 \
		check-gum-macos \
		robber-gum-update-submodule-stamp \
	core-macos \
		core-ios core-watchos core-tvos \
		core-android-x86 core-android-x86_64 \
		core-android-arm core-android-arm64 \
		check-core-macos \
		robber-core-update-submodule-stamp \
	python-macos \
		python-macos-universal \
		check-python-macos \
		robber-python-update-submodule-stamp \
	node-macos \
		check-node-macos \
		robber-node-update-submodule-stamp \
	tools-macos \
		check-tools-macos \
		robber-tools-update-submodule-stamp
.SECONDARY:
