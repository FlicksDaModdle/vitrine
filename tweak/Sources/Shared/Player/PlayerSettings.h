// Settings of the player that hold for either look.
#import <UIKit/UIKit.h>

UIViewController *SGLockScreenWidgetPage(void);

// Switch to video hidden from the player under either look (VideoSwitch.x), off until switched on.
#define SGKeyHideVideoSwitch @"spotifyglass.hide.videoSwitch"
// True shuffle (TrueShuffle.m): turning shuffle on for a playlist plays it in a plain random order instead of
// Spotify's weighted one. On until switched off.
#define SGKeyTrueShuffle @"spotifyglass.trueShuffle"

// SongBlock.m: songs blocked from the player's ⋯ menu, skipped wherever they come up.
NSDictionary<NSString *, NSArray<NSString *> *> *SGBlockedSongs(void);
BOOL SGSongBlocked(NSString *uri);
void SGSetSongBlocked(NSString *uri, NSString *title, NSString *artist, BOOL blocked);
// The song playing blocked (and skipped) or unblocked.
void SGBlockPlayingSong(BOOL blocked);
UIViewController *SGSongBlockSettingsPage(void);

// SaveQueue.m: the song playing and the queue after it saved as a new private playlist, with an alert saying how it went.
void SGSaveQueueAsPlaylist(void);
