// Settings redesign: Spotify's settings lists and the mod's own pages drawn the way iOS draws Settings
// (Settings/SGSettingsLook.h). The mod's pages already stand on inset grouped cards and take the system font at
// Settings' sizes. Spotify's lists, flat #121212 rows as wide as the screen, are inset by 16 pt a side and each
// section put on one #1C1C1E card with Settings' corner, its rows clear over it, their titles in the system font at
// the mod's pages' type, their icons on gray tiles, a hairline between rows, on black.
//
// Spotify's settings (App/ModSettings.x's tree, trees/settings.txt): SettingsListViewController's view holds a
// SettingsListCollectionView of Element_List cells as wide as the screen, and a page pushed from it a UITableView of
// 53 pt cells. Both are found from the controller, and any table under a controller of Spotify's named for Settings,
// and each is laid out again from its own pass (Kit/SGRRestyle.h), which scrolling runs too. Mod Settings' own row
// at the end of the list (App/ModSettings.x) is a view of the list's, not a cell: it is narrowed to the card, and the
// last card reaches down over it.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGSettingsLook.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRRestyle.h"

static char kStyledKey, kRuleKey, kTileKey;
static const CGFloat kSideInset = 16;

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

// The row's labels as Settings sets its own: the top one, the title, at 17 pt white, the rest at 15 pt gray.
static void setType(UIView *cell) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(cell, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && !v.hidden && ((UILabel *)v).text.length) [labels addObject:(UILabel *)v];
    });
    if (!labels.count) return;
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ya = [a convertPoint:CGPointZero toView:cell].y, yb = [b convertPoint:CGPointZero toView:cell].y;
        return ya < yb ? NSOrderedAscending : ya > yb ? NSOrderedDescending : NSOrderedSame;
    }];
    // The mod's own pages' type (Settings/SGPageStyle.h), so the two read as one.
    UIFont *title = SGTitleFont(), *detail = SGSubtitleFont();
    for (UILabel *label in labels) {
        BOOL first = label == labels.firstObject;
        UIFont *font = first ? title : detail;
        if (![label.font isEqual:font]) label.font = font;
        if (first && ![label.textColor isEqual:UIColor.whiteColor]) label.textColor = UIColor.whiteColor;
        if (!first && ![label.textColor isEqual:SGGrey()]) label.textColor = SGGrey();
    }
}

// The row's leading icon on a gray rounded square, white, as the mod's rows lead with their tiles.
static void setTile(UIView *cell) {
    __block UIImageView *icon = nil;
    SGForEachView(cell, ^(UIView *v) {
        if (icon || ![v isKindOfClass:UIImageView.class] || v.hidden) return;
        CGRect f = [v convertRect:v.bounds toView:cell];
        if (f.size.width >= 14 && f.size.width <= 32 && CGRectGetMinX(f) < 60) icon = (UIImageView *)v;
    });
    UIView *tile = objc_getAssociatedObject(cell, &kTileKey);
    if (!icon) {
        tile.hidden = YES;
        return;
    }
    if (!tile) {
        tile = [UIView new];
        tile.userInteractionEnabled = NO;
        tile.backgroundColor = [UIColor colorWithRed:0x8E / 255.0 green:0x8E / 255.0 blue:0x93 / 255.0 alpha:1];
        tile.layer.cornerRadius = 7;
        tile.layer.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(cell, &kTileKey, tile, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    tile.hidden = NO;
    if (tile.superview != icon.superview) [icon.superview insertSubview:tile belowSubview:icon];
    else if ([icon.superview.subviews indexOfObject:tile] > [icon.superview.subviews indexOfObject:icon]) [icon.superview insertSubview:tile belowSubview:icon];
    CGPoint center = icon.center;
    CGRect frame = CGRectMake(round(center.x - 14.5), round(center.y - 14.5), 29, 29);
    if (!CGRectEqualToRect(tile.frame, frame)) tile.frame = frame;
    if (![icon.tintColor isEqual:UIColor.whiteColor]) icon.tintColor = UIColor.whiteColor;
    if (icon.image.renderingMode != UIImageRenderingModeAlwaysTemplate) icon.image = [icon.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// A cell narrowed to the card, after the list's pass placed it as wide as the list.
static void narrow(UIView *cell, CGFloat width) {
    CGRect frame = cell.frame;
    if (frame.size.width < width - 1) return;
    cell.frame = CGRectMake(kSideInset, frame.origin.y, width - 2 * kSideInset, frame.size.height);
}

// A hairline across the foot of every row but a section's last, from under the title as Settings has it.
static void setRule(UIView *cell, BOOL shown) {
    UIView *rule = objc_getAssociatedObject(cell, &kRuleKey);
    if (!rule) {
        rule = [UIView new];
        rule.userInteractionEnabled = NO;
        rule.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        objc_setAssociatedObject(cell, &kRuleKey, rule, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    rule.hidden = !shown;
    if (!shown) return;
    __block CGFloat left = 16;
    __block BOOL found = NO;
    SGForEachView(cell, ^(UIView *v) {
        if (found || ![v isKindOfClass:UILabel.class] || v.hidden) return;
        found = YES;
        left = [v convertPoint:CGPointZero toView:cell].x;
    });
    CGFloat height = 1 / UIScreen.mainScreen.scale;
    CGRect frame = CGRectMake(left, cell.bounds.size.height - height, MAX(0, cell.bounds.size.width - left), height);
    if (!CGRectEqualToRect(rule.frame, frame)) rule.frame = frame;
    if (rule.superview != cell) [cell addSubview:rule];
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
            if (f.size.width < width - 2 * kSideInset - 1 || f.size.height < 36 || f.size.height > 90 || sub.layer.zPosition < 0) continue;
            if (CGRectGetMinY(f) < CGRectGetMaxY(end) - 1 || CGRectGetMinY(f) > CGRectGetMaxY(end) + 40) continue;
            // On the card, not out past its side.
            CGRect narrowed = CGRectMake(CGRectGetMinX(end), f.origin.y, end.size.width, f.size.height);
            if (!CGRectEqualToRect(f, narrowed)) sub.frame = narrowed;
            end.size.height = CGRectGetMaxY(narrowed) - CGRectGetMinY(end);
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
        for (UICollectionViewCell *cell in collection.visibleCells) {
            clearCell(cell);
            narrow(cell, list.bounds.size.width);
            setType(cell);
            setTile(cell);
            NSIndexPath *path = [collection indexPathForCell:cell];
            setRule(cell, path && path.item < [collection numberOfItemsInSection:path.section] - 1);
        }
        SGCardSections(list, collectionRects(collection), SGCardRadius);
    } else if ([list isKindOfClass:UITableView.class]) {
        UITableView *table = (UITableView *)list;
        // A table lays its cells as wide as itself whatever its inset, so each is narrowed after its pass.
        for (UITableViewCell *cell in table.visibleCells) {
            clearCell(cell);
            narrow(cell, table.bounds.size.width);
            setType(cell);
            setTile(cell);
        }
        NSMutableArray<NSValue *> *rects = [NSMutableArray array];
        for (NSValue *rect in SGTableSectionRects(table))
            [rects addObject:[NSValue valueWithCGRect:CGRectIsEmpty(rect.CGRectValue) ? CGRectZero : CGRectInset(rect.CGRectValue, kSideInset, 0)]];
        SGCardSections(list, rects, SGCardRadius);
    }
}

static void watch(UIScrollView *list) {
    if (objc_getAssociatedObject(list, &kStyledKey)) {
        restyle(list);
        return;
    }
    objc_setAssociatedObject(list, &kStyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL watched = SGRObserveLayout(list, ^(UIView *view) { restyle((UIScrollView *)view); });
    SGLog(@"redesign settings: %@ drawn as iOS Settings%@", NSStringFromClass(list.class), watched ? @"" : @" (not watched for its layout)");
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
    SGPagesNativeLook = YES;
    %init;
}
