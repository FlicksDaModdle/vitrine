// Settings redesign: Spotify's settings lists and the mod's own pages on Liquid Glass. Each section of a list stands
// on one pane of glass (Settings/SGGlassSections.h) in place of Spotify's flat #121212 rows or the mod's #1C1C1E cards,
// its rows clear over it, on the redesign's black.
//
// Spotify's settings (App/ModSettings.x's tree, trees/settings.txt): SettingsListViewController's view holds a
// SettingsListCollectionView of Element_List cells as wide as the screen, and a page pushed from it a UITableView of
// 53 pt cells. Both are found from the controller, and any table under a controller of Spotify's named for Settings,
// and each is laid out again from its own pass (Kit/SGRRestyle.h), which scrolling runs too. A collection's cells
// are as wide as the list, so its panes stand SGRGrid in from the sides. Mod Settings' own row at the end of the list
// (App/ModSettings.x) is a view of the list's, not a cell, and the last pane reaches down over it.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGGlassSections.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRRestyle.h"

static char kStyledKey;
static const CGFloat kSideInset = 8;

static void clearCell(UIView *cell) {
    if (cell.backgroundColor != UIColor.clearColor) cell.backgroundColor = UIColor.clearColor;
    if ([cell isKindOfClass:UICollectionViewCell.class]) {
        UICollectionViewCell *c = (UICollectionViewCell *)cell;
        if (!objc_getAssociatedObject(c, &kStyledKey)) {
            objc_setAssociatedObject(c, &kStyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            c.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
        }
        if (c.contentView.backgroundColor && CGColorGetAlpha(c.contentView.backgroundColor.CGColor) > 0.9) c.contentView.backgroundColor = UIColor.clearColor;
    } else if ([cell isKindOfClass:UITableViewCell.class]) {
        UITableViewCell *c = (UITableViewCell *)cell;
        if (!objc_getAssociatedObject(c, &kStyledKey)) {
            objc_setAssociatedObject(c, &kStyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            c.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
        }
        if (c.contentView.backgroundColor && CGColorGetAlpha(c.contentView.backgroundColor.CGColor) > 0.9) c.contentView.backgroundColor = UIColor.clearColor;
    }
}

static NSArray<NSValue *> *collectionRects(UICollectionView *list) {
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    CGFloat width = list.bounds.size.width;
    for (NSInteger section = 0; section < list.numberOfSections; section++) {
        CGRect rect = CGRectNull;
        NSInteger items = [list numberOfItemsInSection:section];
        for (NSInteger item = 0; item < items; item++) {
            UICollectionViewLayoutAttributes *a = [list.collectionViewLayout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:section]];
            if (a && !a.hidden && a.frame.size.height > 1) rect = CGRectUnion(rect, a.frame);
        }
        if (CGRectIsNull(rect)) rect = CGRectZero;
        else if (rect.size.width >= width - 1) rect = CGRectInset(rect, kSideInset, 0);
        [rects addObject:[NSValue valueWithCGRect:rect]];
    }
    // A row of the mod's under the last section, laid in the list as one of its own.
    NSUInteger last = NSNotFound;
    for (NSUInteger i = rects.count; i > 0; i--) if (!CGRectIsEmpty(rects[i - 1].CGRectValue)) { last = i - 1; break; }
    if (last != NSNotFound) {
        CGRect end = rects[last].CGRectValue;
        for (UIView *sub in list.subviews) {
            if ([sub isKindOfClass:UICollectionReusableView.class] || [sub isKindOfClass:UIVisualEffectView.class] || sub.hidden || sub.alpha < 0.01) continue;
            CGRect f = sub.frame;
            if (f.size.width < width - 1 || f.size.height < 36 || f.size.height > 90) continue;
            if (CGRectGetMinY(f) < CGRectGetMaxY(end) - 1 || CGRectGetMinY(f) > CGRectGetMaxY(end) + 40) continue;
            end.size.height = CGRectGetMaxY(f) - CGRectGetMinY(end);
        }
        rects[last] = [NSValue valueWithCGRect:end];
    }
    return rects;
}

static void restyle(UIScrollView *list) {
    if (!list.window) return;
    if (list.backgroundColor != UIColor.blackColor) list.backgroundColor = UIColor.blackColor;
    if ([list isKindOfClass:UICollectionView.class]) {
        UICollectionView *collection = (UICollectionView *)list;
        for (UICollectionViewCell *cell in collection.visibleCells) clearCell(cell);
        SGGlassSections(list, collectionRects(collection), SGGlassSectionRadius);
    } else if ([list isKindOfClass:UITableView.class]) {
        UITableView *table = (UITableView *)list;
        for (UITableViewCell *cell in table.visibleCells) clearCell(cell);
        SGGlassSections(list, SGTableSectionRects(table), SGGlassSectionRadius);
    }
}

static void watch(UIScrollView *list) {
    if (objc_getAssociatedObject(list, &kStyledKey)) {
        restyle(list);
        return;
    }
    objc_setAssociatedObject(list, &kStyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL watched = SGRObserveLayout(list, ^(UIView *view) { restyle((UIScrollView *)view); });
    SGLog(@"redesign settings: %@ on glass%@", NSStringFromClass(list.class), watched ? @"" : @" (not watched for its layout)");
    restyle(list);
}

static void watchListsIn(UIView *root) {
    SGForEachView(root, ^(UIView *v) {
        if ([v isKindOfClass:UICollectionView.class] || [v isKindOfClass:UITableView.class]) watch((UIScrollView *)v);
    });
}

%hook _TtC21Settings_PlatformImpl26SettingsListViewController
- (void)viewDidLayoutSubviews {
    %orig;
    watchListsIn(((UIViewController *)self).view);
}
%end

// A settings page of Spotify's that is not the list's controller: a table under a controller named for Settings.
static BOOL underSpotifySettings(UIView *view) {
    for (UIResponder *r = view.nextResponder; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        NSString *name = NSStringFromClass(r.class);
        return [name hasPrefix:@"_TtC"] && [name containsString:@"Settings"];
    }
    return NO;
}

%hook UITableView
- (void)didMoveToWindow {
    %orig;
    UITableView *table = (UITableView *)self;
    if (table.window && !objc_getAssociatedObject(table, &kStyledKey) && underSpotifySettings(table)) watch(table);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    SGPagesUseGlass = YES;
    %init;
}
