// Player redesign: the line under the cover drawn by the redesign's own lyrics view (SGRKaraokeView), the one the
// full-screen lyrics use, in place of Spotify's preview: the same type, the same smooth sweep and the same lift of
// the letters being sung, Romanized lyrics as that view has them, and the Lyrics page's look.
//
// The view keeps the sung line at a share of its height from the top (kAnchor there, 0.28), so here it is made
// taller than the band by that share and lifted by it: the sung line stands near the top of the band, a little room
// above it, the lines before it cut off above and the next one under it. It takes no touches (PlayerLyricsPreviewTap.x's tap
// is over it) and its pronunciation and translation button is hidden. PlayerLyricsPreviewTap.x puts it over
// Spotify's preview, whose own views it leaves in place with no alpha.
#import "Core/SGCore.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Player.h"

// The share of its height the karaoke view rests the sung line at (SGRKaraokeView.m's kAnchor).
static const CGFloat kKaraokeAnchor = 0.28;
// Between the cover and the sung line.
static const CGFloat kTopRoom = 16;
// The words at most this size here, so a line that wraps still fits the band twice over.
static const CGFloat kMaxFont = 26;
// How far the band reaches past the bottom of Spotify's preview, into the room above the chip row, fading out.
static const CGFloat kReach = 36, kFade = 28;

@interface SGRPreviewLineView : UIView
@property (nonatomic, weak) UIView *band;   // the preview it draws for, when it stands outside it
@end

static NSHashTable<UIView *> *sg_lines;

@implementation SGRPreviewLineView {
    SGRKaraokeView *_lyrics;
@public
    CGFloat _lift;
}

// Out of the window while the player's own lines are up, so its display link and its layout stop with it.
- (void)rest:(BOOL)resting {
    if (!_lyrics) return;
    if (resting && _lyrics.superview) [_lyrics removeFromSuperview];
    else if (!resting && !_lyrics.superview) {
        [self addSubview:_lyrics];
        [self setNeedsLayout];
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    // Clipped by a mask rather than the bounds: solid from the top, fading over its last kFade points.
    CAGradientLayer *mask = [CAGradientLayer layer];
    mask.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    self.layer.mask = mask;
    self.isAccessibilityElement = NO;
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // Made once the band is in a window, so the view starts on the song playing now.
    if (self.window && !_lyrics) {
        _lyrics = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
        _lyrics.maxFontSize = kMaxFont;
        _lyrics.sizePlace = SGRLyricsPlacePreview;
        _lyrics.extrasHidden = YES;
        // Its extras button stays laid out, only its glass hidden, and the lines faded out above it: a line set lower
        // in a taller band was cut in half there.
        _lyrics.noBottomRow = YES;
        _lyrics.keepsSing = NO;
        _lyrics.userInteractionEnabled = NO;
        if (!sg_lines) sg_lines = [NSHashTable weakObjectsHashTable];
        [sg_lines addObject:self];
        [self addSubview:_lyrics];
        [self setNeedsLayout];
    }
    [self rest:SGRPlayerLyricsOpen()];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize band = self.bounds.size;
    if (band.height <= 0) return;
    // The sung line a little below the cover rather than against it, and the band under it for the line to come.
    CGFloat top = MIN(kTopRoom, band.height * 0.2) + _lift;
    CGFloat height = ceil((band.height - top) / (1 - kKaraokeAnchor));
    CGRect frame = CGRectMake(0, top - round(height * kKaraokeAnchor), band.width, height);
    if (!CGRectEqualToRect(_lyrics.frame, frame)) _lyrics.frame = frame;
    CAGradientLayer *mask = (CAGradientLayer *)self.layer.mask;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = self.bounds;
    CGFloat fade = MIN(kFade, band.height * 0.3);
    mask.locations = @[@0, @(MAX(0, (band.height - fade) / band.height)), @1];
    [CATransaction commit];
}

@end

void SGRPreviewLineLyricsChanged(void) {
    BOOL open = SGRPlayerLyricsOpen();
    for (SGRPreviewLineView *line in sg_lines.allObjects) [line rest:open];
}

void SGRPreviewLineSetLift(UIView *line, CGFloat lift) {
    if (![line isKindOfClass:SGRPreviewLineView.class]) return;
    SGRPreviewLineView *view = (SGRPreviewLineView *)line;
    if (fabs(view->_lift - lift) < 0.5) return;
    view->_lift = lift;
    [view setNeedsLayout];
}

// The sung line's bottom at rest from the preview's top: the room over it and the words, with the romanized line
// under them when Romanized lyrics show both.
CGFloat SGRPreviewLineRest(void) {
    CGFloat chosen = SGRLyricsSizeFor(SGRLyricsPlacePreview);
    CGFloat size = chosen > 0 ? chosen : MIN(SGRLyricsLookNow().size, kMaxFont);
    BOOL both = SGFlag(SGKeyLyricsRomanised, NO) && !SGFlag(SGKeyLyricsRomanisedReplace, NO);
    return kTopRoom + ceil(size * 1.3 * (both ? 1.8 : 1));
}

void SGRPreviewLineSetBand(UIView *line, UIView *band) {
    if ([line isKindOfClass:SGRPreviewLineView.class]) ((SGRPreviewLineView *)line).band = band;
}

UIView *SGRPreviewLineBand(UIView *line) {
    return [line isKindOfClass:SGRPreviewLineView.class] ? ((SGRPreviewLineView *)line).band : nil;
}

CGFloat SGRPreviewLineReach(void) {
    return kReach;
}

UIView *SGRPreviewLineMake(void) {
    return [SGRPreviewLineView new];
}

BOOL SGRPreviewLineIsOurs(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:SGRPreviewLineView.class]) return YES;
    }
    return NO;
}
