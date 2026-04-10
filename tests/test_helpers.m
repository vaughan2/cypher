#import <Foundation/Foundation.h>
#import "../hotkey_helpers.h"

static int sPass = 0;
static int sFail = 0;

#define ASSERT(cond, label) do { \
    if (cond) { \
        NSLog(@"  PASS  %s", label); \
        sPass++; \
    } else { \
        NSLog(@"  FAIL  %s", label); \
        sFail++; \
    } \
} while (0)

#define SECTION(name) NSLog(@"\n%s", name)

// ── carbonModsToCGFlags ──────────────────────────────────────────────────────

static void testCarbonModsToCGFlags(void) {
    SECTION("carbonModsToCGFlags");

    ASSERT(carbonModsToCGFlags(cmdKey)     == kCGEventFlagMaskCommand,   "cmdKey     → Command");
    ASSERT(carbonModsToCGFlags(shiftKey)   == kCGEventFlagMaskShift,     "shiftKey   → Shift");
    ASSERT(carbonModsToCGFlags(optionKey)  == kCGEventFlagMaskAlternate, "optionKey  → Alternate");
    ASSERT(carbonModsToCGFlags(controlKey) == kCGEventFlagMaskControl,   "controlKey → Control");

    CGEventFlags combo = kCGEventFlagMaskCommand | kCGEventFlagMaskShift;
    ASSERT(carbonModsToCGFlags(cmdKey | shiftKey) == combo, "cmd+shift combination");

    CGEventFlags all = kCGEventFlagMaskCommand | kCGEventFlagMaskShift |
                       kCGEventFlagMaskAlternate | kCGEventFlagMaskControl;
    ASSERT(carbonModsToCGFlags(cmdKey | shiftKey | optionKey | controlKey) == all,
           "all four modifiers");

    ASSERT(carbonModsToCGFlags(0) == 0, "no modifiers → 0");
}

// ── keyCodeDisplayString ─────────────────────────────────────────────────────

static void testKeyCodeDisplayString(void) {
    SECTION("keyCodeDisplayString");

    // Letters
    ASSERT([keyCodeDisplayString(kVK_ANSI_A) isEqualToString:@"A"], "kVK_ANSI_A → A");
    ASSERT([keyCodeDisplayString(kVK_ANSI_L) isEqualToString:@"L"], "kVK_ANSI_L → L");
    ASSERT([keyCodeDisplayString(kVK_ANSI_Z) isEqualToString:@"Z"], "kVK_ANSI_Z → Z");

    // Digits
    ASSERT([keyCodeDisplayString(kVK_ANSI_0) isEqualToString:@"0"], "kVK_ANSI_0 → 0");
    ASSERT([keyCodeDisplayString(kVK_ANSI_9) isEqualToString:@"9"], "kVK_ANSI_9 → 9");

    // Function keys
    ASSERT([keyCodeDisplayString(kVK_F1)  isEqualToString:@"F1"],  "kVK_F1  → F1");
    ASSERT([keyCodeDisplayString(kVK_F12) isEqualToString:@"F12"], "kVK_F12 → F12");

    // Special keys
    ASSERT([keyCodeDisplayString(kVK_Space)  isEqualToString:@"Space"], "kVK_Space  → Space");
    ASSERT([keyCodeDisplayString(kVK_Return) isEqualToString:@"↩"],     "kVK_Return → ↩");
    ASSERT([keyCodeDisplayString(kVK_Delete) isEqualToString:@"⌫"],     "kVK_Delete → ⌫");

    // Unknown key code falls back to "(N)"
    NSString *unknown = keyCodeDisplayString(200);
    ASSERT([unknown hasPrefix:@"("] && [unknown hasSuffix:@")"], "unknown keycode → (N) format");
}

// ── hotkeyDisplayString ──────────────────────────────────────────────────────

static void testHotkeyDisplayString(void) {
    SECTION("hotkeyDisplayString");

    // Default hotkey
    ASSERT([hotkeyDisplayString(kVK_ANSI_L, cmdKey | shiftKey) isEqualToString:@"⇧⌘L"],
           "default hotkey → ⇧⌘L");

    // Single modifier
    ASSERT([hotkeyDisplayString(kVK_ANSI_L, cmdKey)     isEqualToString:@"⌘L"],   "⌘L");
    ASSERT([hotkeyDisplayString(kVK_ANSI_L, shiftKey)   isEqualToString:@"⇧L"],   "⇧L");
    ASSERT([hotkeyDisplayString(kVK_ANSI_L, optionKey)  isEqualToString:@"⌥L"],   "⌥L");
    ASSERT([hotkeyDisplayString(kVK_ANSI_L, controlKey) isEqualToString:@"⌃L"],   "⌃L");

    // Modifier ordering must be ⌃⌥⇧⌘ (standard macOS order)
    ASSERT([hotkeyDisplayString(kVK_ANSI_L,
                                 controlKey | optionKey | shiftKey | cmdKey)
            isEqualToString:@"⌃⌥⇧⌘L"], "all modifiers → ⌃⌥⇧⌘L");

    // Function key
    ASSERT([hotkeyDisplayString(kVK_F5, cmdKey) isEqualToString:@"⌘F5"], "⌘F5");
}

// ── NSUserDefaults roundtrip ─────────────────────────────────────────────────

static void testUserDefaultsRoundtrip(void) {
    SECTION("NSUserDefaults roundtrip");

    NSString *domain = @"com.vaughan2.cypher.tests";
    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:domain];

    UInt32 writeCode = kVK_ANSI_K;
    UInt32 writeMods = cmdKey | optionKey;

    [ud setInteger:writeCode forKey:@"hotkeyKeyCode"];
    [ud setInteger:writeMods forKey:@"hotkeyModifiers"];
    [ud synchronize];

    UInt32 readCode = (UInt32)[ud integerForKey:@"hotkeyKeyCode"];
    UInt32 readMods = (UInt32)[ud integerForKey:@"hotkeyModifiers"];

    ASSERT(readCode == writeCode, "keyCode survives write→read");
    ASSERT(readMods == writeMods, "modifiers survive write→read");
    ASSERT(readCode != 0,         "keyCode is non-zero after write");

    // Non-existent key returns 0 (the default value)
    UInt32 missing = (UInt32)[ud integerForKey:@"nonExistentKey"];
    ASSERT(missing == 0, "missing key returns 0");

    // Cleanup
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:domain];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// ── Entry point ──────────────────────────────────────────────────────────────

int main(void) {
    @autoreleasepool {
        NSLog(@"Cypher unit tests");
        NSLog(@"─────────────────────────────────────────");

        testCarbonModsToCGFlags();
        testKeyCodeDisplayString();
        testHotkeyDisplayString();
        testUserDefaultsRoundtrip();

        NSLog(@"\n─────────────────────────────────────────");
        if (sFail == 0) {
            NSLog(@"✓  All %d tests passed.", sPass);
        } else {
            NSLog(@"✗  %d failed, %d passed.", sFail, sPass);
        }
        return sFail > 0 ? 1 : 0;
    }
}
