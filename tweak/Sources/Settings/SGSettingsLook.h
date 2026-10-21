// The mod's pages the way iOS draws Settings, for the redesign: the system font at Settings' sizes (17 pt titles,
// 13 pt subtitles, headers and notes) on the inset grouped cards they already stand on. The redesign switches it on
// at launch (Redesigned/Settings/SettingsLook.x); the native look keeps the mod's own 13 pt Spotify type.
#import <UIKit/UIKit.h>

extern BOOL SGPagesNativeLook;

// A row's card color on a mod page.
UIColor *SGCellBackground(void);
// Cards behind `list`'s sections, one a rect (in the list's content), a card past the rects hidden.
void SGCardSections(UIScrollView *list, NSArray<NSValue *> *rects, CGFloat radius);
// A table's sections as the rects their rows take, inset as its cells are.
NSArray<NSValue *> *SGTableSectionRects(UITableView *table);
// Settings' own card corner on iOS 26.
extern const CGFloat SGCardRadius;
