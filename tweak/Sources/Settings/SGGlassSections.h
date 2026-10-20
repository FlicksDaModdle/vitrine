// Settings on glass, for the redesign: each section of a list stands on a pane of Liquid Glass in place of a
// #1C1C1E card, its rows clear over it. The redesign switches it on at launch (Redesigned/Settings/SettingsGlass.x)
// and the mod's own pages and Spotify's settings lists then draw this way; the native look keeps its cards.
#import <UIKit/UIKit.h>

extern BOOL SGPagesUseGlass;

// What a row of a mod page is painted with: clear over glass, the card color otherwise.
UIColor *SGCellBackground(void);
// The panes behind `list`'s sections, one a rect (in the list's content), a pane past the rects hidden.
void SGGlassSections(UIScrollView *list, NSArray<NSValue *> *rects, CGFloat radius);
// A table's sections as the rects their rows take, inset as its cells are.
NSArray<NSValue *> *SGTableSectionRects(UITableView *table);
// The radius of a section's pane.
extern const CGFloat SGGlassSectionRadius;
