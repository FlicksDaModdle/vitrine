#import "SGSettingsLook.h"
#import "SGPageStyle.h"
#import <objc/runtime.h>

BOOL SGPagesNativeLook;
const CGFloat SGCardRadius = 26;
static char kCardsKey;

UIColor *SGCellBackground(void) {
    return SGCardBackground();
}

void SGCardSections(UIScrollView *list, NSArray<NSValue *> *rects, CGFloat radius) {
    NSMutableArray<UIView *> *cards = objc_getAssociatedObject(list, &kCardsKey);
    if (!cards) {
        cards = [NSMutableArray array];
        objc_setAssociatedObject(list, &kCardsKey, cards, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (NSUInteger i = 0; i < rects.count; i++) {
        if (cards.count <= i) {
            UIView *card = [UIView new];
            card.userInteractionEnabled = NO;
            card.backgroundColor = SGCardBackground();
            card.layer.cornerCurve = kCACornerCurveContinuous;
            // Behind the rows, which are the list's subviews too and come and go as it scrolls.
            card.layer.zPosition = -1;
            [cards addObject:card];
        }
        UIView *card = cards[i];
        CGRect rect = rects[i].CGRectValue;
        card.hidden = CGRectIsEmpty(rect);
        if (card.hidden) continue;
        if (!CGRectEqualToRect(card.frame, rect)) card.frame = rect;
        card.layer.cornerRadius = MIN(radius, rect.size.height / 2);
        if (card.superview != list) [list insertSubview:card atIndex:0];
    }
    for (NSUInteger i = rects.count; i < cards.count; i++) cards[i].hidden = YES;
}

NSArray<NSValue *> *SGTableSectionRects(UITableView *table) {
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    CGFloat left = 0, right = table.bounds.size.width - table.contentInset.left - table.contentInset.right;
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
