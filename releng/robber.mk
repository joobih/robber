ROBBER_VERSION := $(shell git describe --tags --always --long | sed 's,-,.,g' | cut -f1-3 -d'.')

include releng/system.mk

FOR_HOST ?= $(build_machine)
SHELL := $(shell which bash)

robber_gum_flags := \
	--default-library static \
	$(ROBBER_FLAGS_COMMON) \
	-Djailbreak=$(ROBBER_JAILBREAK) \
	-Dgumpp=enabled \
	-Dgumjs=enabled \
	-Dv8=$(ROBBER_V8) \
	-Ddatabase=$(ROBBER_DATABASE) \
	-Drobber_objc_bridge=$(ROBBER_OBJC_BRIDGE) \
	-Drobber_swift_bridge=$(ROBBER_SWIFT_BRIDGE) \
	-Drobber_java_bridge=$(ROBBER_JAVA_BRIDGE) \
	-Dtests=enabled \
	$(NULL)
robber_core_flags := \
	--default-library static \
	$(ROBBER_FLAGS_COMMON) \
	-Dconnectivity=$(ROBBER_CONNECTIVITY) \
	$(ROBBER_MAPPER)

robber_tools = \
	robber \
	robber-ls-devices \
	robber-ps \
	robber-kill \
	robber-ls \
	robber-rm \
	robber-pull \
	robber-push \
	robber-discover \
	robber-trace \
	robber-join \
	robber-create \
	frida-compile \
	robber-apk \
	$(NULL)

build/robber-env-%.rc: releng/setup-env.sh build/robber-version.h
	@if [ $* != $(build_machine) ]; then \
		cross=yes; \
	else \
		cross=no; \
	fi; \
	for machine in $(build_machine) $*; do \
		if [ ! -f build/robber-env-$$machine.rc ]; then \
			ROBBER_HOST=$$machine \
			ROBBER_CROSS=$$cross \
			ROBBER_ASAN=$(ROBBER_ASAN) \
			XCODE11="$(XCODE11)" \
			./releng/setup-env.sh || exit 1; \
		fi \
	done
build/robber_thin-env-%.rc: releng/setup-env.sh build/robber-version.h
	@if [ $* != $(build_machine) ]; then \
		cross=yes; \
	else \
		cross=no; \
	fi; \
	for machine in $(build_machine) $*; do \
		if [ ! -f build/robber_thin-env-$$machine.rc ]; then \
			ROBBER_HOST=$$machine \
			ROBBER_CROSS=$$cross \
			ROBBER_ASAN=$(ROBBER_ASAN) \
			ROBBER_ENV_NAME=robber_thin \
			XCODE11="$(XCODE11)" \
			./releng/setup-env.sh || exit 1; \
		fi \
	done
	@cd $(ROBBER)/build/; \
	[ ! -e robber-env-$*.rc ] && ln -s robber_thin-env-$*.rc robber-env-$*.rc; \
	[ ! -d robber-$* ] && ln -s robber_thin-$* robber-$*; \
	[ ! -d sdk-$* ] && ln -s robber_thin-sdk-$* sdk-$*; \
	[ ! -d toolchain-$* ] && ln -s robber_thin-toolchain-$* toolchain-$*; \
	true
build/robber_gir-env-%.rc: releng/setup-env.sh build/robber-version.h
	@if [ $* != $(build_machine) ]; then \
		cross=yes; \
	else \
		cross=no; \
	fi; \
	for machine in $(build_machine) $*; do \
		if [ ! -f build/robber_gir-env-$$machine.rc ]; then \
			ROBBER_HOST=$$machine \
			ROBBER_CROSS=$$cross \
			ROBBER_ASAN=$(ROBBER_ASAN) \
			ROBBER_ENV_NAME=robber_gir \
			XCODE11="$(XCODE11)" \
			./releng/setup-env.sh || exit 1; \
		fi \
	done
	@cd $(ROBBER)/build/; \
	[ ! -e robber-env-$*.rc ] && ln -s robber_gir-env-$*.rc robber-env-$*.rc; \
	[ ! -d robber-$* ] && ln -s robber_gir-$* robber-$*; \
	[ ! -d sdk-$* ] && ln -s robber_gir-sdk-$* sdk-$*; \
	[ ! -d toolchain-$* ] && ln -s robber_gir-toolchain-$* toolchain-$*; \
	true

build/robber-version.h: releng/generate-version-header.py .git/HEAD
	@$(PYTHON3) releng/generate-version-header.py > $@.tmp
	@mv $@.tmp $@

define meson-setup
	$(call meson-setup-for-env,robber,$1)
endef

define meson-setup-thin
	$(call meson-setup-for-env,robber_thin,$1)
endef

define meson-setup-for-env
	meson_args="--native-file build/$1-$(build_machine).txt"; \
	if [ $2 != $(build_machine) ]; then \
		meson_args="$$meson_args --cross-file build/$1-$2.txt"; \
	fi; \
	$(MESON) setup $$meson_args
endef
