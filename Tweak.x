// TalesOfPaths v1.00
// Offline preservation patch for Tales of Phantasia iOS WW 1.0.1 / JP 1.0.2.

#import <Foundation/Foundation.h>
#import <substrate.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

// Opaque C++ types used by the hook signatures. The executable uses the old
// 32-bit libstdc++ std::string ABI, so std::string remains opaque here.
typedef void TopHttpHelper;
typedef void StdString;
typedef void TopMenuTitle;
typedef void TopMenuSave;
typedef void TopMenuBuy;

#define WW_TEXT_VMADDR             0x00004000
#define WW_PARSE_SLOT_ADDR         0x0026F10C
#define WW_CONTINUE_OPEN_ADDR      0x00E62EF0   // __ZL12continueOpen
#define WW_LOAD_OPEN_ADDR          0x00E62EF1   // __ZL8loadOpen

#define JP_TEXT_VMADDR             0x00001000
#define JP_PARSE_SLOT_ADDR         0x00254408
#define JP_CONTINUE_OPEN_ADDR      0x01BFCE99   // __ZL12continueOpen
#define JP_LOAD_OPEN_ADDR          0x01BFCE9A   // __ZL8loadOpen

#define HTTP_STATE_OFFSET          0x11
#define MENU_SELECTION_OFFSET      0x13C
#define IAP_STEP_OFFSET            0x08
#define IAP_SYNC_SUCCESS_STEP      7
#define LOCAL_SAVE_SIZE            0x2000

static int (*orig_IsBusy)(TopHttpHelper *self);
static int (*orig_RequestCheckVersion)(TopHttpHelper *self);
static int (*orig_ParseCheckVersion)(TopHttpHelper *self, StdString *resp);
static int (*orig_RequestLogin)(TopHttpHelper *self);
static int (*orig_parse_login_data_result)(StdString *resp);
static int (*orig_RequestGetSlot)(TopHttpHelper *self);
static int (*orig_parse_slot_data_result)(StdString *resp);

static int (*orig_IAP_IsBusy)(void *self);
static int (*orig_IAP_RequestItemList)(void *self);

// Free/offline shop hooks.
static int  (*orig_getRMBItemCountByItem)(StdString *itemName);
static int  (*orig_IAP_UsedItem)(void *self, StdString *itemName, int count);
static int  (*orig_IAP_RequestBuy)(void *self, int serverID);
static int  (*orig_IAP_RequestSycnItem)(void *self);
static void (*orig_TopMenuBuy_menuSureCallback)(TopMenuBuy *self, void *sender);

// Objective-C StoreKit hooks.
static BOOL (*orig_MKStoreManager_isFeaturePurchased)(id self, SEL _cmd, id feature);
static void (*orig_MKStoreManager_buyFeature)(id self, SEL _cmd, id feature);

static BOOL (*orig_IAPModuler_isGetAllPrices)(id self, SEL _cmd);
static void (*orig_IAPModuler_GetAllPrice)(id self, SEL _cmd);
static int (*orig_RequestGetItemPrice)(TopHttpHelper *self);
static int (*orig_parse_price_data_result)(StdString *resp);
static int (*orig_RequestGetNotice)(TopHttpHelper *self);
static int (*orig_parse_url_data_result)(StdString *resp);
static int (*orig_RequestGetPrivateNotice)(TopHttpHelper *self);
static int (*orig_Parseprivatenotice)(TopHttpHelper *self, StdString *resp);

static void (*orig_menuGameSelectCallback)(TopMenuTitle *self, void *sender);
static void (*fn_popNewGameUI)(TopMenuTitle *self);
static void (*fn_selectLoadData)(TopMenuTitle *self);

static int  (*orig_RequestSave)(TopHttpHelper *self, int slot, StdString *saveStr);
static int  (*orig_parse_save_data_result)(StdString *resp);
static void (*orig_TopMenuSave_linkNet)(TopMenuSave *self);
static void (*fn_TopMenuSave_linkSuccess)(TopMenuSave *self);

static int (*orig_RequestLoad)(TopHttpHelper *self, int slot);
static int (*orig_parse_load_data_result)(StdString *resp, void *dst);

static uint8_t *gContinueOpen = NULL;
static uint8_t *gLoadOpen     = NULL;

// ---------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------

static void *findSymbol(const char *name) {
    static void *handle = NULL;
    if (!handle) handle = dlopen(NULL, RTLD_NOW);
    return handle ? dlsym(handle, name) : NULL;
}

static void markHttpIdle(TopHttpHelper *self) {
    if (self) {
        *((uint8_t *)self + HTTP_STATE_OFFSET) = 0;
    }
}

static int configureSlotGlobals(void *symbol) {
    uintptr_t runtimeParser;
    uintptr_t imageBase;
    uintptr_t parserOffset;
    uintptr_t textVMAddr;
    uintptr_t continueAddr;
    uintptr_t loadAddr;
    const char *buildName;
    Dl_info info;

    if (!symbol) return 0;

    // Callable ARM Thumb symbols carry bit 0; dladdr expects the real address.
    runtimeParser = ((uintptr_t)symbol) & ~(uintptr_t)1;
    memset(&info, 0, sizeof(info));

    if (!dladdr((const void *)runtimeParser, &info) || !info.dli_fbase) {
        NSLog(@"[TOP] Could not identify executable image for slot parser");
        return 0;
    }

    imageBase = (uintptr_t)info.dli_fbase;
    parserOffset = runtimeParser - imageBase;

    if (parserOffset == (WW_PARSE_SLOT_ADDR - WW_TEXT_VMADDR)) {
        buildName = "WW 1.0.1";
        textVMAddr = WW_TEXT_VMADDR;
        continueAddr = WW_CONTINUE_OPEN_ADDR;
        loadAddr = WW_LOAD_OPEN_ADDR;
    } else if (parserOffset == (JP_PARSE_SLOT_ADDR - JP_TEXT_VMADDR)) {
        buildName = "JP 1.0.2";
        textVMAddr = JP_TEXT_VMADDR;
        continueAddr = JP_CONTINUE_OPEN_ADDR;
        loadAddr = JP_LOAD_OPEN_ADDR;
    } else {
        NSLog(@"[TOP] Unsupported TOP build (slot parser image offset 0x%08lx)",
              (unsigned long)parserOffset);
        return 0;
    }

    gContinueOpen = (uint8_t *)(imageBase + (continueAddr - textVMAddr));
    gLoadOpen     = (uint8_t *)(imageBase + (loadAddr - textVMAddr));

    NSLog(@"[TOP] Detected %s, continueOpen=%p, loadOpen=%p",
          buildName, gContinueOpen, gLoadOpen);
    return 1;
}

// ---------------------------------------------------------------------
// Title main menu gate patch
// ---------------------------------------------------------------------

static void my_menuGameSelectCallback(TopMenuTitle *self, void *sender) {
    if (!sender) return;

    int idx = *(int *)((uint8_t *)sender + MENU_SELECTION_OFFSET);

    NSLog(@"[TOP] menuGameSelectCallback idx=%d", idx);

    if (idx == 0) {
        if (orig_menuGameSelectCallback) {
            orig_menuGameSelectCallback(self, sender);
        }
        return;
    }

    switch (idx) {
        case 1: // New Game
            NSLog(@"[TOP] New Game");
            if (fn_popNewGameUI) {
                fn_popNewGameUI(self);
            } else {
                NSLog(@"[TOP] fn_popNewGameUI not resolved; cannot show New Game dialog");
            }
            return;

        case 2: // Load
            NSLog(@"[TOP] Load");
            if (fn_selectLoadData) {
                fn_selectLoadData(self);
            } else {
                NSLog(@"[TOP] fn_selectLoadData not resolved; cannot open Load dialog");
            }
            return;

        case 3: // BNID
            NSLog(@"[TOP] BNID selected");
            return;

        default:
            if (orig_menuGameSelectCallback) {
                orig_menuGameSelectCallback(self, sender);
            }
            return;
    }
}

// ---------------------------------------------------------------------
// Network / IAP / notice stubs
// ---------------------------------------------------------------------

static int my_IsBusy(TopHttpHelper *self) {
    (void)self;
    return 0;
}

static int my_RequestCheckVersion(TopHttpHelper *self) {
    markHttpIdle(self);
    NSLog(@"[TOP] RequestCheckVersion -> success");
    return 1;
}

static int my_ParseCheckVersion(TopHttpHelper *self, StdString *response) {
    (void)self;
    (void)response;
    NSLog(@"[TOP] ParseCheckVersion -> current");
    return 0;
}

static int my_RequestLogin(TopHttpHelper *self) {
    markHttpIdle(self);
    NSLog(@"[TOP] RequestLogin -> success");
    return 1;
}

static int my_parse_login_data_result(StdString *response) {
    (void)response;
    NSLog(@"[TOP] parse_login_data_result -> success");
    return 1;
}

static int my_RequestGetSlot(TopHttpHelper *self) {
    markHttpIdle(self);
    NSLog(@"[TOP] RequestGetSlot -> success");
    return 1;
}

// Slot type 0 is quick/continue; slot type 1 is the normal save slot.
static int my_parse_slot_data_result(StdString *response) {
    (void)response;
    NSLog(@"[TOP] parse_slot_data_result -> normal save available");

    if (gContinueOpen) *gContinueOpen = 0;
    if (gLoadOpen)     *gLoadOpen     = 1;

    return 1;
}

static int my_IAP_IsBusy(void *self) {
    (void)self;
    return 0;
}

static int my_IAP_RequestItemList(void *self) {
    (void)self;
    NSLog(@"[TOP] RequestItemList -> success");
    return 1;
}

// ---------------------------------------------------------------------
// Free archival shop
// ---------------------------------------------------------------------
// Keep one virtual copy of each consumable available; native item effects still run.
static int my_getRMBItemCountByItem(StdString *item) {
    (void)item;
    return 1;
}

static int my_IAP_UsedItem(void *self, StdString *item, int count) {
    (void)self;
    (void)item;
    NSLog(@"[TOP] Free Store: UsedItem(count=%d)", count);
    return 1;
}

static int my_IAP_RequestBuy(void *self, int serverID) {
    (void)self;
    NSLog(@"[TOP] Free Store: RequestBuy(serverID=%d)", serverID);
    return 1;
}

static int my_IAP_RequestSycnItem(void *self) {
    // GetStep() reads self+0x8; the save flow expects step 7 after item sync.
    if (self) {
        *(int *)((uint8_t *)self + IAP_STEP_OFFSET) = IAP_SYNC_SUCCESS_STEP;
    }
    NSLog(@"[TOP] Free Store: RequestSycnItem -> step %d", IAP_SYNC_SUCCESS_STEP);
    return 1;
}

// Choice 0 is Use, 1 is Purchase, and 2 is Cancel.
static void my_TopMenuBuy_menuSureCallback(TopMenuBuy *self, void *sender) {
    if (!orig_TopMenuBuy_menuSureCallback || !sender) {
        if (orig_TopMenuBuy_menuSureCallback) {
            orig_TopMenuBuy_menuSureCallback(self, sender);
        }
        return;
    }

    int *choicePtr = (int *)((uint8_t *)sender + MENU_SELECTION_OFFSET);
    int choice = *choicePtr;

    if (choice == 1) {
        NSLog(@"[TOP] Free Store: Purchase -> Cancel");
        *choicePtr = 2;
    }

    // The native callback may destroy sender while closing the popup.
    orig_TopMenuBuy_menuSureCallback(self, sender);
}

static int my_RequestGetItemPrice(TopHttpHelper *self) {
    markHttpIdle(self);
    NSLog(@"[TOP] RequestGetItemPrice -> success");
    return 1;
}

static int my_parse_price_data_result(StdString *response) {
    (void)response;
    NSLog(@"[TOP] parse_price_data_result -> success");
    return 1;
}

static int my_RequestGetNotice(TopHttpHelper *self) {
    markHttpIdle(self);
    NSLog(@"[TOP] RequestGetNotice -> success");
    return 1;
}

static int my_parse_url_data_result(StdString *response) {
    (void)response;
    NSLog(@"[TOP] parse_url_data_result -> success");
    return 1;
}

static int my_RequestGetPrivateNotice(TopHttpHelper *self) {
    markHttpIdle(self);
    NSLog(@"[TOP] RequestGetPrivateNotice -> success");
    return 1;
}

static int my_Parseprivatenotice(TopHttpHelper *self, StdString *response) {
    (void)self;
    (void)response;
    NSLog(@"[TOP] Parseprivatenotice -> success");
    return 1;
}

// ---------------------------------------------------------------------
// Local save support
// ---------------------------------------------------------------------

static int my_RequestSave(TopHttpHelper *self, int slot, StdString *saveData) {
    (void)self;
    (void)saveData;
    NSLog(@"[TOP] RequestSave(slot=%d) -> local-only", slot);
    return 1;
}

static int my_parse_save_data_result(StdString *response) {
    (void)response;
    NSLog(@"[TOP] parse_save_data_result -> success");
    return 1;
}

static void my_TopMenuSave_linkNet(TopMenuSave *self) {
    NSLog(@"[TOP] TopMenuSave::linkNet -> success");

    if (fn_TopMenuSave_linkSuccess) {
        fn_TopMenuSave_linkSuccess(self);
    } else if (orig_TopMenuSave_linkNet) {
        orig_TopMenuSave_linkNet(self);
    }
}

// ---------------------------------------------------------------------
// Local load support
// ---------------------------------------------------------------------

static int my_RequestLoad(TopHttpHelper *self, int slot) {
    (void)self;
    NSLog(@"[TOP] RequestLoad(slot=%d) -> local-only", slot);
    return 1;
}

// The native parser expects exactly 0x2000 bytes in dst.
static int my_parse_load_data_result(StdString *response, void *dst) {
    (void)response;
    if (!dst) return 0;

    NSArray *paths = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    if ([paths count] == 0) return 0;

    NSString *docs = [paths objectAtIndex:0];
    NSString *path = [docs stringByAppendingPathComponent:@"savedata.bin"];

    NSData *payload = [NSData dataWithContentsOfFile:path];
    if (!payload || payload.length == 0) {
        NSLog(@"[TOP] No local savedata.bin at %@ (len=%lu)",
              path, (unsigned long)payload.length);
        return 0;
    }

    if (payload.length < LOCAL_SAVE_SIZE) {
        NSLog(@"[TOP] Local savedata.bin is too short at %@ (len=%lu, need=8192)",
              path, (unsigned long)payload.length);
        return 0;
    }

    const size_t copyLen = LOCAL_SAVE_SIZE;
    memcpy(dst, payload.bytes, copyLen);

    NSLog(@"[TOP] Loaded local save from %@ (copied=%zu, fileLen=%lu)",
          path, copyLen, (unsigned long)payload.length);

    return 1;
}

// ---------------------------------------------------------------------
// Shop price readiness
// ---------------------------------------------------------------------
static BOOL my_IAPModuler_isGetAllPrices(id self, SEL selector) {
    (void)self;
    (void)selector;
    NSLog(@"[TOP] Free Store: IAPModuler price gate -> ready");
    return YES;
}

static void my_IAPModuler_GetAllPrice(id self, SEL selector) {
    (void)self;
    (void)selector;
    NSLog(@"[TOP] Free Store: GetAllPrice");
}

// ---------------------------------------------------------------------
// Permanent StoreKit feature entitlements.
// ---------------------------------------------------------------------

static BOOL my_MKStoreManager_isFeaturePurchased(id self, SEL selector, id feature) {
    (void)self;
    (void)selector;
    NSLog(@"[TOP] Free Store: feature %@ treated as purchased", feature);
    return YES;
}

static void my_MKStoreManager_buyFeature(id self, SEL selector, id feature) {
    (void)self;
    (void)selector;
    NSLog(@"[TOP] Free Store: buyFeature:%@", feature);
}

// ---------------------------------------------------------------------
// ctor
// ---------------------------------------------------------------------

%ctor {
    NSLog(@"[TOP] TalesOfPaths v1.06 loaded");

    void *sym;
    void *slotParserSym = findSymbol("_Z22parse_slot_data_resultSs");

    // The filter targets every executable named TOP, so refuse to install any
    // hooks unless this is one of the two layouts validated for this release.
    if (!slotParserSym || !configureSlotGlobals(slotParserSym)) {
        NSLog(@"[TOP] Unsupported TOP build; no hooks installed");
        return;
    }

    // Shop price-readiness gate.
    Class iapModulerClass = (Class)objc_getClass("IAPModuler");
    if (iapModulerClass) {
        SEL readySel = sel_registerName("isGetAllPrices");
        SEL fetchSel = sel_registerName("GetAllPrice");

        Method readyMethod = class_getInstanceMethod(iapModulerClass, readySel);
        if (readyMethod) {
            MSHookMessageEx(iapModulerClass, readySel,
                            (IMP)&my_IAPModuler_isGetAllPrices,
                            (IMP *)&orig_IAPModuler_isGetAllPrices);
            NSLog(@"[TOP] Free Store: hooked -[IAPModuler isGetAllPrices] -> YES");
        } else {
            NSLog(@"[TOP] Free Store: -[IAPModuler isGetAllPrices] not found");
        }

        Method fetchMethod = class_getInstanceMethod(iapModulerClass, fetchSel);
        if (fetchMethod) {
            MSHookMessageEx(iapModulerClass, fetchSel,
                            (IMP)&my_IAPModuler_GetAllPrice,
                            (IMP *)&orig_IAPModuler_GetAllPrice);
            NSLog(@"[TOP] Free Store: hooked -[IAPModuler GetAllPrice]");
        } else {
            NSLog(@"[TOP] Free Store: -[IAPModuler GetAllPrice] not found");
        }
    } else {
        NSLog(@"[TOP] Free Store: IAPModuler class not found");
    }

    // Permanent feature entitlements.
    Class mkStoreClass = (Class)objc_getClass("MKStoreManager");
    if (mkStoreClass) {
        Class mkStoreMeta = object_getClass((id)mkStoreClass);

        SEL purchasedSel = sel_registerName("isFeaturePurchased:");
        SEL buySel = sel_registerName("buyFeature:");

        Method purchasedMethod = class_getClassMethod(mkStoreClass, purchasedSel);
        if (purchasedMethod && mkStoreMeta) {
            MSHookMessageEx(mkStoreMeta, purchasedSel,
                            (IMP)&my_MKStoreManager_isFeaturePurchased,
                            (IMP *)&orig_MKStoreManager_isFeaturePurchased);
            NSLog(@"[TOP] Free Store: hooked +[MKStoreManager isFeaturePurchased:]");
        }

        Method buyMethod = class_getInstanceMethod(mkStoreClass, buySel);
        if (buyMethod) {
            MSHookMessageEx(mkStoreClass, buySel,
                            (IMP)&my_MKStoreManager_buyFeature,
                            (IMP *)&orig_MKStoreManager_buyFeature);
            NSLog(@"[TOP] Free Store: hooked -[MKStoreManager buyFeature:]");
        }
    } else {
        NSLog(@"[TOP] Free Store: MKStoreManager class not found");
    }

    // Bootstrap/network state.
    sym = findSymbol("_ZN13TopHttpHelper6IsBusyEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_IsBusy, (void **)&orig_IsBusy);
        NSLog(@"[TOP] Hooked IsBusy");
    } else {
        NSLog(@"[TOP] Failed to find IsBusy");
    }

    sym = findSymbol("_ZN13TopHttpHelper19RequestCheckVersionEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_RequestCheckVersion, (void **)&orig_RequestCheckVersion);
        NSLog(@"[TOP] Hooked RequestCheckVersion");
    } else {
        NSLog(@"[TOP] Failed to find RequestCheckVersion");
    }

    sym = findSymbol("_ZN13TopHttpHelper17ParseCheckVersionESs");
    if (sym) {
        MSHookFunction(sym, (void *)&my_ParseCheckVersion, (void **)&orig_ParseCheckVersion);
        NSLog(@"[TOP] Hooked ParseCheckVersion");
    } else {
        NSLog(@"[TOP] Failed to find ParseCheckVersion");
    }

    sym = findSymbol("_ZN13TopHttpHelper12RequestLoginEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_RequestLogin, (void **)&orig_RequestLogin);
        NSLog(@"[TOP] Hooked RequestLogin");
    } else {
        NSLog(@"[TOP] Failed to find RequestLogin");
    }

    sym = findSymbol("_Z23parse_login_data_resultSs");
    if (sym) {
        MSHookFunction(sym, (void *)&my_parse_login_data_result, (void **)&orig_parse_login_data_result);
        NSLog(@"[TOP] Hooked parse_login_data_result");
    } else {
        NSLog(@"[TOP] Failed to find parse_login_data_result");
    }

    sym = findSymbol("_ZN13TopHttpHelper14RequestGetSlotEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_RequestGetSlot, (void **)&orig_RequestGetSlot);
        NSLog(@"[TOP] Hooked RequestGetSlot");
    } else {
        NSLog(@"[TOP] Failed to find RequestGetSlot");
    }

    // Slot parser and build-specific static title-menu gates.
    MSHookFunction(slotParserSym, (void *)&my_parse_slot_data_result,
                                  (void **)&orig_parse_slot_data_result);
    NSLog(@"[TOP] Hooked parse_slot_data_result");

    // IAP state and free-store hooks.
    sym = findSymbol("_ZN12TopIAPHelper15RequestItemListEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_IAP_RequestItemList, (void **)&orig_IAP_RequestItemList);
        NSLog(@"[TOP] Hooked RequestItemList");
    } else {
        NSLog(@"[TOP] Failed to find RequestItemList");
    }

    sym = findSymbol("_ZN12TopIAPHelper6IsBusyEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_IAP_IsBusy, (void **)&orig_IAP_IsBusy);
        NSLog(@"[TOP] Hooked IAP IsBusy");
    } else {
        NSLog(@"[TOP] Failed to find IAP IsBusy");
    }

    sym = findSymbol("_Z21getRMBItemCountByItemRKSs");
    if (sym) {
        MSHookFunction(sym, (void *)&my_getRMBItemCountByItem,
                           (void **)&orig_getRMBItemCountByItem);
        NSLog(@"[TOP] Free Store: hooked getRMBItemCountByItem");
    } else {
        NSLog(@"[TOP] Free Store: failed to find getRMBItemCountByItem");
    }

    sym = findSymbol("_ZN12TopIAPHelper8UsedItemESsi");
    if (sym) {
        MSHookFunction(sym, (void *)&my_IAP_UsedItem, (void **)&orig_IAP_UsedItem);
        NSLog(@"[TOP] Free Store: hooked TopIAPHelper::UsedItem");
    } else {
        NSLog(@"[TOP] Free Store: failed to find TopIAPHelper::UsedItem");
    }

    sym = findSymbol("_ZN12TopIAPHelper10RequestBuyEi");
    if (sym) {
        MSHookFunction(sym, (void *)&my_IAP_RequestBuy, (void **)&orig_IAP_RequestBuy);
        NSLog(@"[TOP] Free Store: hooked TopIAPHelper::RequestBuy");
    } else {
        NSLog(@"[TOP] Free Store: failed to find TopIAPHelper::RequestBuy");
    }

    sym = findSymbol("_ZN12TopIAPHelper15RequestSycnItemEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_IAP_RequestSycnItem,
                           (void **)&orig_IAP_RequestSycnItem);
        NSLog(@"[TOP] Free Store: hooked TopIAPHelper::RequestSycnItem");
    } else {
        NSLog(@"[TOP] Free Store: failed to find TopIAPHelper::RequestSycnItem");
    }

    sym = findSymbol("_ZN10TopMenuBuy16menuSureCallbackEPN7cocos2d8CCObjectE");
    if (sym) {
        MSHookFunction(sym, (void *)&my_TopMenuBuy_menuSureCallback,
                           (void **)&orig_TopMenuBuy_menuSureCallback);
        NSLog(@"[TOP] Free Store: hooked TopMenuBuy::menuSureCallback");
    } else {
        NSLog(@"[TOP] Free Store: failed to find TopMenuBuy::menuSureCallback");
    }

    // Notice and price responses.
    sym = findSymbol("_ZN13TopHttpHelper19RequestGetItemPriceEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_RequestGetItemPrice, (void **)&orig_RequestGetItemPrice);
        NSLog(@"[TOP] Hooked RequestGetItemPrice");
    } else {
        NSLog(@"[TOP] Failed to find RequestGetItemPrice");
    }

    sym = findSymbol("_Z23parse_price_data_resultSs");
    if (sym) {
        MSHookFunction(sym, (void *)&my_parse_price_data_result, (void **)&orig_parse_price_data_result);
        NSLog(@"[TOP] Hooked parse_price_data_result");
    } else {
        NSLog(@"[TOP] Failed to find parse_price_data_result");
    }

    sym = findSymbol("_ZN13TopHttpHelper16RequestGetNoticeEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_RequestGetNotice, (void **)&orig_RequestGetNotice);
        NSLog(@"[TOP] Hooked RequestGetNotice");
    } else {
        NSLog(@"[TOP] Failed to find RequestGetNotice");
    }

    sym = findSymbol("_Z21parse_url_data_resultSs");
    if (sym) {
        MSHookFunction(sym, (void *)&my_parse_url_data_result, (void **)&orig_parse_url_data_result);
        NSLog(@"[TOP] Hooked parse_url_data_result");
    } else {
        NSLog(@"[TOP] Failed to find parse_url_data_result");
    }

    sym = findSymbol("_ZN13TopHttpHelper23RequestGetPrivateNoticeEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_RequestGetPrivateNotice, (void **)&orig_RequestGetPrivateNotice);
        NSLog(@"[TOP] Hooked RequestGetPrivateNotice");
    } else {
        NSLog(@"[TOP] Failed to find RequestGetPrivateNotice");
    }

    sym = findSymbol("_ZN13TopHttpHelper18ParseprivatenoticeESs");
    if (sym) {
        MSHookFunction(sym, (void *)&my_Parseprivatenotice, (void **)&orig_Parseprivatenotice);
        NSLog(@"[TOP] Hooked Parseprivatenotice");
    } else {
        NSLog(@"[TOP] Failed to find Parseprivatenotice");
    }

    // Title menu.
    sym = findSymbol("_ZN12TopMenuTitle12popNewGameUIEv");
    if (sym) {
        fn_popNewGameUI = (void (*)(TopMenuTitle *))sym;
        NSLog(@"[TOP] Resolved TopMenuTitle::popNewGameUI");
    }

    sym = findSymbol("_ZN12TopMenuTitle14selectLoadDataEv");
    if (sym) {
        fn_selectLoadData = (void (*)(TopMenuTitle *))sym;
        NSLog(@"[TOP] Resolved TopMenuTitle::selectLoadData");
    }

    sym = findSymbol("_ZN12TopMenuTitle22menuGameSelectCallbackEPN7cocos2d8CCObjectE");
    if (sym) {
        MSHookFunction(sym, (void *)&my_menuGameSelectCallback,
                           (void **)&orig_menuGameSelectCallback);
        NSLog(@"[TOP] Hooked menuGameSelectCallback (gate patched)");
    }

    // Save/load hooks.

    sym = findSymbol("_ZN13TopHttpHelper11RequestSaveEiSs");
    if (sym) {
        MSHookFunction(sym, (void *)&my_RequestSave, (void **)&orig_RequestSave);
        NSLog(@"[TOP] Hooked RequestSave");
    }

    sym = findSymbol("_Z22parse_save_data_resultSs");
    if (sym) {
        MSHookFunction(sym, (void *)&my_parse_save_data_result,
                           (void **)&orig_parse_save_data_result);
        NSLog(@"[TOP] Hooked parse_save_data_result");
    } else {
        NSLog(@"[TOP] Failed to find parse_save_data_result");
    }

    sym = findSymbol("_ZN11TopMenuSave11linkSuccessEv");
    if (sym) {
        fn_TopMenuSave_linkSuccess = (void (*)(TopMenuSave *))sym;
        NSLog(@"[TOP] Resolved TopMenuSave::linkSuccess");
    }

    sym = findSymbol("_ZN11TopMenuSave7linkNetEv");
    if (sym) {
        MSHookFunction(sym, (void *)&my_TopMenuSave_linkNet,
                           (void **)&orig_TopMenuSave_linkNet);
        NSLog(@"[TOP] Hooked TopMenuSave::linkNet");
    }

    sym = findSymbol("_ZN13TopHttpHelper11RequestLoadEi");
    if (sym) {
        MSHookFunction(sym, (void *)&my_RequestLoad, (void **)&orig_RequestLoad);
        NSLog(@"[TOP] Hooked RequestLoad");
    }

    sym = findSymbol("_Z22parse_load_data_resultSsPc");
    if (sym) {
        MSHookFunction(sym, (void *)&my_parse_load_data_result,
                           (void **)&orig_parse_load_data_result);
        NSLog(@"[TOP] Hooked parse_load_data_result");
    }
}
