// How the redesign's lyrics are set, from the Lyrics page: the size of the words, the room between two
// lines, how strongly the lines away from the one sung blur, and how strongly a held word glows and its
// letters wave. A preset sets all five, the sheet of sliders each one; they apply at once to every lyrics
// view there is, the Lyrics page's own preview among them (LyricsLookSettings.m).
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

// size and spacing in points; blur, glow and wave as shares of Apple Music's, 1 being theirs and 0 none.
typedef struct {
    CGFloat size, spacing, blur, glow, wave;
} SGRLyricsLook;

// The five as one dictionary; unset is the first preset, Apple Music's.
#define SGRKeyLyricsLook @"spotifyglass.redesign.lyricsLook"

// Posted on the main queue when the look changes; the object is whoever changed it, nil for none named.
extern NSNotificationName const SGRLyricsLookDidChangeNotification;

SGRLyricsLook SGRLyricsLookNow(void);
void SGRSetLyricsLook(SGRLyricsLook look, id changer);

// The words' size in each place the lyrics show, over the look's own: the line under the player's cover, the lines
// in the player, and the full-screen lyrics (and the landscape screen with them). 0 is the place's default: the
// look's size, capped at 26 under the cover. Applies at once, posting the notification below.
typedef NS_ENUM(NSInteger, SGRLyricsPlace) {
    SGRLyricsPlaceNone = 0,
    SGRLyricsPlacePreview,
    SGRLyricsPlacePlayer,
    SGRLyricsPlaceFullScreen,
};
extern NSNotificationName const SGRLyricsSizeDidChangeNotification;
CGFloat SGRLyricsSizeFor(SGRLyricsPlace place);
void SGRSetLyricsSize(SGRLyricsPlace place, CGFloat size);
// A menu of the sizes for one place, a checkmark at the one it has; and one of the three places' menus.
UIMenu *SGRLyricsSizeMenu(SGRLyricsPlace place, NSString *title);
UIMenu *SGRLyricsSizesMenu(void);
// Redesigned/Player/PlayerLyricsSizePanel.m: the sizes by slider in a glass popover from `from`, one place's or (0) all.
void SGRShowLyricsSizePanel(UIView *from, NSInteger onlyPlace);

// The presets, by name, Apple Music's first.
NSArray<NSString *> *SGRLyricsLookPresetNames(void);
SGRLyricsLook SGRLyricsLookPreset(NSUInteger index);
// The preset the look is, or -1 for a look of the sliders' own.
NSInteger SGRLyricsLookPresetIndex(SGRLyricsLook look);

// A few lines of the preview's own, words timed, one held long enough to glow and wave, and how long
// they take to come round again.
NSArray<SGKaraokeLine *> *SGRLyricsSampleLines(void);
NSInteger SGRLyricsSampleLength(void);

// LyricsLookSettings.m: the Lyrics page in the redesign, leading with the preview, the presets under it
// and their sliders in a sheet, then `sections`.
@class SGModSection;
UIViewController *SGRLyricsSettingsPage(NSString *title, NSString *intro, NSArray<SGModSection *> *sections);
