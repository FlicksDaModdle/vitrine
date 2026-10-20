// Player redesign: the lyrics on a screen of their own, upright. The lines fill it over the player's Fluid
// artwork, with the track and a back button at the top and a slim progress bar with previous, play and next
// at the bottom. The back button (or VoiceOver's escape) returns to the player as it was. The buttons at the top sit
// on glass circles as the player's header ones do, and the bar and its controls on one glass capsule (Kit/SGRGlass.h).
//
// Opened from the player's ⋯ menu (Full-Screen Lyrics, PlayerMenu.m) or by holding the footer's lyrics
// glyph (PlayerFooter.x), whenever the playing track has lines. It is the landscape screen's portrait
// sibling (PlayerLandscape.x) and shares its parts: the karaoke view, the artwork field and the player.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Player.h"

static const CGFloat kSide = 20, kControlSide = 44, kBarGap = 8, kTimeHeight = 16;

static __weak UIViewController *sg_screen;
static char kBackGlassKey, kShareGlassKey, kDockGlassKey;
static const CGFloat kDockPad = 12, kDockSide = 12;

@interface SGRLyricsScreenController : UIViewController <SGPlayerStateObserver>
@end

static UIButton *glyphButton(NSString *symbol, CGFloat size, NSString *label, SEL action, id target) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = label;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static NSString *timeText(double seconds) {
    if (!isfinite(seconds) || seconds < 0) seconds = 0;
    NSInteger whole = (NSInteger)floor(seconds);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(whole / 60), (long)(whole % 60)];
}

@implementation SGRLyricsScreenController {
    SGRArtworkField *_field;
    UIButton *_back, *_share, *_play, *_previous, *_next;
    SGMarqueeLabel *_title, *_artist;
    UIView *_stage;   // the lines' own view: the karaoke view dims every sibling it has
    SGRKaraokeView *_lyrics;
    UIView *_dock;   // the glass under the bar and the controls; they are its siblings, above it
    UISlider *_progress;
    UILabel *_elapsed, *_remaining;
    NSTimer *_clock;
    BOOL _scrubbing;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    _field = [[SGRArtworkField alloc] initWithFrame:self.view.bounds];
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _field.showsBackdrop = YES;
    _field.fluid = YES;
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    if (art) [_field setArtwork:art identity:identity animated:NO];
    [self.view addSubview:_field];

    _back = glyphButton(@"chevron.down", 20, @"Back to the player", @selector(close), self);
    [self.view addSubview:_back];
    // A lyric card of the lines (Shared/Lyrics/LyricCard.m).
    _share = glyphButton(@"square.and.arrow.up", 18, @"Share lyrics", @selector(shareLyrics), self);
    [self.view addSubview:_share];
    _title = [SGMarqueeLabel new];
    _title.textColor = UIColor.whiteColor;
    _title.font = SGRFont(UIFontTextStyleHeadline, UIFontWeightBold, UIContentSizeCategoryExtraExtraLarge);
    _artist = [SGMarqueeLabel new];
    _artist.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    _artist.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraExtraLarge);
    [self.view addSubview:_title];
    [self.view addSubview:_artist];

    _stage = [UIView new];
    [self.view addSubview:_stage];
    _lyrics = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _lyrics.keepsSing = YES;
    [_stage addSubview:_lyrics];

    _dock = [UIView new];
    _dock.userInteractionEnabled = NO;
    [self.view addSubview:_dock];

    _progress = [UISlider new];
    _progress.minimumTrackTintColor = UIColor.whiteColor;
    _progress.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.25];
    // A small thumb: the bar is meant to be slim.
    UIImage *thumb = [UIImage systemImageNamed:@"circle.fill" withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightBold]];
    [_progress setThumbImage:[thumb imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
    _progress.accessibilityLabel = @"Track position";
    [_progress addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
    [_progress addTarget:self action:@selector(scrubMoved) forControlEvents:UIControlEventValueChanged];
    [_progress addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.view addSubview:_progress];
    _elapsed = [UILabel new];
    _remaining = [UILabel new];
    for (UILabel *label in @[_elapsed, _remaining]) {
        label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
        label.textColor = [UIColor colorWithWhite:1 alpha:0.6];
        [self.view addSubview:label];
    }
    _remaining.textAlignment = NSTextAlignmentRight;

    _previous = glyphButton(@"backward.fill", 22, @"Previous track", @selector(previousTrack), self);
    _play = glyphButton(@"pause.fill", 28, @"Pause", @selector(togglePlay), self);
    _next = glyphButton(@"forward.fill", 22, @"Next track", @selector(nextTrack), self);
    for (UIButton *button in @[_previous, _play, _next]) [self.view addSubview:button];

    SGAddPlayerStateObserver(self);
    [self playerStateDidChange:SGPlayerState()];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(artworkChanged)
                                               name:SGRNowPlayingArtworkDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_clock invalidate];
    __weak SGRLyricsScreenController *weakSelf = self;
    _clock = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    [self tick];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_clock invalidate];
    _clock = nil;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_clock invalidate];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat width = safe.size.width, left = CGRectGetMinX(safe);
    CGFloat top = CGRectGetMinY(safe) + 4;

    // The top row: back at the leading edge, the track beside it.
    _back.frame = CGRectMake(left + 6, top, kControlSide, kControlSide);
    _share.frame = CGRectMake(CGRectGetMaxX(safe) - 6 - kControlSide, top, kControlSide, kControlSide);
    CGFloat textLeft = CGRectGetMaxX(_back.frame) + 4, textWidth = CGRectGetMinX(_share.frame) - 4 - textLeft;
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    CGFloat textTop = top + (kControlSide - titleHeight - artistHeight) / 2;
    _title.frame = CGRectMake(textLeft, textTop, textWidth, titleHeight);
    _artist.frame = CGRectMake(textLeft, CGRectGetMaxY(_title.frame), textWidth, artistHeight);
    CGFloat headerBottom = top + MAX(kControlSide, titleHeight + artistHeight) + kBarGap;

    // The bottom: the controls on the safe edge, the bar and its times over them.
    CGFloat bottom = CGRectGetMaxY(safe) - 10;
    CGFloat controlsTop = bottom - kControlSide;
    CGFloat mid = CGRectGetMidX(safe);
    _play.frame = CGRectMake(mid - kControlSide / 2, controlsTop, kControlSide, kControlSide);
    _previous.frame = CGRectMake(mid - kControlSide * 2.2, controlsTop, kControlSide, kControlSide);
    _next.frame = CGRectMake(mid + kControlSide * 1.2, controlsTop, kControlSide, kControlSide);
    CGFloat timesTop = controlsTop - kTimeHeight;
    CGFloat inset = kSide + kDockSide;
    _elapsed.frame = CGRectMake(left + inset, timesTop, 60, kTimeHeight);
    _remaining.frame = CGRectMake(CGRectGetMaxX(safe) - inset - 60, timesTop, 60, kTimeHeight);
    _progress.frame = CGRectMake(left + inset, timesTop - 28, width - 2 * inset, 28);

    // The glass: circles behind the two buttons at the top, a capsule around the bar and the controls.
    SGRGlassInside(_back, &kBackGlassKey, kControlSide);
    SGRGlassInside(_share, &kShareGlassKey, kControlSide);
    CGFloat dockTop = CGRectGetMinY(_progress.frame) - kDockPad;
    _dock.frame = CGRectMake(left + kDockSide, dockTop, width - 2 * kDockSide, CGRectGetMaxY(_play.frame) + kDockPad / 2 - dockTop);
    SGRGlassCapsuleInside(_dock, &kDockGlassKey, _dock.bounds.size, NO);

    CGFloat linesBottom = CGRectGetMinY(_dock.frame) - kBarGap;
    _stage.frame = CGRectMake(CGRectGetMinX(self.view.bounds), headerBottom, self.view.bounds.size.width, linesBottom - headerBottom);
    _lyrics.frame = _stage.bounds;
}

#pragma mark - what it shows

- (void)artworkChanged {
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    if (art) [_field setArtwork:art identity:identity animated:YES];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!state) return;
    _title.text = state.track.trackTitle;
    _artist.text = state.track.artistName;
    [_play setImage:[UIImage systemImageNamed:state.isPaused ? @"play.fill" : @"pause.fill" withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    _play.accessibilityLabel = state.isPaused ? @"Play" : @"Pause";
    _share.hidden = !SGLyricCardAvailable();
    _field.motionHeld = state.isPaused;
    [self tick];
}

// The position from the player's last report, run on by the time since it.
- (void)tick {
    SPTPlayerState *state = SGPlayerState();
    double duration = state.duration;
    if (!state || duration <= 0) return;
    double position = state.positionAsOfTimestamp;
    if (!state.isPaused && state.timestamp) position += -state.timestamp.timeIntervalSinceNow * (state.playbackSpeed > 0 ? state.playbackSpeed : 1);
    position = MIN(MAX(position, 0), duration);
    if (!_scrubbing) {
        _progress.maximumValue = duration;
        _progress.value = position;
    }
    double shown = _scrubbing ? _progress.value : position;
    _elapsed.text = timeText(shown);
    _remaining.text = [@"-" stringByAppendingString:timeText(duration - shown)];
}

#pragma mark - what it does

- (id<SPTPlayer>)player {
    id player = SGKaraokePlayer();
    return [player respondsToSelector:@selector(pause:)] ? player : nil;
}

- (void)togglePlay {
    id<SPTPlayer> player = self.player;
    if (SGPlayerState().isPaused) [player resume:nil];
    else [player pause:nil];
}

- (void)previousTrack {
    [self.player skipToPreviousTrackWithOptions:nil];
}

- (void)nextTrack {
    [self.player skipToNextTrackWithOptions:nil];
}

- (void)scrubBegan {
    _scrubbing = YES;
}

- (void)scrubMoved {
    [self tick];
}

- (void)scrubEnded {
    if (!_scrubbing) return;
    _scrubbing = NO;
    SGKaraokeSeek((NSInteger)(_progress.value * 1000));
}

- (void)shareLyrics {
    SGLyricCardPresent(self);
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)accessibilityPerformEscape {
    [self close];
    return YES;
}

@end

void SGRPlayerShowLyricsScreen(void) {
    if (sg_screen) return;
    UIViewController *top = SGTopController();
    if (!top) return;
    SGRLyricsScreenController *screen = [SGRLyricsScreenController new];
    screen.modalPresentationStyle = UIModalPresentationOverFullScreen;
    screen.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    SGPresentDark(screen);
    sg_screen = screen;
    [top presentViewController:screen animated:YES completion:nil];
    SGLog(@"redesign player: full-screen lyrics");
}
