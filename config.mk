DESTDIR ?=
PREFIX ?= /usr

ROBBER := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Features ordered by binary footprint, from largest to smallest
ROBBER_V8 ?= auto
ROBBER_CONNECTIVITY ?= enabled
ROBBER_DATABASE ?= enabled
ROBBER_JAVA_BRIDGE ?= auto
ROBBER_OBJC_BRIDGE ?= auto
ROBBER_SWIFT_BRIDGE ?= auto

ROBBER_AGENT_EMULATED ?= yes

# Include jailbreak-specific integrations
ROBBER_JAILBREAK ?= auto

ROBBER_ASAN ?= no

ifeq ($(ROBBER_ASAN), yes)
ROBBER_FLAGS_COMMON := -Doptimization=1 -Db_sanitize=address
ROBBER_FLAGS_BOTTLE := -Doptimization=1 -Db_sanitize=address
else
ROBBER_FLAGS_COMMON := -Doptimization=s -Db_ndebug=true --strip
ROBBER_FLAGS_BOTTLE := -Doptimization=s -Db_ndebug=true --strip
endif

ROBBER_MAPPER := -Dmapper=auto

XCODE11 ?= /Applications/Xcode-11.7.app

PYTHON ?= $(shell which python3)
PYTHON_VERSION := $(shell $(PYTHON) -c 'import sys; v = sys.version_info; print("{0}.{1}".format(v[0], v[1]))')
PYTHON_NAME ?= python$(PYTHON_VERSION)
PYTHON_PREFIX ?=
PYTHON_INCDIR ?=

PYTHON3 ?= python3

NODE ?= $(shell which node)
NODE_BIN_DIR := $(shell dirname $(NODE) 2>/dev/null)
NPM ?= $(NODE_BIN_DIR)/npm

MESON ?= $(PYTHON3) $(ROBBER)/releng/meson/meson.py

tests ?=
