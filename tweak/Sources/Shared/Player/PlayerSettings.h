// Settings of the player that hold for either look.
#import <UIKit/UIKit.h>

UIViewController *SGLockScreenWidgetPage(void);

// Switch to video hidden from the player under either look (VideoSwitch.x), off until switched on.
#define SGKeyHideVideoSwitch @"spotifyglass.hide.videoSwitch"
// True shuffle (TrueShuffle.m): turning shuffle on for a playlist plays it in a plain random order instead of
// Spotify's weighted one. On until switched off.
#define SGKeyTrueShuffle @"spotifyglass.trueShuffle"
