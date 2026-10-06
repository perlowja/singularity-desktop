BUILD_DIR = build
LABWC_DIR = subprojects/labwc
LABWC_BUILD = $(LABWC_DIR)/build
LIBINPUT_DIR = subprojects/libinput
LIBINPUT_BUILD = $(LIBINPUT_DIR)/build
LIBINPUT_OPTIONS = --prefix=/usr --buildtype=release -Ddocumentation=false -Ddebug-gui=false -Dtests=false -Dlibwacom=false -Dlua-plugins=disabled
FPRINT_DRIVERS_DIR = /var/lib/singularity/fprint
GUSB_DIR = subprojects/libgusb
GUSB_BUILD = $(GUSB_DIR)/build
GUSB_STAGE = $(abspath $(GUSB_DIR))/stage
GUSB_REPO = https://github.com/hughsie/libgusb.git
GUSB_TAG = 0.4.9
GUSB_COMMIT = ed31c8134d80d006bd45450e84180be2a7c0742e
GUSB_OPTIONS = --prefix=$(GUSB_STAGE) --libdir=lib --buildtype=release -Dtests=false -Dvapi=false -Ddocs=false -Dintrospection=false -Dumockdev=disabled
LIBFPRINT_DIR = subprojects/libfprint
LIBFPRINT_BUILD = $(LIBFPRINT_DIR)/build
LIBFPRINT_REPO = https://gitlab.freedesktop.org/3v1n0/libfprint.git
LIBFPRINT_TAG = v1.94.9+tod1
LIBFPRINT_COMMIT = d25fa50748d6edf5be0f472f157a3b3020cb4113
LIBFPRINT_OPTIONS = --prefix=/usr --libdir=lib/x86_64-linux-gnu --buildtype=release --pkg-config-path=$(GUSB_STAGE)/lib/pkgconfig -Ddrivers=default -Dtod=true -Dintrospection=false -Ddoc=false -Dgtk-examples=false -Dinstalled-tests=false -Dudev_rules=disabled -Dudev_hwdb=disabled -Dtod_extra_drivers_dir=$(FPRINT_DRIVERS_DIR)/tod-1
GESTURE_DIR = subprojects/singularity-gestures
GESTURES ?= enabled
APPS ?= all
ifneq ($(SKIP_EXTRA),)
APPS = core
endif
ifneq ($(SKIP_NONESSENTIAL),)
APPS = essential
endif
export APPS
DEPLOY_PREFIX ?= /opt/local
PREFIX_OPTIONS = -Dprefix=$(DEPLOY_PREFIX) -Dlibdir=lib -Dlocalstatedir=/var/local
MESON_OPTIONS = -Dgestures=$(GESTURES) -Dapps=$(APPS) $(PREFIX_OPTIONS)

all: compile

$(BUILD_DIR)/build.ninja: | gesture-runtime
	meson setup $(BUILD_DIR) $(MESON_OPTIONS) || { rm -rf $(BUILD_DIR); meson setup $(BUILD_DIR) $(MESON_OPTIONS); }

$(LABWC_BUILD)/build.ninja:
	meson setup $(LABWC_BUILD) $(LABWC_DIR) --prefix=/usr --buildtype=release -Dxwayland=enabled --force-fallback-for=wlroots-0.20,scenefx-0.5 -Dscenefx:default_library=static -Dscenefx:examples=false || { rm -rf $(LABWC_BUILD); meson setup $(LABWC_BUILD) $(LABWC_DIR) --prefix=/usr --buildtype=release -Dxwayland=enabled --force-fallback-for=wlroots-0.20,scenefx-0.5 -Dscenefx:default_library=static -Dscenefx:examples=false; }

labwc: $(LABWC_BUILD)/build.ninja
	meson compile -C $(LABWC_BUILD)

$(LIBINPUT_BUILD)/build.ninja:
	meson setup $(LIBINPUT_BUILD) $(LIBINPUT_DIR) $(LIBINPUT_OPTIONS) || { rm -rf $(LIBINPUT_BUILD); meson setup $(LIBINPUT_BUILD) $(LIBINPUT_DIR) $(LIBINPUT_OPTIONS); }

libinput: $(LIBINPUT_BUILD)/build.ninja
	meson configure $(LIBINPUT_BUILD) -Dlibwacom=false
	meson compile -C $(LIBINPUT_BUILD)

$(GUSB_DIR)/meson.build:
	git -c advice.detachedHead=false clone --depth 1 --branch $(GUSB_TAG) $(GUSB_REPO) $(GUSB_DIR)
	test "$$(git -C $(GUSB_DIR) rev-parse HEAD)" = "$(GUSB_COMMIT)"

$(GUSB_BUILD)/build.ninja: | $(GUSB_DIR)/meson.build
	meson setup $(GUSB_BUILD) $(GUSB_DIR) $(GUSB_OPTIONS) || { rm -rf $(GUSB_BUILD); meson setup $(GUSB_BUILD) $(GUSB_DIR) $(GUSB_OPTIONS); }

gusb: $(GUSB_BUILD)/build.ninja
	meson compile -C $(GUSB_BUILD)
	meson install -C $(GUSB_BUILD) --quiet

$(LIBFPRINT_DIR)/meson.build:
	git -c advice.detachedHead=false clone --depth 1 --branch $(LIBFPRINT_TAG) $(LIBFPRINT_REPO) $(LIBFPRINT_DIR)
	test "$$(git -C $(LIBFPRINT_DIR) rev-parse HEAD)" = "$(LIBFPRINT_COMMIT)"
	git -C $(LIBFPRINT_DIR) apply $(CURDIR)/data/fprint/libfprint-tod-extra-dir.patch

$(LIBFPRINT_BUILD)/build.ninja: | gusb $(LIBFPRINT_DIR)/meson.build
	meson setup $(LIBFPRINT_BUILD) $(LIBFPRINT_DIR) $(LIBFPRINT_OPTIONS) || { rm -rf $(LIBFPRINT_BUILD); meson setup $(LIBFPRINT_BUILD) $(LIBFPRINT_DIR) $(LIBFPRINT_OPTIONS); }

libfprint: gusb $(LIBFPRINT_BUILD)/build.ninja
	meson compile -C $(LIBFPRINT_BUILD)
	meson install -C $(LIBFPRINT_BUILD) --destdir $(abspath $(LIBFPRINT_BUILD))/stage --quiet

libfprint-test: libfprint
	LD_LIBRARY_PATH=$(GUSB_STAGE)/lib meson test -C $(LIBFPRINT_BUILD) --print-errorlogs --no-suite data

BUILD_LOCK ?= $(if $(wildcard $(BUILD_DIR)/.build.lock),flock $(BUILD_DIR)/.build.lock)

compile: gesture-runtime $(BUILD_DIR)/build.ninja labwc libinput libfprint
	$(BUILD_LOCK) meson configure $(BUILD_DIR) -Dapps=$(APPS) $(PREFIX_OPTIONS)
	$(BUILD_LOCK) ninja -C $(BUILD_DIR) subprojects/libsingularity/Singularity-1.0.gir
	mkdir -p $(HOME)/.local/share/gir-1.0
	cp $(BUILD_DIR)/subprojects/libsingularity/Singularity-1.0.gir $(HOME)/.local/share/gir-1.0/
	$(BUILD_LOCK) meson compile -C $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR) $(LABWC_BUILD) $(LIBINPUT_BUILD) $(LIBFPRINT_BUILD) $(GUSB_BUILD) $(GUSB_STAGE)

install: compile
	@if [ -n "$$container" ]; then \
		echo "Inside container: bundling host libraries..."; \
		mkdir -p $(BUILD_DIR)/extra-libs; \
		find /usr/lib /usr/local/lib -name "libsfdo*.so*" -exec cp -a {} $(BUILD_DIR)/extra-libs/ \; 2>/dev/null || true; \
		find /usr/lib /usr/local/lib -name "libgtk4-layer-shell*.so*" -exec cp -a {} $(BUILD_DIR)/extra-libs/ \; 2>/dev/null || true; \
		find /usr/lib /usr/local/lib -name "libpeas-2*.so*" -exec cp -a {} $(BUILD_DIR)/extra-libs/ \; 2>/dev/null || true; \
	fi
	DEPLOY_PREFIX=$(DEPLOY_PREFIX) bash scripts/deploy-to-host.sh
	@if [ -n "$$container" ]; then \
		host-spawn systemctl --user try-restart xdg-desktop-portal-singularity.service || true; \
	else \
		systemctl --user try-restart xdg-desktop-portal-singularity.service || true; \
	fi

run: compile
	mkdir -p $(BUILD_DIR)/share/applications
	mkdir -p $(BUILD_DIR)/share/icons/hicolor/scalable/apps
	cp data/*.desktop $(BUILD_DIR)/share/applications/
	cp -r data/icons/* $(BUILD_DIR)/share/icons/
	gtk-update-icon-cache -f -t $(BUILD_DIR)/share/icons/hicolor

reconfigure:
	meson setup $(BUILD_DIR) $(MESON_OPTIONS) --reconfigure
	meson setup $(LABWC_BUILD) $(LABWC_DIR) --reconfigure --force-fallback-for=wlroots-0.20,scenefx-0.5 -Dscenefx:default_library=static -Dscenefx:examples=false

schemas:
	glib-compile-schemas data/

install-session:
	@if [ -n "$$container" ]; then \
		host-spawn sh $(CURDIR)/scripts/run0-tty.sh bash $(CURDIR)/subprojects/singularity-session/scripts/install-session.sh; \
		host-spawn sh $(CURDIR)/scripts/run0-tty.sh bash $(CURDIR)/subprojects/singularity-session/scripts/install-gdm-config.sh; \
	else \
		sh $(CURDIR)/scripts/run0-tty.sh bash $(CURDIR)/subprojects/singularity-session/scripts/install-session.sh; \
		sh $(CURDIR)/scripts/run0-tty.sh bash $(CURDIR)/subprojects/singularity-session/scripts/install-gdm-config.sh; \
	fi

deploy-host:
	@echo "NOTE: 'make deploy-host' is deprecated and now runs 'make install';"
	@echo "      the install and deploy processes have been unified."
	@$(MAKE) install

gesture-runtime:
ifeq ($(GESTURES),disabled)
	@:
else
	@test -f $(GESTURE_DIR)/runtime/libmediapipe.so \
		-a -f $(GESTURE_DIR)/runtime/hand_landmarker.task \
		-a -f $(GESTURE_DIR)/runtime/face_landmarker.task \
		-a -f $(GESTURE_DIR)/runtime/libonnxruntime.so \
		-a -f $(GESTURE_DIR)/runtime/mobileone_s0_gaze.onnx \
		-a -f $(GESTURE_DIR)/runtime/include/onnxruntime_c_api.h \
		-a -f $(GESTURE_DIR)/runtime/include/onnxruntime_ep_c_api.h \
		|| bash $(GESTURE_DIR)/scripts/bootstrap-runtime.sh
endif

install-greeter:
	@if [ -n "$$container" ]; then \
		host-spawn sh $(CURDIR)/scripts/run0-tty.sh bash $(CURDIR)/scripts/install-greeter.sh; \
	else \
		sh $(CURDIR)/scripts/run0-tty.sh bash $(CURDIR)/scripts/install-greeter.sh; \
	fi

.PHONY: all compile labwc libinput gusb libfprint libfprint-test gesture-runtime clean install run reconfigure schemas deploy-host install-session install-greeter
