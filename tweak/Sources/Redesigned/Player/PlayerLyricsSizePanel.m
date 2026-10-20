// Player redesign: the lyrics' size set by hand, a slider a place (LyricsLook.h's SGRLyricsPlace): under the cover,
// in the player and full screen. A popover, so it takes the system's glass and closes at a tap outside it, the way
// Speed, Pitch & Reverb's does (Shared/Player/SpeedPitchMenu.x). Each slider sets the size as it moves, a point at a
// time, and Default gives the place back the Lyrics page's size.
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Settings/SGPageStyle.h"
#import "Player.h"

static const CGFloat kMin = 12, kMax = 48, kRowHeight = 84, kPad = 16, kWidth = 320;

// What a place shows at Default: the look's size, capped under the cover as the band caps it (PlayerLyricsPreviewLine.m).
static CGFloat defaultSize(SGRLyricsPlace place) {
    CGFloat size = SGRLyricsLookNow().size;
    return place == SGRLyricsPlacePreview ? MIN(size, 26) : size;
}

static NSString *placeName(SGRLyricsPlace place) {
    switch (place) {
        case SGRLyricsPlacePreview: return @"Under the Cover";
        case SGRLyricsPlacePlayer: return @"In the Player";
        default: return @"Full Screen";
    }
}

@interface SGRLyricsSizeRow : UIView
@property (nonatomic) SGRLyricsPlace place;
@end

@implementation SGRLyricsSizeRow {
    UILabel *_name, *_value;
    UISlider *_slider;
    UIButton *_reset;
}

- (instancetype)initWithPlace:(SGRLyricsPlace)place {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _place = place;
    _name = [UILabel new];
    _name.text = placeName(place);
    _name.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _name.textColor = UIColor.labelColor;
    _value = [UILabel new];
    _value.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
    _value.textColor = UIColor.secondaryLabelColor;
    _value.textAlignment = NSTextAlignmentRight;
    _slider = [UISlider new];
    _slider.minimumValue = kMin;
    _slider.maximumValue = kMax;
    _slider.minimumValueImage = [UIImage systemImageNamed:@"textformat.size.smaller"];
    _slider.maximumValueImage = [UIImage systemImageNamed:@"textformat.size.larger"];
    _slider.accessibilityLabel = [placeName(place) stringByAppendingString:@" lyrics size"];
    [_slider addTarget:self action:@selector(moved) forControlEvents:UIControlEventValueChanged];
    _reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [_reset setTitle:@"Default" forState:UIControlStateNormal];
    _reset.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [_reset addTarget:self action:@selector(reset) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *view in @[_name, _value, _slider, _reset]) [self addSubview:view];
    [self show];
    return self;
}

- (void)show {
    CGFloat chosen = SGRLyricsSizeFor(_place);
    CGFloat size = chosen > 0 ? chosen : defaultSize(_place);
    _slider.value = size;
    _value.text = chosen > 0 ? [NSString stringWithFormat:@"%.0f pt", size] : [NSString stringWithFormat:@"Default · %.0f pt", size];
    _reset.enabled = chosen > 0;
}

- (void)moved {
    CGFloat size = round(_slider.value);
    if (fabs(size - SGRLyricsSizeFor(_place)) < 0.5) return;   // a point at a time: every set lays the song out again
    SGRSetLyricsSize(_place, size);
    [self show];
}

- (void)reset {
    SGRSetLyricsSize(_place, 0);
    [self show];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _name.frame = CGRectMake(0, 8, width * 0.5, 20);
    _reset.frame = CGRectMake(width - 64, 2, 64, 32);
    _value.frame = CGRectMake(width * 0.5, 8, width * 0.5 - 70, 20);
    _slider.frame = CGRectMake(0, 38, width, 36);
}

@end

@interface SGRLyricsSizePanel : UIViewController <UIPopoverPresentationControllerDelegate>
@property (nonatomic, copy) NSArray<NSNumber *> *places;
@end

@implementation SGRLyricsSizePanel

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    CGFloat y = kPad;
    for (NSNumber *place in self.places) {
        SGRLyricsSizeRow *row = [[SGRLyricsSizeRow alloc] initWithPlace:place.integerValue];
        row.frame = CGRectMake(kPad, y, kWidth - 2 * kPad, kRowHeight);
        row.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self.view addSubview:row];
        y += kRowHeight;
    }
}

// A popover on iPhone too, not a sheet.
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
                                                               traitCollection:(UITraitCollection *)traits {
    return UIModalPresentationNone;
}

@end

void SGRShowLyricsSizePanel(UIView *from, NSInteger onlyPlace) {
    if (!from.window) return;
    SGRLyricsSizePanel *panel = [SGRLyricsSizePanel new];
    panel.places = onlyPlace ? @[@(onlyPlace)] : @[@(SGRLyricsPlacePreview), @(SGRLyricsPlacePlayer), @(SGRLyricsPlaceFullScreen)];
    panel.modalPresentationStyle = UIModalPresentationPopover;
    panel.preferredContentSize = CGSizeMake(kWidth, 2 * kPad + kRowHeight * panel.places.count);
    UIPopoverPresentationController *popover = panel.popoverPresentationController;
    popover.sourceView = from;
    popover.sourceRect = from.bounds;
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown;
    popover.delegate = panel;
    SGPresentDark(panel);
    // Picked from a system menu that is still going away: the panel waits for it, as Speed and Pitch's does.
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
