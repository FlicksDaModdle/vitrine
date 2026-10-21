// Settings redesign: Spotify's settings pages shown as one of the mod's own (Settings/SGModPage.m's look): a table of
// inset grouped cards on black, each row a gray tile, a 17 pt title and a chevron, a switch or a value, at the
// system's row height. Spotify's own list stays behind it, unseen and untouched by touch, and is what each row
// reads from and acts through: its text, its switch's state and what a tap on it does.
//
// SettingsListViewController's view holds Spotify's SettingsListCollectionView (App/ModSettings.x). The list is kept
// as tall as its content so every row has a cell, and the rows are read from those cells after each of its passes: a
// cell's labels top to bottom are its title and what is under it, a label beside the title its value, and a switch
// in it its state. A tap selects the item through the list's own delegate, or fires the cell the way a tap would; a
// switch is flipped and fires its own action. Mod Settings' row, which App/ModSettings.x lays in the list, is a row
// here too. A page holding what a row cannot stand in for (a slider, a text field, a segmented control) is left as
// Spotify draws it, under SettingsLook.x's cards.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGSettingsLook.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRRestyle.h"

@interface SGRSettingsItem : NSObject
@property (nonatomic, copy) NSString *title, *subtitle, *value;
@property (nonatomic) BOOL hasSwitch, on, opens;
@property (nonatomic, strong) NSIndexPath *path;       // nil for a view of the list's that is not a cell
@property (nonatomic, weak) UIView *source;
@end
@implementation SGRSettingsItem
@end

@interface SGRSettingsMirror : UITableView <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, weak) UICollectionView *list;
@property (nonatomic, copy) NSArray<NSArray<SGRSettingsItem *> *> *sections;
@property (nonatomic, copy) NSArray<NSString *> *headers;
@property (nonatomic, copy) NSString *signature;
@end

static char kMirrorKey, kBailKey;

// What a row is called, as a symbol and a tile color in the Settings app's manner.
static void symbolFor(NSString *title, NSString **symbol, UIColor **color) {
    NSString *t = title.lowercaseString;
    NSArray *table = @[
        @[@"account", @"person.crop.circle.fill", UIColor.systemBlueColor],
        @[@"parental", @"figure.and.child.holdinghands", UIColor.systemOrangeColor],
        @[@"content", @"music.note", UIColor.systemPinkColor],
        @[@"privacy", @"hand.raised.fill", UIColor.systemBlueColor],
        @[@"playback", @"play.fill", UIColor.systemRedColor],
        @[@"notification", @"bell.badge.fill", UIColor.systemRedColor],
        @[@"apps", @"iphone", UIColor.systemIndigoColor],
        @[@"device", @"hifispeaker.fill", UIColor.systemIndigoColor],
        @[@"data", @"arrow.down.circle.fill", UIColor.systemGreenColor],
        @[@"offline", @"airplane", UIColor.systemOrangeColor],
        @[@"private session", @"eye.slash.fill", UIColor.systemGrayColor],
        @[@"quality", @"waveform", UIColor.systemTealColor],
        @[@"storage", @"internaldrive.fill", UIColor.systemGrayColor],
        @[@"advert", @"megaphone.fill", UIColor.systemOrangeColor],
        @[@"about", @"info.circle.fill", UIColor.systemGrayColor],
        @[@"log out", @"rectangle.portrait.and.arrow.right", UIColor.systemRedColor],
        @[@"mod settings", @"sparkles", UIColor.systemPurpleColor],
        @[@"language", @"globe", UIColor.systemBlueColor],
        @[@"social", @"person.2.fill", UIColor.systemGreenColor],
        @[@"car", @"car.fill", UIColor.systemBlueColor],
        @[@"voice", @"mic.fill", UIColor.systemPinkColor],
        @[@"local", @"folder.fill", UIColor.systemBlueColor],
        @[@"explicit", @"e.square.fill", UIColor.systemGrayColor],
        @[@"video", @"play.rectangle.fill", UIColor.systemRedColor],
        @[@"autoplay", @"infinity", UIColor.systemPurpleColor],
        @[@"crossfade", @"arrow.triangle.merge", UIColor.systemTealColor],
        @[@"equalizer", @"slider.vertical.3", UIColor.systemOrangeColor],
        @[@"download", @"arrow.down.to.line", UIColor.systemGreenColor],
        @[@"email", @"envelope.fill", UIColor.systemBlueColor],
        @[@"push", @"app.badge.fill", UIColor.systemRedColor],
    ];
    for (NSArray *entry in table) {
        if ([t containsString:entry[0]]) {
            *symbol = entry[1];
            *color = entry[2];
            return;
        }
    }
    *symbol = nil;
    *color = nil;
}

#pragma mark - reading the list

static BOOL unsupported(UIView *cell) {
    __block BOOL found = NO;
    SGForEachView(cell, ^(UIView *v) {
        if (found || v.hidden) return;
        if ([v isKindOfClass:UISlider.class] || [v isKindOfClass:UITextField.class] || [v isKindOfClass:UISegmentedControl.class]
            || [v isKindOfClass:UIStepper.class] || ([v isKindOfClass:UITextView.class] && ((UITextView *)v).editable)) found = YES;
    });
    return found;
}

static SGRSettingsItem *itemOf(UIView *cell) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    __block UISwitch *toggle = nil;
    __block BOOL chevron = NO;
    CGFloat width = cell.bounds.size.width;
    SGForEachView(cell, ^(UIView *v) {
        if (v.hidden || v.alpha < 0.01) return;
        if ([v isKindOfClass:UILabel.class] && [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) [labels addObject:(UILabel *)v];
        if ([v isKindOfClass:UISwitch.class]) toggle = (UISwitch *)v;
        CGRect f = [v convertRect:v.bounds toView:cell];
        if (![v isKindOfClass:UILabel.class] && f.size.width <= 24 && f.size.width >= 6 && CGRectGetMinX(f) > width - 60) chevron = YES;
    });
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGPoint pa = [a convertPoint:CGPointZero toView:cell], pb = [b convertPoint:CGPointZero toView:cell];
        if (fabs(pa.y - pb.y) > 4) return pa.y < pb.y ? NSOrderedAscending : NSOrderedDescending;
        return pa.x < pb.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    SGRSettingsItem *item = [SGRSettingsItem new];
    if (labels.count) {
        UILabel *title = labels.firstObject;
        item.title = title.text;
        CGFloat titleY = [title convertPoint:CGPointZero toView:cell].y;
        NSMutableArray<NSString *> *under = [NSMutableArray array];
        for (UILabel *label in [labels subarrayWithRange:NSMakeRange(1, labels.count - 1)]) {
            CGPoint at = [label convertPoint:CGPointZero toView:cell];
            if (fabs(at.y - titleY) <= 4 && at.x > width * 0.45) item.value = label.text;
            else [under addObject:label.text];
        }
        if (under.count) item.subtitle = [under componentsJoinedByString:@" "];
    } else {
        // Encore's text is not always a label: its accessibility says the same, title first.
        NSArray<NSString *> *parts = [cell.accessibilityLabel componentsSeparatedByString:@", "];
        item.title = parts.firstObject;
        if (parts.count > 1) item.subtitle = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@", "];
    }
    // A cell with no words of its own (a spacer, a picture) is not a row.
    if (![item.title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) return nil;
    item.hasSwitch = toggle != nil;
    item.on = toggle.on;
    item.opens = !toggle && chevron;
    item.source = cell;
    return item;
}

// A cell holding tiles side by side (Data saver mode, Offline mode, Private session): each tile a row of its own,
// its name the title and what is under it the value, a tap firing the tile. nil for a cell of one row.
static NSArray<SGRSettingsItem *> *tilesOf(UIView *cell) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(cell, ^(UIView *v) {
        if (!v.hidden && v.alpha >= 0.01 && [v isKindOfClass:UILabel.class] && [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) [labels addObject:(UILabel *)v];
    });
    CGFloat width = cell.bounds.size.width;
    // Columns: labels whose spans across the cell do not overlap.
    NSMutableArray<NSMutableArray<UILabel *> *> *columns = [NSMutableArray array];
    NSMutableArray<NSValue *> *spans = [NSMutableArray array];
    for (UILabel *label in labels) {
        CGRect f = [label convertRect:label.bounds toView:cell];
        NSUInteger hit = NSNotFound;
        for (NSUInteger i = 0; i < spans.count; i++) {
            CGRect span = spans[i].CGRectValue;
            if (CGRectGetMinX(f) < CGRectGetMaxX(span) && CGRectGetMaxX(f) > CGRectGetMinX(span)) { hit = i; break; }
        }
        if (hit == NSNotFound) {
            [columns addObject:[NSMutableArray arrayWithObject:label]];
            [spans addObject:[NSValue valueWithCGRect:CGRectMake(CGRectGetMinX(f), 0, f.size.width, 1)]];
        } else {
            [columns[hit] addObject:label];
            CGRect span = spans[hit].CGRectValue;
            spans[hit] = [NSValue valueWithCGRect:CGRectUnion(span, CGRectMake(CGRectGetMinX(f), 0, f.size.width, 1))];
        }
    }
    if (columns.count < 2) return nil;
    for (NSValue *span in spans) if (span.CGRectValue.size.width > width * 0.6) return nil;
    NSMutableArray<SGRSettingsItem *> *items = [NSMutableArray array];
    NSArray *order = [[NSArray arrayWithArray:columns] sortedArrayUsingComparator:^NSComparisonResult(NSArray<UILabel *> *a, NSArray<UILabel *> *b) {
        CGFloat xa = [a.firstObject convertPoint:CGPointZero toView:cell].x, xb = [b.firstObject convertPoint:CGPointZero toView:cell].x;
        return xa < xb ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (NSMutableArray<UILabel *> *column in order) {
        [column sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
            CGFloat ya = [a convertPoint:CGPointZero toView:cell].y, yb = [b convertPoint:CGPointZero toView:cell].y;
            return ya < yb ? NSOrderedAscending : NSOrderedDescending;
        }];
        SGRSettingsItem *item = [SGRSettingsItem new];
        item.title = column.firstObject.text;
        NSMutableArray<NSString *> *rest = [NSMutableArray array];
        for (UILabel *label in [column subarrayWithRange:NSMakeRange(1, column.count - 1)]) [rest addObject:label.text];
        if (rest.count) item.value = [rest componentsJoinedByString:@" "];
        // The tile: the widest view around its labels that is still narrower than the cell.
        UIView *tile = column.firstObject;
        for (UIView *v = column.firstObject.superview; v && v != cell; v = v.superview) {
            BOOL holds = YES;
            for (UILabel *label in column) holds &= [label isDescendantOfView:v];
            if (holds && v.bounds.size.width < width * 0.6) tile = v;
            if (v.bounds.size.width >= width * 0.6) break;
        }
        item.source = tile;
        [items addObject:item];
    }
    return items;
}

// Every row of the list, by section, with each section's header text; nil when the page cannot be shown this way.
static NSArray *readList(UICollectionView *list, NSArray<NSString *> **headers) {
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSInteger section = 0; section < list.numberOfSections; section++) {
        NSMutableArray<SGRSettingsItem *> *rows = [NSMutableArray array];
        for (NSInteger index = 0; index < [list numberOfItemsInSection:section]; index++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:index inSection:section];
            UICollectionViewCell *cell = [list cellForItemAtIndexPath:path];
            if (!cell) return nil;   // not laid out yet
            if (unsupported(cell)) {
                *headers = nil;
                return @[];
            }
            NSArray<SGRSettingsItem *> *tiles = tilesOf(cell);
            if (tiles) {
                [rows addObjectsFromArray:tiles];
                continue;
            }
            SGRSettingsItem *item = itemOf(cell);
            if (!item) continue;
            item.path = path;
            [rows addObject:item];
        }
        // The section's header: the text of a supplementary view over its first row.
        NSString *header = @"";
        UICollectionReusableView *view = nil;
        if ([list numberOfItemsInSection:section]) {
            @try {
                view = [list supplementaryViewForElementKind:UICollectionElementKindSectionHeader atIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]];
            } @catch (NSException *e) { view = nil; }
        }
        __block NSString *text = nil;
        if (view) SGForEachView(view, ^(UIView *v) { if (!text && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) text = ((UILabel *)v).text; });
        if (text) header = text;
        if (rows.count) {
            [sections addObject:rows];
            [titles addObject:header];
        }
    }
    // Mod Settings' row, a view of the list's under its rows.
    for (UIView *sub in list.subviews) {
        if (![sub isKindOfClass:UIControl.class] || sub.hidden) continue;
        __block NSString *text = nil;
        SGForEachView(sub, ^(UIView *v) { if (!text && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) text = ((UILabel *)v).text; });
        if (!text) continue;
        SGRSettingsItem *item = [SGRSettingsItem new];
        item.title = text;
        item.opens = YES;
        item.source = sub;
        [sections addObject:@[item]];
        [titles addObject:@""];
    }
    *headers = titles;
    return sections;
}

#pragma mark - the page

@implementation SGRSettingsMirror

- (instancetype)initWithList:(UICollectionView *)list {
    if (!(self = [super initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped])) return nil;
    _list = list;
    self.dataSource = self;
    self.delegate = self;
    self.backgroundColor = SGPageBackground();
    self.separatorColor = [UIColor colorWithWhite:1 alpha:0.1];
    self.sectionHeaderTopPadding = 0;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAlways;
    SGInsetForBars(self);
    return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = self.headers[section];
    return title.length ? SGSectionHeader(table, title) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return self.headers[section].length ? SGSectionHeaderHeight() : SGSectionGap;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return [UIView new];
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGRSettingsItem *item = self.sections[path.section][path.row];
    UITableViewCell *cell = SGDequeueCell(table, @"spotify");
    // A row that opens a page says only its name, as Settings' do; a switch or a value keeps what explains it.
    SGFillCell(cell, item.title, item.opens ? nil : item.subtitle, nil, nil);
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    NSString *symbol = nil;
    UIColor *color = nil;
    symbolFor(item.title, &symbol, &color);
    content.image = color ? SGTileImageTinted(symbol, color) : SGTileImage(@"gearshape.fill");
    content.imageToTextPadding = 13;
    cell.contentConfiguration = content;
    cell.separatorInset = UIEdgeInsetsMake(0, SGTileRowInset, 0, 0);
    cell.selectionStyle = item.hasSwitch ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    if (item.hasSwitch) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = item.on;
        toggle.onTintColor = SGGreen();
        toggle.tag = path.section * 1000 + path.row;
        [toggle addTarget:self action:@selector(flipped:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (item.value.length) {
        UILabel *value = [UILabel new];
        value.text = item.value;
        value.font = SGTitleFont();
        value.textColor = SGGrey();
        [value sizeToFit];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:item.opens ? @[value, SGChevronView()] : @[value]];
        stack.spacing = 8;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.frame = CGRectMake(0, 0, value.bounds.size.width + (item.opens ? 24 : 0), 30);
        cell.accessoryView = stack;
    } else {
        cell.accessoryView = item.opens ? SGChevronView() : nil;
    }
    return cell;
}

- (void)flipped:(UISwitch *)toggle {
    SGRSettingsItem *item = self.sections[toggle.tag / 1000][toggle.tag % 1000];
    __block UISwitch *theirs = nil;
    SGForEachView(item.source, ^(UIView *v) { if (!theirs && [v isKindOfClass:UISwitch.class]) theirs = (UISwitch *)v; });
    if (!theirs) return;
    [theirs setOn:toggle.on animated:NO];
    [theirs sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    SGRSettingsItem *item = self.sections[path.section][path.row];
    UICollectionView *list = self.list;
    if (item.hasSwitch) return;
    if (!item.path || !list || ![list.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        SGRActivate(item.source);
        return;
    }
    // Through the list's delegate, as a tap on the cell selects it; the cell itself fired if nothing came of that.
    UIViewController *owner = nil;
    for (UIResponder *r = self.nextResponder; r; r = r.nextResponder) if ([r isKindOfClass:UIViewController.class]) { owner = (UIViewController *)r; break; }
    UIViewController *top = owner.navigationController.topViewController;
    [list.delegate collectionView:list didSelectItemAtIndexPath:item.path];
    __weak UIViewController *weakOwner = owner;
    __weak UIView *source = item.source;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *o = weakOwner;
        if (!o || o.presentedViewController || o.navigationController.topViewController != top) return;
        SGLog(@"redesign settings: selecting %@ did nothing, the cell is fired", item.title);
        SGRActivate(source);
    });
}

@end

#pragma mark - the hook

// The list as tall as all it holds, so every row has a cell to read, kept out of sight and out of reach.
static void hideList(UICollectionView *list, UIView *root) {
    list.alpha = 0.011;
    list.userInteractionEnabled = NO;
    list.accessibilityElementsHidden = YES;
    CGFloat tall = MAX(root.bounds.size.height, list.contentSize.height + list.adjustedContentInset.top + list.adjustedContentInset.bottom);
    CGRect frame = CGRectMake(0, 0, root.bounds.size.width, tall);
    if (!CGRectEqualToRect(list.frame, frame)) list.frame = frame;
}

static void showList(UICollectionView *list) {
    list.alpha = 1;
    list.userInteractionEnabled = YES;
    list.accessibilityElementsHidden = NO;
}

static NSString *signatureOf(NSArray<NSArray<SGRSettingsItem *> *> *sections, NSArray<NSString *> *headers) {
    NSMutableString *s = [NSMutableString stringWithString:[headers componentsJoinedByString:@"|"]];
    for (NSArray<SGRSettingsItem *> *rows in sections)
        for (SGRSettingsItem *item in rows) [s appendFormat:@"/%@~%@~%@~%d%d%d", item.title, item.subtitle ?: @"", item.value ?: @"", item.hasSwitch, item.on, item.opens];
    return s;
}

static void mirror(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (!root.window) return;
    UICollectionView *list = nil;
    for (UIView *sub in root.subviews) if ([sub isKindOfClass:UICollectionView.class]) { list = (UICollectionView *)sub; break; }
    if (!list) return;
    if (objc_getAssociatedObject(list, &kBailKey)) return;
    SGRSettingsMirror *page = objc_getAssociatedObject(controller, &kMirrorKey);
    if (!page) {
        page = [[SGRSettingsMirror alloc] initWithList:list];
        objc_setAssociatedObject(controller, &kMirrorKey, page, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIViewController *weak = controller;
        SGRObserveLayout(list, ^(UIView *v) {
            UIViewController *owner = weak;
            if (owner) dispatch_async(dispatch_get_main_queue(), ^{ mirror(owner); });
        });
    }
    hideList(list, root);
    [list layoutIfNeeded];
    NSArray<NSString *> *headers = nil;
    NSArray *sections = readList(list, &headers);
    if (sections && !headers) {
        // A page with a control a row cannot stand in for: Spotify's, as it is.
        objc_setAssociatedObject(list, &kBailKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [page removeFromSuperview];
        showList(list);
        SGLog(@"redesign settings: %@ keeps Spotify's own list", NSStringFromClass(controller.class));
        return;
    }
    if (!sections.count) return;   // not laid out yet, or nothing read: the next pass tries again
    CGRect frame = root.bounds;
    if (!CGRectEqualToRect(page.frame, frame)) page.frame = frame;
    if (page.superview != root) {
        [root addSubview:page];
        SGLog(@"redesign settings: %@ drawn as a mod page, %lu sections", NSStringFromClass(controller.class), (unsigned long)sections.count);
    } else if (root.subviews.lastObject != page) [root bringSubviewToFront:page];
    NSString *signature = signatureOf(sections, headers);
    if ([signature isEqualToString:page.signature]) return;
    page.signature = signature;
    page.sections = sections;
    page.headers = headers;
    [page reloadData];
}

%hook _TtC21Settings_PlatformImpl26SettingsListViewController
- (void)viewDidLayoutSubviews {
    %orig;
    mirror((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
