// Player redesign: Spotify's lyric preview under the cover (the line being sung).
//
// A tap on it brings the lyrics into the player, as the footer's lyrics glyph does (PlayerLyrics.x): the cover
// goes to a thumbnail and the lines take its room, with every control of the player still there. The tap is a recognizer on a
// clear view over the preview, which the recognizers of the views around it (the cover's tilt view takes taps
// and holds, PlayerArtwork.x) are made to wait on: a control there lost its touches to them, and the cover
// opened instead. With the switch off, a track without lines, or the lines already up, the view is not there.
//
// Its text follows Romanized lyrics (Shared/Lyrics): in place of the line with Show romanized on Instead of
// the original, under it otherwise, as the lyrics view has them. The text is set into labels inside the
// preview; each one keeps the line Spotify gave it, so a change of the setting sets it again.
//
// Tree (trees/clean/player/01.txt:36-43, PlayerArtwork.x): Lyrics_NPVContainerKit.LyricsContainerView under
// the cover's tilt view.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Player.h"

static char kTapKey, kOriginalKey, kShownKey, kLineKey, kHiddenKey;
static Class sg_previewClass;
static NSHashTable<UILabel *> *sg_labels;
static BOOL sg_setting;   // a text of ours going in, which the hooks pass through

#pragma mark - the tap

@interface SGRPreviewTap : UIView <UIGestureRecognizerDelegate>
@end

@implementation SGRPreviewTap

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Show lyrics";
    self.accessibilityTraits = UIAccessibilityTraitButton;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    tap.delegate = self;
    [self addGestureRecognizer:tap];
    return self;
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateEnded) return;
    SGLog(@"redesign player: the lyric preview was tapped");
    if (SGRPlayerLyricsAvailable() && !SGRPlayerLyricsOpen()) SGRPlayerToggleLyrics();
}

// Every recognizer on a view around this one waits until this tap has failed, so a tap here is this one's.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)mine shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    return other.view && other.view != self && [self isDescendantOfView:other.view];
}

- (BOOL)accessibilityActivate {
    if (SGRPlayerLyricsAvailable() && !SGRPlayerLyricsOpen()) SGRPlayerToggleLyrics();
    return YES;
}

@end

#pragma mark - the text

static BOOL isPreviewClass(UIView *view);
static BOOL inPreview(UIView *view) {
    if (!sg_previewClass) return NO;
    UIView *v = view.superview;
    for (int up = 0; v && up < 10; up++, v = v.superview) {
        if (isPreviewClass(v)) return YES;
    }
    return NO;
}

// Off, or a line with nothing to romanize: nil, and the line shows as it is.
static NSString *romanisedLine(NSString *line) {
    if (!line.length || !SGFlag(SGKeyLyricsRomanised, NO)) return nil;
    return SGLyricsRomanised(line, NO);
}

static BOOL instead(void) {
    return SGInt(SGKeyLyricsRomanisedMode, 0) == 1;
}

static NSAttributedString *shownAttributed(NSAttributedString *line, NSString *latin) {
    NSDictionary *attributes = line.length ? [line attributesAtIndex:0 effectiveRange:NULL] : @{};
    if (instead()) return [[NSAttributedString alloc] initWithString:latin attributes:attributes];
    NSMutableAttributedString *both = [line mutableCopy];
    NSMutableDictionary *under = [attributes mutableCopy];
    UIFont *font = attributes[NSFontAttributeName];
    if (font) under[NSFontAttributeName] = [font fontWithSize:round(font.pointSize * 0.78)];
    UIColor *color = attributes[NSForegroundColorAttributeName];
    under[NSForegroundColorAttributeName] = [color ?: UIColor.whiteColor colorWithAlphaComponent:0.65];
    [both appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n" stringByAppendingString:latin] attributes:under]];
    return both;
}

static void keep(UILabel *label, id original) {
    objc_setAssociatedObject(label, &kOriginalKey, original, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!sg_labels) sg_labels = [NSHashTable weakObjectsHashTable];
    [sg_labels addObject:label];
}

%hook UILabel
- (void)setText:(NSString *)text {
    if (sg_setting || !text.length || SGRPreviewLineIsOurs((UIView *)self) || !inPreview((UIView *)self)) {
        %orig;
        return;
    }
    keep(self, text);
    NSString *latin = romanisedLine(text);
    if (!latin) {
        %orig;
        return;
    }
    sg_setting = YES;
    if (instead()) [self setText:latin];
    else {
        self.numberOfLines = 0;
        [self setAttributedText:shownAttributed([[NSAttributedString alloc] initWithString:text attributes:@{
            NSFontAttributeName: self.font ?: [UIFont systemFontOfSize:17], NSForegroundColorAttributeName: self.textColor ?: UIColor.whiteColor}], latin)];
    }
    sg_setting = NO;
    objc_setAssociatedObject(self, &kShownKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setAttributedText:(NSAttributedString *)text {
    if (sg_setting || !text.length || SGRPreviewLineIsOurs((UIView *)self) || !inPreview((UIView *)self)) {
        %orig;
        return;
    }
    keep(self, text);
    NSString *latin = romanisedLine(text.string);
    if (!latin) {
        %orig;
        return;
    }
    if (!instead()) self.numberOfLines = 0;
    sg_setting = YES;
    [self setAttributedText:shownAttributed(text, latin)];
    sg_setting = NO;
    objc_setAssociatedObject(self, &kShownKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

// The setting changed: every preview label gets the line Spotify gave it again, through the hooks above.
static void refreshLabels(void) {
    for (UILabel *label in sg_labels.allObjects) {
        id original = objc_getAssociatedObject(label, &kOriginalKey);
        if ([original isKindOfClass:NSAttributedString.class]) label.attributedText = original;
        else if ([original isKindOfClass:NSString.class]) label.text = original;
    }
}

#pragma mark - the preview

// Spotify has had more than one view for the preview: LyricsContainerView (9.1.78's tree), and the elements kit's
// containers newer versions build it from. Every one this app has is hooked, and the outermost one in the player
// (a short band as wide as the cover, not a lyrics page or card) gets the tap.
static NSArray<Class> *sg_previewClasses;
static const CGFloat kPreviewMinWidth = 200, kPreviewMaxHeight = 220;

static BOOL isPreviewClass(UIView *view) {
    for (Class cls in sg_previewClasses) {
        if ([view isKindOfClass:cls]) return YES;
    }
    return NO;
}

static BOOL insidePreviewClass(UIView *view) {
    UIView *v = view.superview;
    for (int up = 0; v && up < 8; up++, v = v.superview) {
        if (isPreviewClass(v)) return YES;
    }
    return NO;
}

static void previewLaidOut(UIView *view) {
    CGSize size = view.bounds.size;
    if (!view.window || size.width < kPreviewMinWidth || size.height > kPreviewMaxHeight || size.height < 10) return;
    if (insidePreviewClass(view)) return;   // the outer one takes it
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *name = NSStringFromClass(view.class);
    if (![logged containsObject:name]) {
        [logged addObject:name];
        NSMutableArray<NSString *> *kinds = [NSMutableArray array];
        SGForEachView(view, ^(UIView *v) { if (v != view) [kinds addObject:NSStringFromClass(v.class)]; });
        SGLog(@"redesign player: the lyric preview is %@ %@, holding %@", name, NSStringFromCGSize(size), [kinds componentsJoinedByString:@", "]);
    }
    // The mod's own line in place of Spotify's: Spotify's views stay, with no alpha, and come back with the switch off.
    UIView *line = objc_getAssociatedObject(view, &kLineKey);
    BOOL own = SGEnabled(SGRKeyLyricsPreviewOwn) && SGRPlayerLyricsAvailable();
    if (own && !line) {
        line = SGRPreviewLineMake();
        objc_setAssociatedObject(view, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (own) {
        line.frame = view.bounds;
        if (line.superview != view) [view addSubview:line];
    } else [line removeFromSuperview];
    for (UIView *sub in view.subviews) {
        if (sub == line || [sub isKindOfClass:SGRPreviewTap.class]) continue;
        if (own && sub.alpha != 0) {
            objc_setAssociatedObject(sub, &kHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            sub.alpha = 0;
        } else if (!own && objc_getAssociatedObject(sub, &kHiddenKey)) {
            objc_setAssociatedObject(sub, &kHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            sub.alpha = 1;
        }
    }

    // A label filled before it was inside the preview: its line is taken now.
    SGForEachView(view, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || SGRPreviewLineIsOurs(v)) return;
        UILabel *label = (UILabel *)v;
        if (objc_getAssociatedObject(label, &kOriginalKey) || !label.text.length) return;
        if (label.attributedText.length) label.attributedText = label.attributedText;
        else label.text = label.text;
    });

    SGRPreviewTap *tap = objc_getAssociatedObject(view, &kTapKey);
    BOOL wanted = SGEnabled(SGRKeyLyricsPreviewOpensScreen) && SGRPlayerLyricsAvailable() && !SGRPlayerLyricsOpen();
    if (!wanted) {
        [tap removeFromSuperview];
        return;
    }
    if (!tap) {
        tap = [SGRPreviewTap new];
        objc_setAssociatedObject(view, &kTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign player: %@ opens the lyrics in the player", name);
    }
    tap.frame = view.bounds;
    if (tap.superview != view) [view addSubview:tap];
    else if (view.subviews.lastObject != tap) [view bringSubviewToFront:tap];
}

// -layoutSubviews of a class, followed by previewLaidOut: its own where it has one, added over its superclass's
// where it has not, so no other class is touched.
static void hookLayout(Class cls) {
    SEL sel = @selector(layoutSubviews);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return;
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(UIView *view) {
        ((void (*)(id, SEL))original)(view, sel);
        previewLaidOut(view);
    });
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) method_setImplementation(method, replacement);
}

%ctor {
    if (!SGRedesignedUI()) return;
    NSMutableArray<Class> *classes = [NSMutableArray array];
    for (NSString *name in @[@"_TtC22Lyrics_NPVContainerKit19LyricsContainerView",
                             @"_TtC25Lyrics_NPVElementsKitImpl26LyricsElementContainerView",
                             @"_TtC25Lyrics_NPVElementsKitImpl24LyricsElementWrapperView",
                             @"_TtC28NowPlaying_ContentLayersImpl25LegacyLyricsContainerView"]) {
        Class cls = NSClassFromString(name);
        if (cls) [classes addObject:cls];
    }
    sg_previewClasses = classes;
    sg_previewClass = classes.firstObject;
    SGLog(@"redesign player: lyric preview classes %@", classes);
    if (!classes.count) return;
    for (Class cls in classes) hookLayout(cls);
    %init;
    [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsRomanisedDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ refreshLabels(); });
    }];
}
