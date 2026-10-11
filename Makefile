ifeq ($(THEOS_DEVICE_IP),)
THEOS_DEVICE_IP =
endif

ARCHS = arm64
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = standoff2

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = StandoffWH

StandoffWH_FILES = src/Tweak.xm
StandoffWH_CFLAGS = -fobjc-arc -std=c++17 -Wno-unused-function -Wno-unused-variable
StandoffWH_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics
StandoffWH_PRIVATE_FRAMEWORKS =
StandoffWH_LDFLAGS = -lsubstrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 standoff2" 2>/dev/null || true
