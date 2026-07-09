ARCHS := arm64
TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES := Excalibur

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := Excalibur



Excalibur_USE_MODULES := 0
Excalibur_FILES += $(wildcard objc_base/*.mm objc_base/*.m)
Excalibur_FILES += $(wildcard cheat/*.mm cheat/*.m)
Excalibur_FILES += imgui/ImGuiDrawView.mm
Excalibur_FILES += imgui/ESPImGuiView.mm
Excalibur_FILES += $(wildcard imgui/IMGUI/*.cpp)
Excalibur_FILES += $(wildcard imgui/IMGUI/*.mm)
Excalibur_FILES += $(wildcard esp/helpers/*.mm)
Excalibur_FILES += $(wildcard esp/unity_api/*.mm)
Excalibur_CFLAGS += -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-value -Wno-module-import-in-extern-c -Wno-mismatched-return-types
Excalibur_CFLAGS += -Iinclude
Excalibur_CFLAGS += -Iimgui
Excalibur_CFLAGS += -Iesp
Excalibur_CFLAGS += -include hud-prefix.pch
Excalibur_CCFLAGS += -DNOTIFY_LAUNCHED_HUD=\"ch.xxtou.notification.hud.launched\"
Excalibur_CCFLAGS += -DNOTIFY_DISMISSAL_HUD=\"ch.xxtou.notification.hud.dismissal\"
Excalibur_CCFLAGS += -DNOTIFY_RELOAD_HUD=\"ch.xxtou.notification.hud.reload\"
Excalibur_CCFLAGS += -DNOTIFY_RELOAD_APP=\"ch.xxtou.notification.app.reload\"
Excalibur_CCFLAGS += -std=c++17
MainApplication.mm_CCFLAGS += -std=c++14
Excalibur_FRAMEWORKS += CoreGraphics QuartzCore UIKit Foundation Metal MetalKit
Excalibur_PRIVATE_FRAMEWORKS += BackBoardServices GraphicsServices IOKit SpringBoardServices


TARGET_CODESIGN_FLAGS = -Sent.plist

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p packages $(THEOS_STAGING_DIR)/Payload$(ECHO_END)
	$(ECHO_NOTHING)cp -rp $(THEOS_STAGING_DIR)/Applications/Excalibur.app $(THEOS_STAGING_DIR)/Payload$(ECHO_END)
	$(ECHO_NOTHING)cd $(THEOS_STAGING_DIR); zip -qr XternalZ.tipa Payload; cd -;$(ECHO_END)
	$(ECHO_NOTHING)mv $(THEOS_STAGING_DIR)/XternalZ.tipa packages/XternalZ.tipa $(ECHO_END)



