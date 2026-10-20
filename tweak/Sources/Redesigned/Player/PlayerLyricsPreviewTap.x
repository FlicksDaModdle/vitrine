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

static char kTapKey, kOriginalKey, kShownKey;
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

static BOOL inPreview(UIView *view) {
    if (!sg_previewClass) return NO;
    UIView *v = view.superview;
    for (int up = 0; v && up < 10; up++, v = v.superview) {
        if ([v isKindOfClass:sg_previewClass]) return YES;
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
    if (sg_setting || !text.length || !inPreview((UIView *)self)) { %orig; return; }
    keep(self, text);
    NSString *latin = romanisedLine(text);
    if (!latin) { %orig; return; }
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
    if (sg_setting || !text.length || !inPreview((UIView *)self)) { %orig; return; }
    keep(self, text);
    NSString *latin = romanisedLine(text.string);
    if (!latin) { %orig; return; }
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

%hook _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *kinds = [NSMutableArray array];
        SGForEachView(view, ^(UIView *v) { if (v != view) [kinds addObject:NSStringFromClass(v.class)]; });
        SGLog(@"redesign player: the lyric preview holds %@", [kinds componentsJoinedByString:@", "]);
    });
    // A label filled before it was inside the preview: its line is taken now.
    SGForEachView(view, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || [v isKindOfClass:SGRPreviewTap.class]) return;
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
        SGLog(@"redesign player: the lyric preview opens the lyrics in the player");
    }
    tap.frame = view.bounds;
    if (tap.superview != view) [view addSubview:tap];
    else if (view.subviews.lastObject != tap) [view bringSubviewToFront:tap];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_previewClass = NSClassFromString(@"_TtC22Lyrics_NPVContainerKit19LyricsContainerView");
    if (!sg_previewClass) {
        SGLog(@"redesign player: no lyric preview view in this Spotify; its tap and text are left alone");
        return;
    }
    %init;
    [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsRomanisedDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ refreshLabels(); });
    }];
}
