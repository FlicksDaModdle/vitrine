// Player redesign: a tap on Spotify's lyric preview under the cover (the line being sung) opens the lyrics on
// a screen of their own (PlayerLyricsScreen.m). A clear control over the preview takes the tap, so Spotify's own
// handling of it never runs; with the switch off, or a track without lines, the control is not there.
//
// Tree (trees/clean/player/01.txt:36-43, PlayerArtwork.x): Lyrics_NPVContainerKit.LyricsContainerView under
// the cover's tilt view.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Player.h"

static char kTapKey;

@interface SGRPreviewTap : UIControl
@end

@implementation SGRPreviewTap
- (void)opened {
    if (SGRPlayerLyricsAvailable()) SGRPlayerShowLyricsScreen();
}
@end

%hook _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    SGRPreviewTap *tap = objc_getAssociatedObject(view, &kTapKey);
    BOOL wanted = SGEnabled(SGRKeyLyricsPreviewOpensScreen) && SGRPlayerLyricsAvailable();
    if (!wanted) {
        [tap removeFromSuperview];
        return;
    }
    if (!tap) {
        tap = [SGRPreviewTap new];
        tap.accessibilityLabel = @"Full-screen lyrics";
        tap.isAccessibilityElement = YES;
        tap.accessibilityTraits = UIAccessibilityTraitButton;
        [tap addTarget:tap action:@selector(opened) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(view, &kTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    tap.frame = view.bounds;
    if (tap.superview != view) [view addSubview:tap];
    else [view bringSubviewToFront:tap];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!NSClassFromString(@"_TtC22Lyrics_NPVContainerKit19LyricsContainerView")) {
        SGLog(@"redesign player: no lyric preview view in this Spotify; its tap is left alone");
        return;
    }
    %init;
}
