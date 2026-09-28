ARCHS = arm64e
TARGET := iphone:clang:16.5:15.0

THEOS_PACKAGE_SCHEME = roothide
DEB_ARCH = iphoneos-arm64e

FINALPACKAGE = 1
DEBUG = 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AndroidNavigationBar ANBSpringBoardBridge


AndroidNavigationBar_FILES = AppBar.xm
AndroidNavigationBar_CFLAGS = -fobjc-arc
AndroidNavigationBar_FRAMEWORKS = \
	UIKit \
	WebKit \
	QuartzCore


ANBSpringBoardBridge_FILES = SpringBoardBridge.xm
ANBSpringBoardBridge_CFLAGS = -fobjc-arc
ANBSpringBoardBridge_FRAMEWORKS = \
	UIKit \
	Foundation


include $(THEOS_MAKE_PATH)/tweak.mk
