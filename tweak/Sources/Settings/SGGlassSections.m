#import "SGGlassSections.h"
#import "SGPageStyle.h"
#import "Core/SGGlass.h"
#import <objc/runtime.h>

BOOL SGPagesUseGlass;
const CGFloat SGGlassSectionRadius = 22;
static char kPanesKey;

UIColor *SGCellBackground(void) {
    return SGPagesUseGlass ? UIColor.clearColor : SGCardBackground();
}

void SGGlassSections(UIScrollView *list, NSArray<NSValue *> *rects, CGFloat radius) {
    NSMutableArray<UIVisualEffectView *> *panes = objc_getAssociatedObject(list, &kPanesKey);
    if (!panes) {
        panes = [NSMutableArray array];
        objc_setAssociatedObject(list, &kPanesKey, panes, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (NSUInteger i = 0; i < rects.count; i++) {
        if (panes.count <= i) {
            UIVisualEffectView *pane = [[UIVisualEffectView alloc] initWithEffect:SGGlassEffect()];
            pane.userInteractionEnabled = NO;
            pane.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            // Behind the rows, which are the list's subviews too and come and go as it scrolls.
            pane.layer.zPosition = -1;
            [panes addObject:pane];
        }
        UIVisualEffectView *pane = panes[i];
        CGRect rect = rects[i].CGRectValue;
        pane.hidden = CGRectIsEmpty(rect);
        if (pane.hidden) continue;
        if (!CGRectEqualToRect(pane.frame, rect)) {
            pane.frame = rect;
            SGShapeGlass(pane, MIN(radius, rect.size.height / 2), NO);
        }
        if (pane.superview != list) [list insertSubview:pane atIndex:0];
    }
    for (NSUInteger i = rects.count; i < panes.count; i++) panes[i].hidden = YES;
}

NSArray<NSValue *> *SGTableSectionRects(UITableView *table) {
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    // The cells' own inset, from one on screen; the table's margins until one is.
    CGFloat left = table.layoutMargins.left, right = table.bounds.size.width - table.layoutMargins.right;
    for (UITableViewCell *cell in table.visibleCells) {
        if (cell.frame.size.width < table.bounds.size.width - 1) {
            left = CGRectGetMinX(cell.frame);
            right = CGRectGetMaxX(cell.frame);
        }
        break;
    }
    for (NSInteger section = 0; section < table.numberOfSections; section++) {
        NSInteger rows = [table numberOfRowsInSection:section];
        if (!rows) {
            [rects addObject:[NSValue valueWithCGRect:CGRectZero]];
            continue;
        }
        CGRect first = [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
        CGRect last = [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:rows - 1 inSection:section]];
        [rects addObject:[NSValue valueWithCGRect:CGRectMake(left, CGRectGetMinY(first), right - left, CGRectGetMaxY(last) - CGRectGetMinY(first))]];
    }
    return rects;
}
