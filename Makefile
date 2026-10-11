ifeq ($(THEOS_DEVICE_IP),)
THEOS_DEVICE_IP =
endif

ARCHS = arm64
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = standoff2

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = StandoffWH

StandoffWH_FILES = src/Tweak.xm \
                   src/imgui/imgui.cpp \
                   src/imgui/imgui_draw.cpp \
                   src/imgui/imgui_tables.cpp \
                   src/imgui/imgui_widgets.cpp \
                   src/imgui/imgui_impl_metal.mm

StandoffWH_CFLAGS = -fobjc-arc -std=c++17 -Isrc -Isrc/imgui -Wno-unused-function -Wno-unused-variable -Wno-nullability-completeness
StandoffWH_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics Metal MetalKit
StandoffWH_PRIVATE_FRAMEWORKS =
StandoffWH_LDFLAGS = -lsubstrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 standoff2" 2>/dev/null || true
