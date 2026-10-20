// Player redesign: the line under the cover drawn by the redesign's own lyrics view (SGRKaraokeView), the one the
// full-screen lyrics use, in place of Spotify's preview: the same type, the same smooth sweep and the same lift of
// the letters being sung, Romanized lyrics as that view has them, and the Lyrics page's look.
//
// The view keeps the sung line at a share of its height from the top (kAnchor there, 0.28), so here it is made
// taller than the band by that share and lifted by it: the sung line stands at the top of the band, the lines
// before it are cut off above, the next one is cut off below. It takes no touches (PlayerLyricsPreviewTap.x's tap
// is over it) and its pronunciation and translation button is hidden. PlayerLyricsPreviewTap.x puts it over
// Spotify's preview, whose own views it leaves in place with no alpha.
#import "Core/SGCore.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Player.h"

// The share of its height the karaoke view rests the sung line at (SGRKaraokeView.m's kAnchor).
static const CGFloat kKaraokeAnchor = 0.28;

@interface SGRPreviewLineView : UIView
@end

@implementation SGRPreviewLineView {
    SGRKaraokeView *_lyrics;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;
    self.isAccessibilityElement = NO;
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // Made once the band is in a window, so the view starts on the song playing now.
    if (self.window && !_lyrics) {
        _lyrics = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
        _lyrics.extrasHidden = YES;
        _lyrics.keepsSing = NO;
        _lyrics.userInteractionEnabled = NO;
        [self addSubview:_lyrics];
        [self setNeedsLayout];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize band = self.bounds.size;
    if (band.height <= 0) return;
    CGFloat height = ceil(band.height / (1 - kKaraokeAnchor));
    CGRect frame = CGRectMake(0, -round(height * kKaraokeAnchor), band.width, height);
    if (!CGRectEqualToRect(_lyrics.frame, frame)) _lyrics.frame = frame;
}

@end

UIView *SGRPreviewLineMake(void) {
    return [SGRPreviewLineView new];
}

BOOL SGRPreviewLineIsOurs(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:SGRPreviewLineView.class]) return YES;
    }
    return NO;
}
