// Player redesign: Karaoke from the ⋯ (PlayerMenu.m), in a popover as Lyrics Size… and Speed, Pitch & Reverb are: the
// switch, and one slider for how the song is mixed, the vocals turned down at its left (gone at its end), as sung in
// its middle, and the music turned down at its right (the vocals alone at its end), as the Sing page's level is
// (Shared/Sing/Sing.h, SGKeySingLevel). What Karaoke is doing is under the switch, live, and the Sing page is a tap away
// for the model's download and the rest.
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Sing/Sing.h"
#import "Player.h"

static const CGFloat kWidth = 320, kPad = 16;

@interface SGRKaraokePanel : UIViewController <UIPopoverPresentationControllerDelegate>
@end

@implementation SGRKaraokePanel {
    UILabel *_title, *_status, *_level, *_left, *_right;
    UISwitch *_toggle;
    UISlider *_slider;
    UIButton *_asSung, *_more;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    _title = [UILabel new];
    _title.text = @"Karaoke";
    _title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _title.textColor = UIColor.labelColor;
    _status = [UILabel new];
    _status.font = [UIFont systemFontOfSize:13];
    _status.textColor = UIColor.secondaryLabelColor;
    _status.numberOfLines = 2;
    _toggle = [UISwitch new];
    [_toggle addTarget:self action:@selector(flipped) forControlEvents:UIControlEventValueChanged];
    _level = [UILabel new];
    _level.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
    _level.textColor = UIColor.labelColor;
    _level.textAlignment = NSTextAlignmentCenter;
    _slider = [UISlider new];
    _slider.minimumValue = 0;
    _slider.maximumValue = 2;
    _slider.minimumValueImage = [UIImage systemImageNamed:@"music.note"];
    _slider.maximumValueImage = [UIImage systemImageNamed:@"music.mic"];
    _slider.accessibilityLabel = @"Mix";
    [_slider addTarget:self action:@selector(moved) forControlEvents:UIControlEventValueChanged];
    _left = [UILabel new];
    _left.text = @"Less vocals";
    _right = [UILabel new];
    _right.text = @"Less music";
    _right.textAlignment = NSTextAlignmentRight;
    for (UILabel *label in @[_left, _right]) {
        label.font = [UIFont systemFontOfSize:12];
        label.textColor = UIColor.secondaryLabelColor;
    }
    _asSung = [UIButton buttonWithType:UIButtonTypeSystem];
    [_asSung setTitle:@"As Sung" forState:UIControlStateNormal];
    [_asSung addTarget:self action:@selector(reset) forControlEvents:UIControlEventTouchUpInside];
    _more = [UIButton buttonWithType:UIButtonTypeSystem];
    [_more setTitle:@"Karaoke Settings…" forState:UIControlStateNormal];
    [_more addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *view in @[_title, _status, _toggle, _level, _slider, _left, _right, _asSung, _more]) [self.view addSubview:view];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(show) name:SGSingChangedNotification object:nil];
    [self show];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)show {
    NSString *missing = SGSingMissing();
    _toggle.on = SGSingOn();
    _toggle.enabled = !missing;
    NSString *detail = SGSingStatusDetail();
    _status.text = missing ?: (detail.length ? [NSString stringWithFormat:@"%@ · %@", SGSingStatusText(), detail] : SGSingStatusText());
    float level = SGSingLevel();
    if (!_slider.tracking) _slider.value = level;
    _level.text = SGSingLevelText(level);
    BOOL usable = !missing && SGSingCurrentState() != SGSingStateNoModel;
    _slider.enabled = usable;
    _asSung.enabled = usable && fabsf(level - 1) > 0.001f;
}

- (void)flipped {
    SGSetSingOn(_toggle.on);
    [self show];
}

- (void)moved {
    float value = _slider.value;
    // Held at As sung a little either side of the middle, so it can be found again by feel.
    if (fabsf(value - 1) < 0.04f) value = 1;
    SGSetSingLevel(value);
    if (value > 0.001f && !SGSingOn() && !SGSingMissing()) SGSetSingOn(YES);
    [self show];
}

- (void)reset {
    SGSetSingLevel(1);
    _slider.value = 1;
    [self show];
}

- (void)openSettings {
    UIViewController *presenter = self.presentingViewController;
    [self dismissViewControllerAnimated:YES completion:^{
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:SGSingSettingsPage()];
        SGPresentDark(nav);
        [(presenter ?: SGTopController()) presentViewController:nav animated:YES completion:nil];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width - 2 * kPad, y = kPad;
    CGSize toggle = [_toggle sizeThatFits:CGSizeZero];
    _title.frame = CGRectMake(kPad, y, width - toggle.width - 8, 22);
    _toggle.frame = CGRectMake(kPad + width - toggle.width, y - 4, toggle.width, toggle.height);
    y += 24;
    _status.frame = CGRectMake(kPad, y, width, 34);
    y += 42;
    _level.frame = CGRectMake(kPad, y, width, 20);
    y += 24;
    _slider.frame = CGRectMake(kPad, y, width, 34);
    y += 36;
    _left.frame = CGRectMake(kPad, y, width / 2, 16);
    _right.frame = CGRectMake(kPad + width / 2, y, width / 2, 16);
    y += 26;
    _asSung.frame = CGRectMake(kPad, y, width / 2 - 4, 32);
    _more.frame = CGRectMake(kPad + width / 2 + 4, y, width / 2 - 4, 32);
}

// A popover on iPhone too, not a sheet.
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
                                                               traitCollection:(UITraitCollection *)traits {
    return UIModalPresentationNone;
}

@end

NSString *SGRKaraokeMenuSubtitle(void) {
    if (SGSingMissing()) return nil;
    return SGSingOn() ? SGSingLevelText(SGSingLevel()) : @"Off";
}

void SGRShowKaraokePanel(UIView *from) {
    if (!from.window) return;
    SGRKaraokePanel *panel = [SGRKaraokePanel new];
    panel.modalPresentationStyle = UIModalPresentationPopover;
    panel.preferredContentSize = CGSizeMake(kWidth, 236);
    UIPopoverPresentationController *popover = panel.popoverPresentationController;
    popover.sourceView = from;
    popover.sourceRect = from.bounds;
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown;
    popover.delegate = panel;
    SGPresentDark(panel);
    // Picked from a system menu that is still going away: the panel waits for it, as Lyrics Size…'s does.
    __block int tries = 0;
    __block void (^present)(void);
    present = ^{
        UIViewController *top = SGTopController();
        if ((top.isBeingDismissed || top.isBeingPresented || top.transitionCoordinator) && ++tries < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), present);
            return;
        }
        present = nil;
        [top presentViewController:panel animated:YES completion:nil];
    };
    dispatch_async(dispatch_get_main_queue(), present);
}
