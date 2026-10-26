// Player redesign: Spotify's lyric preview under the cover (the line being sung).
//
// A tap on it brings the lyrics into the player, as the footer's lyrics glyph does (PlayerLyrics.x): the cover
// goes to a thumbnail and the lines take its room, with every control of the player still there. The tap is a recognizer on a
// clear view over the preview, which the recognizers of the views around it (the cover's tilt view takes taps
// and holds, PlayerArtwork.x) are made to wait on: a control there lost its touches to them, and the cover
// opened instead. With the switch off the view is not there; a tap before the track's lines are in does nothing.
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
#import "Shared/Player/PlayerSettings.h"
#import "Player.h"

static char kTapKey, kOriginalKey, kShownKey, kLineKey, kHiddenKey, kShiftKey;
static Class sg_previewClass;
static NSHashTable<UILabel *> *sg_labels;
static BOOL sg_setting;   // a text of ours going in, which the hooks pass through
// Whether Spotify's preview labels are romanized at all: Romanized lyrics on and the mod's own line off (it draws
// its own). Every label in the app goes through the hooks, so this is what they read first; it follows the switch.
static BOOL sg_labelsWanted;
static void readLabelsWanted(void) {
    sg_labelsWanted = SGFlag(SGKeyLyricsRomanised, NO) && !SGEnabled(SGRKeyLyricsPreviewOwn);
}

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
    SGLog(@"redesign player: the lyric preview was tapped (lines %d, open %d)", SGRPlayerLyricsAvailable(), SGRPlayerLyricsOpen());
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
    return SGFlag(SGKeyLyricsRomanisedReplace, NO);
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
    if (!sg_labelsWanted || sg_setting || !text.length || SGRPreviewLineIsOurs((UIView *)self) || !inPreview((UIView *)self)) {
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
    if (!sg_labelsWanted || sg_setting || !text.length || SGRPreviewLineIsOurs((UIView *)self) || !inPreview((UIView *)self)) {
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

#pragma mark - the room under the line

// Spotify keeps a 100 pt band under the cover for its preview and the Switch to video chip's room over the title, and
// the mod's line uses the top of it: one sung line left a blank of about 100 pt over the title. With the chip hidden
// the cover and the line move down by most of that blank (onto the space over the cover, which was all but none
// while playing), the line sits a little lower in what is left, and about kUnder stays between the line and the title.
static const CGFloat kUnder = 30, kMostShift = 56;

static BOOL holdsTilt(UIView *view, int depth) {
    static Class tiltClass;
    if (!tiltClass) tiltClass = NSClassFromString(@"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView");
    if ([view isKindOfClass:tiltClass]) return YES;
    if (depth <= 0) return NO;
    for (UIView *sub in view.subviews) if (holdsTilt(sub, depth - 1)) return YES;
    return NO;
}

// The view holding both the cover and the preview, which moves them together; a cell's content view, since a list
// sets its cells' transforms.
static UIView *coverGroupOf(UIView *preview) {
    int up = 0;
    for (UIView *v = preview.superview; v && up < 6; v = v.superview, up++) {
        if ([v isKindOfClass:UIScrollView.class]) return nil;
        if (!holdsTilt(v, 3)) continue;
        return [v isKindOfClass:UICollectionViewCell.class] ? ((UICollectionViewCell *)v).contentView : v;
    }
    return nil;
}

CGFloat SGRPreviewShiftAbove(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        NSNumber *shift = objc_getAssociatedObject(v, &kShiftKey);
        if (shift) return shift.doubleValue;
    }
    return 0;
}

static void setShift(UIView *group, CGFloat shift) {
    if (!group) return;
    objc_setAssociatedObject(group, &kShiftKey, shift ? @(shift) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGAffineTransform move = CGAffineTransformMakeTranslation(0, shift);
    if (!CGAffineTransformEqualToTransform(group.transform, move)) group.transform = move;
}

static const CGFloat kSeenMargin = 16;

// The lowest point in the preview's coordinates that the views clipping it let show, as it stands now.
static CGFloat visibleBottom(UIView *view, UIView *group) {
    CGFloat bottom = CGFLOAT_MAX;
    for (UIView *v = view.superview; v && v.window; v = v.superview) {
        if (!v.clipsToBounds && !v.layer.mask) continue;
        bottom = MIN(bottom, CGRectGetMaxY([view convertRect:v.bounds fromView:v]));
        if ([v isKindOfClass:UIWindow.class]) break;
    }
    return bottom == CGFLOAT_MAX ? view.bounds.size.height + 200 : bottom;
}

// The line's frame in the preview, and how much lower than its rest the sung line sits in it.
static CGRect placeRoom(UIView *view, CGFloat *lift) {
    CGRect bounds = view.bounds;
    *lift = 0;
    UIView *group = coverGroupOf(view);
    CGFloat shift = group ? group.transform.ty : 0;
    CGRect row = SGHidden(SGKeyHideVideoSwitch) ? SGRPlayerTitleRowFrameIn(view) : CGRectNull;
    // Where the title row would be in the preview with no move on the cover.
    CGFloat rowTop = CGRectIsNull(row) ? 0 : CGRectGetMinY(row) + shift;
    if (CGRectIsNull(row) || rowTop <= CGRectGetMaxY(bounds) || rowTop > CGRectGetMaxY(bounds) + 220) {
        if (!SGRPlayerLyricsOpen()) setShift(group, 0);
        bounds.size.height += SGRPreviewLineReach();
        return bounds;
    }
    // What the views around the preview let show, unmoved: the line, carried down with the cover, stops short of it,
    // or it is cut in half there.
    CGFloat seen = visibleBottom(view, group) + shift;
    CGFloat rest = SGRPreviewLineRest();
    CGFloat room = MAX(0, seen - rest - kSeenMargin);
    CGFloat surplus = rowTop - rest - kUnder;
    CGFloat newShift = surplus > 0 ? round(MIN(MIN(surplus * 0.6, kMostShift), room)) : 0;
    // While the lines are up the cover stays where it is: the thumbnail is measured from it.
    if (SGRPlayerLyricsOpen()) newShift = shift;
    else setShift(group, newShift);
    *lift = surplus > newShift ? round(MIN((surplus - newShift) * 0.4, MAX(0, room - newShift))) : 0;
    CGFloat bottom = MIN(rowTop, seen) - newShift - 4;
    bounds.size.height = MAX(bounds.size.height, bottom - CGRectGetMinY(bounds));
    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign player: the title row %.0f pt under the preview's top, the cover moved down %.0f (%@), the line %.0f lower, %.0f pt tall",
              rowTop, newShift, group ? NSStringFromClass(group.class) : @"no group", *lift, bounds.size.height);
        SGLog(@"redesign player: the preview's surroundings show it down to %.0f pt", seen);
    }
    return bounds;
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
    // Not waiting on the lines: Spotify lays the preview out before they are in, and may not again. The line shows
    // nothing until they come, and the tap asks for them when it lands.
    BOOL own = SGEnabled(SGRKeyLyricsPreviewOwn);
    if (own && !line) {
        line = SGRPreviewLineMake();
        objc_setAssociatedObject(view, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (own) {
        // Into the room under the preview, which Spotify leaves empty above the chip row; the preview lets it show.
        // With Switch to video hidden, its room over the title is empty too, so the line runs down to the title row and
        // the lines to come fill what was a blank band (the sung line sits lower in a taller band, PlayerLyricsPreviewLine.m).
        CGFloat lift = 0;
        CGRect bounds = placeRoom(view, &lift);
        SGRPreviewLineSetLift(line, lift);
        if (!CGRectEqualToRect(line.frame, bounds)) line.frame = bounds;
        if (line.superview != view) [view addSubview:line];
        // Unclipped up to the cell the cover is in, not past it: a scroll view clipping is the player's own.
        int up = 0;
        for (UIView *v = view; v && up < 5 && ![v isKindOfClass:UIScrollView.class]; v = v.superview, up++) {
            if (v.clipsToBounds) v.clipsToBounds = NO;
            if ([v isKindOfClass:UICollectionViewCell.class] || [v isKindOfClass:UITableViewCell.class]) break;
        }

    } else {
        [line removeFromSuperview];
        setShift(coverGroupOf(view), 0);
    }
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

    // A label filled before it was inside the preview: its line is taken now. Not with the mod's own line up.
    if (sg_labelsWanted) SGForEachView(view, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || SGRPreviewLineIsOurs(v)) return;
        UILabel *label = (UILabel *)v;
        if (objc_getAssociatedObject(label, &kOriginalKey) || !label.text.length) return;
        if (label.attributedText.length) label.attributedText = label.attributedText;
        else label.text = label.text;
    });

    SGRPreviewTap *tap = objc_getAssociatedObject(view, &kTapKey);
    BOOL wanted = SGEnabled(SGRKeyLyricsPreviewOpensScreen);
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
    readLabelsWanted();
    sg_previewClass = classes.firstObject;
    SGLog(@"redesign player: lyric preview classes %@", classes);
    if (!classes.count) return;
    for (Class cls in classes) hookLayout(cls);
    %init;
    [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsRomanisedDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            readLabelsWanted();
            refreshLabels();
        });
    }];
}
