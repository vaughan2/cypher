#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <QuartzCore/QuartzCore.h>
#import <ServiceManagement/ServiceManagement.h>

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
#define HOTKEY_KEYCODE   kVK_ANSI_L
#define HOTKEY_MODIFIERS (cmdKey | shiftKey)

#define CELL_W         14.0f
#define CELL_H         18.0f
#define FONT_SIZE      15.0f
#define FPS            60.0

// Mouse ripple effect
#define RIPPLE_RADIUS  110.0f
#define RIPPLE_TIERS   5
#define ALPHA_LEVELS   32      // quantised brightness steps for color cache
#define GLOW_LEVELS    16      // steps for the ripple→white glow blend

// ---------------------------------------------------------------------------
// Matrix character set — half-width katakana + digits + symbols
// ---------------------------------------------------------------------------
static const unichar kMatrixChars[] = {
    0xFF66,0xFF67,0xFF68,0xFF69,0xFF6A,0xFF6B,0xFF6C,0xFF6D,0xFF6E,0xFF6F,
    0xFF70,0xFF71,0xFF72,0xFF73,0xFF74,0xFF75,0xFF76,0xFF77,0xFF78,0xFF79,
    0xFF7A,0xFF7B,0xFF7C,0xFF7D,0xFF7E,0xFF7F,0xFF80,0xFF81,0xFF82,0xFF83,
    0xFF84,0xFF85,0xFF86,0xFF87,0xFF88,0xFF89,0xFF8A,0xFF8B,0xFF8C,0xFF8D,
    0xFF8E,0xFF8F,0xFF90,0xFF91,0xFF92,0xFF93,0xFF94,0xFF95,0xFF96,0xFF97,
    0xFF98,0xFF99,0xFF9A,0xFF9B,0xFF9C,0xFF9D,
    '0','1','2','3','4','5','6','7','8','9',
    'Z','T','Y','U','I','O','P','A','S','D',
    '!','@','#','$','%','&','*','+','-','=','<','>','?',
};
static const int kMatrixCharCount =
    (int)(sizeof(kMatrixChars) / sizeof(kMatrixChars[0]));

// ---------------------------------------------------------------------------
// Per-column drop state
// ---------------------------------------------------------------------------
typedef struct {
    float headY;      // current head row (float for smooth scroll)
    float speed;      // rows per tick
    int   trailLen;   // how many rows the lit trail spans
    int   waitFrames; // countdown before this column activates
} Drop;

// ---------------------------------------------------------------------------
// Matrix animated view
// ---------------------------------------------------------------------------
@interface MatrixView : NSView {
    NSTimer             *_timer;       // fallback for macOS < 14
    CADisplayLink       *_displayLink API_AVAILABLE(macos(14.0)); // display-synced timer
    int                  _cols, _rows;
    Drop                *_drops;
    uint8_t             *_charIdx;    // [col*_rows+row]
    float               *_brightness; // [col*_rows+row]
    float               *_ripple;     // [col*_rows+row] cursor energy, decays
    float               *_cellCX;     // [col] pre-computed cell centre X
    float               *_cellCY;     // [row] pre-computed cell centre Y
    NSFont              *_font;
    NSFont              *_rippleFonts[RIPPLE_TIERS];
    NSString            *_charStrings[128];
    NSMutableDictionary *_drawAttrs;
    NSPoint              _mousePos;
}
@end

@implementation MatrixView

static float randFloat(float lo, float hi) {
    return lo + (hi - lo) * ((float)arc4random() / (float)UINT32_MAX);
}

- (void)resetDrop:(int)col {
    _drops[col].speed      = randFloat(0.25f, 0.65f);
    _drops[col].trailLen   = (int)randFloat(8, 24);
    _drops[col].headY      = -_drops[col].trailLen;
    _drops[col].waitFrames = (int)randFloat(0, FPS * 3);
}

- (void)setupGrid {
    NSRect b = self.bounds;
    _cols = MAX(1, (int)(b.size.width  / CELL_W) + 1);
    _rows = MAX(1, (int)(b.size.height / CELL_H) + 1);

    free(_drops);      _drops      = calloc(_cols, sizeof(Drop));
    free(_charIdx);    _charIdx    = calloc(_cols * _rows, sizeof(uint8_t));
    free(_brightness); _brightness = calloc(_cols * _rows, sizeof(float));
    free(_ripple);     _ripple     = calloc(_cols * _rows, sizeof(float));
    free(_cellCX);     _cellCX     = calloc(_cols, sizeof(float));
    free(_cellCY);     _cellCY     = calloc(_rows, sizeof(float));

    // Pre-compute cell centres — constant for the lifetime of this grid
    float height = self.bounds.size.height;
    for (int c = 0; c < _cols; c++) _cellCX[c] = c * CELL_W + CELL_W * 0.5f;
    for (int r = 0; r < _rows; r++) _cellCY[r] = height - r * CELL_H - CELL_H * 0.5f;

    for (int c = 0; c < _cols; c++) {
        [self resetDrop:c];
        _drops[c].waitFrames = (int)randFloat(0, FPS * 5);
        for (int r = 0; r < _rows; r++)
            _charIdx[c * _rows + r] = arc4random_uniform(kMatrixCharCount);
    }
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    _font = [NSFont fontWithName:@"Courier New" size:FONT_SIZE];
    if (!_font) _font = [NSFont monospacedSystemFontOfSize:FONT_SIZE weight:NSFontWeightRegular];

    float scales[RIPPLE_TIERS] = {1.0f, 1.5f, 2.2f, 3.1f, 4.2f};
    for (int i = 0; i < RIPPLE_TIERS; i++) {
        float sz = FONT_SIZE * scales[i];
        _rippleFonts[i] = [NSFont fontWithName:@"Courier New" size:sz];
        if (!_rippleFonts[i])
            _rippleFonts[i] = [NSFont monospacedSystemFontOfSize:sz weight:NSFontWeightRegular];
    }

    // Pre-build one NSString per character — reused every frame, no alloc in hot path
    for (int i = 0; i < kMatrixCharCount; i++)
        _charStrings[i] = [NSString stringWithCharacters:&kMatrixChars[i] length:1];

    // Reusable attribute dict — mutated in-place each cell
    _drawAttrs = [@{ NSFontAttributeName: _font,
                     NSForegroundColorAttributeName: [NSColor whiteColor] } mutableCopy];

    // Layer-backed rendering lets the GPU composite the view
    self.wantsLayer = YES;

    [self setupGrid];
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    free(_drops); free(_charIdx); free(_brightness); free(_ripple);
    free(_cellCX); free(_cellCY);
    // ARC handles super dealloc
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        if (@available(macOS 14.0, *)) {
            // On macOS, CADisplayLink is created via NSView, not as a class method
            _displayLink = [self displayLinkWithTarget:self selector:@selector(tick:)];
            _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
            [_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                               forMode:NSRunLoopCommonModes];
        } else {
            _timer = [NSTimer scheduledTimerWithTimeInterval:1.0/FPS
                                                      target:self
                                                    selector:@selector(tick:)
                                                    userInfo:nil
                                                     repeats:YES];
            [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
        }
    } else {
        [_displayLink invalidate]; _displayLink = nil;
        [_timer invalidate];       _timer = nil;
    }
}

- (void)tick:(NSTimer *)t {
    for (int c = 0; c < _cols; c++) {
        Drop *d = &_drops[c];

        if (d->waitFrames > 0) {
            d->waitFrames--;
            continue;
        }

        d->headY += d->speed;

        // Update brightness for every row in this column
        for (int r = 0; r < _rows; r++) {
            float dist = d->headY - r;            // positive = head is below row r
            float bright;
            if (dist < 0 || dist > d->trailLen) {
                bright = 0.0f;
            } else if (dist < 1.0f) {
                bright = 1.0f;                     // head: white flash
            } else {
                bright = 1.0f - (dist / d->trailLen);
            }
            // Decay existing brightness rather than hard-overwriting,
            // so old trails fade out after the drop passes.
            float existing = _brightness[c * _rows + r];
            _brightness[c * _rows + r] = MAX(bright, existing * 0.85f);

            if (bright > 0.0f && arc4random_uniform(6) == 0)
                _charIdx[c * _rows + r] = arc4random_uniform(kMatrixCharCount);
        }

        // Reset when drop has fully scrolled off the bottom
        if (d->headY - d->trailLen > _rows) {
            [self resetDrop:c];
        }
    }

    // ── Cursor position ──────────────────────────────────────────────────────
    // [NSEvent mouseLocation] stays current because we pass kCGEventMouseMoved
    // through the tap. It returns global Cocoa screen coords (bottom-left origin).
    if (self.window) {
        NSPoint screen = [NSEvent mouseLocation];
        NSPoint win    = [self.window convertPointFromScreen:screen];
        NSPoint local  = [self convertPoint:win fromView:nil];
        _mousePos      = local;

        // ── Ripple decay + inject energy at cursor ────────────────────────────
        float height = self.bounds.size.height;
        int   count  = _cols * _rows;

        // Decay all existing ripple energy
        for (int i = 0; i < count; i++) _ripple[i] *= 0.88f;

        // Boost cells within RIPPLE_RADIUS using pre-computed centres
        float rr = RIPPLE_RADIUS * RIPPLE_RADIUS;
        for (int c = 0; c < _cols; c++) {
            float dx = _cellCX[c] - local.x;
            if (dx * dx > rr) continue; // skip whole column
            for (int r = 0; r < _rows; r++) {
                float dy = _cellCY[r] - local.y;
                float dd = dx * dx + dy * dy;
                if (dd < rr) {
                    float energy = 1.0f - (sqrtf(dd) / RIPPLE_RADIUS);
                    int   idx    = c * _rows + r;
                    // Lerp toward target — smooth onset matches smooth decay
                    _ripple[idx] += (energy - _ripple[idx]) * 0.30f;
                }
            }
        }
    }

    [self setNeedsDisplay:YES];
}

// Pre-built color table: sColorTable[tier][alphaLevel]
// tier 0=head, 1=bright, 2=mid, 3=dim  — eliminates colorWithAlphaComponent per cell
// sGlowColors[0..GLOW_LEVELS-1] — pre-blended bright→white, at alpha 1.0
// eliminates blendedColorWithFraction per ripple cell
static NSColor *sColorTable[4][ALPHA_LEVELS];
static NSColor *sGlowColors[GLOW_LEVELS];

+ (void)initialize {
    if (self != [MatrixView class]) return;

    NSColor *base[4] = {
        [NSColor colorWithCalibratedRed:0.9 green:1.0 blue:0.9  alpha:1.0], // head
        [NSColor colorWithCalibratedRed:0.0 green:1.0 blue:0.25 alpha:1.0], // bright
        [NSColor colorWithCalibratedRed:0.0 green:0.8 blue:0.15 alpha:1.0], // mid
        [NSColor colorWithCalibratedRed:0.0 green:0.5 blue:0.08 alpha:1.0], // dim
    };
    for (int t = 0; t < 4; t++)
        for (int a = 0; a < ALPHA_LEVELS; a++)
            sColorTable[t][a] = [base[t] colorWithAlphaComponent:(float)a / (ALPHA_LEVELS - 1)];

    NSColor *white = base[0];
    NSColor *green = base[1];
    for (int i = 0; i < GLOW_LEVELS; i++) {
        float t = (float)i / (GLOW_LEVELS - 1);
        sGlowColors[i] = [green blendedColorWithFraction:t ofColor:white];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor blackColor] setFill];
    NSRectFill(self.bounds);

    float height = self.bounds.size.height;

    for (int c = 0; c < _cols; c++) {
        float headY = _drops[c].headY;

        for (int r = 0; r < _rows; r++) {
            float bright = _brightness[c * _rows + r];
            if (bright < 0.04f) continue;

            float ripple        = _ripple[c * _rows + r];
            float effectiveBright = MIN(bright + ripple * 0.55f, 1.0f);

            // Font tier
            NSFont *cellFont = _font;
            if (ripple > 0.01f) {
                int tier = (int)(ripple * (RIPPLE_TIERS - 0.01f));
                cellFont = _rippleFonts[MIN(tier, RIPPLE_TIERS - 1)];
            }

            // Push — unnormalized (no sqrtf): dx/dy scaled by ripple²
            // Visually indistinguishable from normalized at typical speeds.
            float drawX = c * CELL_W;
            float drawY = height - (r + 1) * CELL_H;
            if (ripple > 0.01f) {
                float push = ripple * ripple * 0.35f;
                drawX += (_cellCX[c] - _mousePos.x) * push;
                drawY += (_cellCY[r] - _mousePos.y) * push;
            }

            // Color — table lookup, no alloc
            NSColor *color;
            if (ripple > 0.3f) {
                int gi = (int)((ripple - 0.3f) / 0.7f * (GLOW_LEVELS - 0.01f));
                color = sGlowColors[gi]; // full alpha, blended toward white
            } else {
                int tier;
                float hd = headY - r;
                if      (hd >= 0 && hd < 1.0f)      tier = 0;
                else if (effectiveBright > 0.75f)    tier = 1;
                else if (effectiveBright > 0.4f)     tier = 2;
                else                                  tier = 3;
                int ai = (int)(effectiveBright * (ALPHA_LEVELS - 0.01f));
                color  = sColorTable[tier][ai];
            }

            _drawAttrs[NSFontAttributeName]            = cellFont;
            _drawAttrs[NSForegroundColorAttributeName] = color;

            [_charStrings[_charIdx[c * _rows + r]]
                drawAtPoint:NSMakePoint(drawX, drawY)
             withAttributes:_drawAttrs];
        }
    }
}

@end

// ---------------------------------------------------------------------------
// Static overlay state
// ---------------------------------------------------------------------------
static NSMutableArray<NSWindow *> *sOverlayWindows = nil;
static BOOL                        sOverlayVisible  = NO;
static CFMachPortRef               sEventTap        = NULL;
static CFRunLoopSourceRef          sTapSource        = NULL;

// CGEventTap callback — blocks all keyboard events while overlay is active,
// except our exact unlock hotkey combo which Carbon already handled upstream.
static CGEventRef EventTapCallback(CGEventTapProxy proxy,
                                    CGEventType type,
                                    CGEventRef event,
                                    void *refcon) {
    // macOS disables passive taps on timeout — re-enable immediately
    if (type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput) {
        if (sEventTap) CGEventTapEnable(sEventTap, true);
        return event;
    }

    if (!sOverlayVisible) return event;

    // Pass mouse-moved through so [NSEvent mouseLocation] stays live.
    // The overlay window is on top and swallows these — no underlying app sees them.
    if (type == kCGEventMouseMoved) return event;

    // Always pass through our unlock hotkey so Carbon can fire the toggle.
    if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        CGKeyCode    keyCode = (CGKeyCode)CGEventGetIntegerValueField(
                                    event, kCGKeyboardEventKeycode);
        CGEventFlags flags   = CGEventGetFlags(event) &
                                    (kCGEventFlagMaskCommand  |
                                     kCGEventFlagMaskShift    |
                                     kCGEventFlagMaskAlternate|
                                     kCGEventFlagMaskControl);
        CGEventFlags wantFlags = kCGEventFlagMaskCommand | kCGEventFlagMaskShift;
        if (keyCode == HOTKEY_KEYCODE && flags == wantFlags) return event;
    }

    return NULL; // block everything else (Cmd+Tab, Cmd+Space, volume keys…)
}

// ---------------------------------------------------------------------------
// App delegate
// ---------------------------------------------------------------------------
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic) EventHotKeyRef   hotKeyRef;
@property (strong, nonatomic) NSStatusItem *statusItem;
- (void)toggleOverlay;
@end

static OSStatus HotkeyHandler(EventHandlerCallRef next, EventRef event, void *user) {
    AppDelegate *delegate = (__bridge AppDelegate *)user;
    dispatch_async(dispatch_get_main_queue(), ^{ [delegate toggleOverlay]; });
    return noErr;
}

@implementation AppDelegate

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];

    NSStatusBarButton *btn = self.statusItem.button;
    btn.image = [NSImage imageWithSystemSymbolName:@"lock.open.fill"
                          accessibilityDescription:@"Cypher"];
    btn.image.template = YES;
    btn.toolTip = @"Cypher — Cmd+Shift+L to lock";

    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Toggle Matrix Lock"
                    action:@selector(toggleOverlay)
             keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *loginItem = [[NSMenuItem alloc]
        initWithTitle:@"Launch at Login"
               action:@selector(toggleLaunchAtLogin:)
        keyEquivalent:@""];
    loginItem.target = self;
    BOOL runningFromBundle = [NSBundle.mainBundle.bundlePath hasSuffix:@".app"];
    if (@available(macOS 13.0, *)) {
        if (runningFromBundle) {
            loginItem.state = ([SMAppService.mainAppService status] == SMAppServiceStatusEnabled)
                ? NSControlStateValueOn : NSControlStateValueOff;
        } else {
            loginItem.enabled = NO;
            loginItem.toolTip = @"Run make install first";
        }
    } else {
        loginItem.hidden = YES;
    }
    [menu addItem:loginItem];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit"
                    action:@selector(terminate:)
             keyEquivalent:@"q"];
    self.statusItem.menu = menu;
}

- (void)toggleLaunchAtLogin:(NSMenuItem *)item API_AVAILABLE(macos(13.0)) {
    if (![NSBundle.mainBundle.bundlePath hasSuffix:@".app"]) return;
    NSError *error = nil;
    SMAppService *svc = SMAppService.mainAppService;

    if (svc.status == SMAppServiceStatusEnabled) {
        [svc unregisterAndReturnError:&error];
        item.state = NSControlStateValueOff;
    } else {
        // Unregister any stale registration (e.g. from a previous bundle path) before re-registering
        [svc unregisterAndReturnError:nil];
        [svc registerAndReturnError:&error];
        if (!error) {
            item.state = NSControlStateValueOn;
        } else {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText     = @"Launch at Login failed";
            alert.informativeText = [NSString stringWithFormat:
                @"Cypher must be installed to /Applications to enable Launch at Login.\n\n"
                @"Run: make install\n\nError: %@", error.localizedDescription];
            alert.alertStyle = NSAlertStyleWarning;
            [alert runModal];
        }
    }
}

- (void)updateStatusIcon {
    NSString *symbol = sOverlayVisible ? @"lock.fill" : @"lock.open.fill";
    self.statusItem.button.image =
        [NSImage imageWithSystemSymbolName:symbol
                     accessibilityDescription:@"Cypher"];
    self.statusItem.button.image.template = YES;
}

// Returns YES only when both required permissions are confirmed.
// Walks the user through each missing one with a blocking alert before continuing.
- (BOOL)checkAndRequestPermissions {
    // ── Accessibility (CGEventTap / block system shortcuts) ──────────────────
    if (!AXIsProcessTrusted()) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Accessibility permission required";
        alert.informativeText =
            @"Cypher needs Accessibility access to block system shortcuts "
            @"(Cmd+Tab, Mission Control, Spaces) while the screen is locked.\n\n"
            @"Click \"Open Settings\", enable Cypher, then relaunch the app.";
        alert.alertStyle = NSAlertStyleCritical;
        [alert addButtonWithTitle:@"Open Settings"];
        [alert addButtonWithTitle:@"Quit"];
        NSModalResponse r = [alert runModal];
        if (r == NSAlertFirstButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:
                [NSURL URLWithString:
                    @"x-apple.systempreferences:com.apple.preference.security"
                    @"?Privacy_Accessibility"]];
        }
        [NSApp terminate:nil];
        return NO;
    }

    // ── Input Monitoring (RegisterEventHotKey / unlock hotkey) ───────────────
    EventTypeSpec eventType = {kEventClassKeyboard, kEventHotKeyPressed};
    InstallApplicationEventHandler(HotkeyHandler, 1, &eventType,
                                   (__bridge void *)self, NULL);
    EventHotKeyID hkID = {.signature = 'MTRX', .id = 1};
    EventHotKeyRef ref  = NULL;
    OSStatus status = RegisterEventHotKey(HOTKEY_KEYCODE, HOTKEY_MODIFIERS, hkID,
                                          GetApplicationEventTarget(), 0, &ref);
    if (status != noErr) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Input Monitoring permission required";
        alert.informativeText =
            @"Cypher needs Input Monitoring access to register the unlock "
            @"hotkey (Cmd+Shift+L).\n\n"
            @"Without it the screen cannot be unlocked once locked.\n\n"
            @"Click \"Open Settings\", enable Cypher, then relaunch the app.";
        alert.alertStyle = NSAlertStyleCritical;
        [alert addButtonWithTitle:@"Open Settings"];
        [alert addButtonWithTitle:@"Quit"];
        NSModalResponse r = [alert runModal];
        if (r == NSAlertFirstButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:
                [NSURL URLWithString:
                    @"x-apple.systempreferences:com.apple.preference.security"
                    @"?Privacy_ListenEvent"]];
        }
        [NSApp terminate:nil];
        return NO;
    }

    self.hotKeyRef = ref;
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    sOverlayWindows = [[NSMutableArray alloc] init];

    if (![self checkAndRequestPermissions]) return;

    [self setupStatusItem];
    NSLog(@"[cypher] Running — Cmd+Shift+L to toggle Matrix lock.");
}

- (void)applicationWillTerminate:(NSNotification *)note {
    if (self.hotKeyRef) UnregisterEventHotKey(self.hotKeyRef);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return NO;
}

- (BOOL)installEventTap {
    CGEventMask mask = (CGEventMaskBit(kCGEventKeyDown)        |
                        CGEventMaskBit(kCGEventKeyUp)          |
                        CGEventMaskBit(kCGEventFlagsChanged)   |
                        CGEventMaskBit(kCGEventMouseMoved)     |
                        CGEventMaskBit(kCGEventLeftMouseDown)  |
                        CGEventMaskBit(kCGEventLeftMouseUp)    |
                        CGEventMaskBit(kCGEventRightMouseDown) |
                        CGEventMaskBit(kCGEventRightMouseUp)   |
                        CGEventMaskBit(kCGEventOtherMouseDown) |
                        CGEventMaskBit(kCGEventOtherMouseUp)   |
                        CGEventMaskBit(kCGEventScrollWheel));

    sEventTap = CGEventTapCreate(kCGSessionEventTap,
                                  kCGHeadInsertEventTap,
                                  kCGEventTapOptionDefault,
                                  mask,
                                  EventTapCallback,
                                  NULL);
    if (!sEventTap) return NO;

    sTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, sEventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), sTapSource, kCFRunLoopCommonModes);
    CGEventTapEnable(sEventTap, true);
    return YES;
}

- (void)removeEventTap {
    if (sTapSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), sTapSource, kCFRunLoopCommonModes);
        CFRelease(sTapSource);
        sTapSource = NULL;
    }
    if (sEventTap) {
        CFRelease(sEventTap);
        sEventTap = NULL;
    }
}

- (void)showOverlay {
    // Never lock if the unlock hotkey isn't registered — user would have no escape.
    if (!self.hotKeyRef) return;

    // Re-check Accessibility in case the user revoked it after launch.
    // Without it the event tap won't install and the overlay blocks nothing.
    if (!AXIsProcessTrusted()) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Accessibility permission was revoked";
        alert.informativeText =
            @"Cypher can no longer block system shortcuts. "
            @"Re-enable Accessibility in System Settings, then relaunch.";
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"Open Settings"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:
                [NSURL URLWithString:
                    @"x-apple.systempreferences:com.apple.preference.security"
                    @"?Privacy_Accessibility"]];
        }
        return;
    }

    NSMutableArray<NSWindow *> *newWindows = [[NSMutableArray alloc] init];

    for (NSScreen *screen in [NSScreen screens]) {
        NSWindow *win = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0,
                                           screen.frame.size.width,
                                           screen.frame.size.height)
                      styleMask:NSWindowStyleMaskBorderless
                        backing:NSBackingStoreBuffered
                          defer:YES];

        [win setFrame:screen.frame display:NO];
        [win setLevel:NSPopUpMenuWindowLevel];
        [win setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
        [win setOpaque:YES];
        [win setIgnoresMouseEvents:NO];
        [win setHidesOnDeactivate:NO];
        [win setMovable:NO];
        [win setBackgroundColor:[NSColor blackColor]];

        MatrixView *view = [[MatrixView alloc]
            initWithFrame:NSMakeRect(0, 0,
                                     screen.frame.size.width,
                                     screen.frame.size.height)];
        [win setContentView:view];
        [win orderFrontRegardless];

        [newWindows addObject:win];
    }

    [sOverlayWindows removeAllObjects];
    [sOverlayWindows addObjectsFromArray:newWindows];
    sOverlayVisible = YES;
    [self updateStatusIcon];

    if (![self installEventTap]) {
        // Tap failed — tear down the overlay rather than show a fake lock.
        [self hideOverlay];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Failed to install input blocker";
        alert.informativeText =
            @"Cypher could not block system input. The screen was not locked. "
            @"Try relaunching the app.";
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
        return;
    }

    [NSApp activateIgnoringOtherApps:YES];
}

- (void)hideOverlay {
    [self removeEventTap];
    for (NSWindow *win in sOverlayWindows) [win orderOut:nil];
    [sOverlayWindows removeAllObjects];
    sOverlayVisible = NO;
    [self updateStatusIcon];
}

- (void)toggleOverlay {
    sOverlayVisible ? [self hideOverlay] : [self showOverlay];
}

@end

// ---------------------------------------------------------------------------
void RunApp(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
}
