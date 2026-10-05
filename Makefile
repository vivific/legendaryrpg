TARGET := iphone:clang:latest:6.0
FINALPACKAGE = 1
ARCHS = armv7
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LegendaryRPG

LegendaryRPG_FILES = Tweak.x
LegendaryRPG_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
