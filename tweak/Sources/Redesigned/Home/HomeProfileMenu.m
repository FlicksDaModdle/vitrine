// Home redesign: the avatar in the title row's pill opens a menu of the system's (Liquid Glass from iOS 26) with the
// side drawer's rows, in place of the drawer sliding in: View profile, Your Premium, Listening stats, Recents, Taste
// Profile, Your Updates, Settings and privacy, Mod Settings, Add account, and Show all for the drawer itself
// (friends' activity, messages).
//
// A row is opened through the drawer, which is the only thing that knows where each one leads: the window is
// covered by a still picture of itself, the drawer is opened under it by the avatar's own button, the row is found
// by its accessibility identifier and selected the way a tap selects it, and the picture fades once the page it
// opens is up. A row not found in time leaves the drawer open, the picture gone, for a tap by hand.
//
// The drawer (Diagnostics/DrawerProbe.x, Spotify 9.1.90): SideDrawer_ECMKit.SideDrawerContainer >
// SideDrawer_ListPageImpl.ListViewController > SideDrawerListCollectionView, its rows Element_List cells:
// SideDrawer.YourSoundCapsule (Listening stats), .Recents, .TasteProfile, .YourUpdates, .Settings,
// Components.UI.YourPlanRowSideDrawer (Your Premium), AccountSwitching.AddAccountRow, and the profile card's
// Encore.ListRow holding "View profile".
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Settings/SGPage.h"
#import "Home.h"

static const NSTimeInterval kFindEvery = 0.1, kFindFor = 2.5, kHoldAfter = 0.7;

static UIView *sg_cover;   // the still picture over the window while a row opens

static void uncover(void) {
    UIView *cover = sg_cover;
    sg_cover = nil;
    [UIView animateWithDuration:0.25 animations:^{ cover.alpha = 0; } completion:^(BOOL finished) { [cover removeFromSuperview]; }];
}

static UIView *rowIn(UIView *window, NSString *identifier) {
    __block UIView *row = nil;
    BOOL profile = [identifier isEqualToString:@"profile"];
    SGForEachView(window, ^(UIView *v) {
        if (row) return;
        if (!profile && [v.accessibilityIdentifier isEqualToString:identifier]) row = v;
        if (profile && [v isKindOfClass:UILabel.class] && [((UILabel *)v).text isEqualToString:@"View profile"]) {
            for (UIView *up = v.superview; up; up = up.superview) {
                if ([up.accessibilityIdentifier isEqualToString:@"Encore.ListRow"]) { row = up; break; }
            }
        }
    });
    return row;
}

// The way a tap selects the row: its list's own selection where the list takes one, else its control or its
// accessibility action.
static void openRow(UIView *row) {
    UICollectionViewCell *cell = nil;
    for (UIView *v = row; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionViewCell.class]) { cell = (UICollectionViewCell *)v; break; }
    }
    UICollectionView *list = nil;
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) { list = (UICollectionView *)v; break; }
    }
    NSIndexPath *path = cell && list ? [list indexPathForCell:cell] : nil;
    // The profile card holds two rows in one cell (the profile and Add account): its row is fired, not the cell.
    BOOL wholeCell = path && ![row.accessibilityIdentifier isEqualToString:@"Encore.ListRow"]
                  && ![row.accessibilityIdentifier isEqualToString:@"AccountSwitching.AddAccountRow"];
    if (wholeCell && [list.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        SGLog(@"redesign home: profile menu selects %@ in its list", row.accessibilityIdentifier);
        [list.delegate collectionView:list didSelectItemAtIndexPath:path];
        return;
    }
    SGLog(@"redesign home: profile menu fires %@", row.accessibilityIdentifier);
    SGRActivate(row);
}

static void openThroughDrawer(UIControl *avatar, NSString *identifier) {
    UIWindow *window = avatar.window;
    if (!window || sg_cover) return;
    sg_cover = [window snapshotViewAfterScreenUpdates:NO];
    sg_cover.frame = window.bounds;
    sg_cover.userInteractionEnabled = YES;
    [window addSubview:sg_cover];
    SGRActivate(avatar);
    __block NSTimeInterval waited = 0;
    __block void (^look)(void);
    __block void (^weakLook)(void);
    look = ^{
        UIView *row = rowIn(window, identifier);
        if (row) {
            openRow(row);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHoldAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ uncover(); });
            weakLook = nil;
            return;
        }
        waited += kFindEvery;
        if (waited >= kFindFor) {
            SGLog(@"redesign home: profile menu did not find %@ in the drawer; left open", identifier);
            uncover();
            weakLook = nil;
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFindEvery * NSEC_PER_SEC)), dispatch_get_main_queue(), weakLook);
    };
    weakLook = look;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFindEvery * NSEC_PER_SEC)), dispatch_get_main_queue(), look);
}

// The avatar's own button, the one that opens the drawer.
static UIControl *avatarButton(UIView *face) {
    __block UIControl *button = nil;
    SGForEachView(face, ^(UIView *v) {
        if (!button && [v isKindOfClass:UIControl.class]) button = (UIControl *)v;
    });
    return button;
}

NSArray<UIMenuElement *> *SGRHomeProfileMenuElements(UIView *face) {
    __weak UIControl *avatar = avatarButton(face);
    UIAction *(^row)(NSString *, NSString *, NSString *) = ^UIAction *(NSString *title, NSString *symbol, NSString *identifier) {
        return [UIAction actionWithTitle:title image:[UIImage systemImageNamed:symbol] identifier:nil handler:^(UIAction *action) {
            UIControl *button = avatar;
            if (button) openThroughDrawer(button, identifier);
        }];
    };
    UIMenu *account = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
        row(@"View profile", @"person.crop.circle", @"profile"),
        row(@"Your Premium", @"star.circle", @"Components.UI.YourPlanRowSideDrawer"),
    ]];
    UIMenu *pages = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
        row(@"Listening stats", @"chart.xyaxis.line", @"SideDrawer.YourSoundCapsule"),
        row(@"Recents", @"clock.arrow.circlepath", @"SideDrawer.Recents"),
        row(@"Taste Profile", @"heart.circle", @"SideDrawer.TasteProfile"),
        row(@"Your Updates", @"megaphone", @"SideDrawer.YourUpdates"),
    ]];
    UIAction *mod = [UIAction actionWithTitle:@"Mod Settings" image:[UIImage systemImageNamed:@"slider.horizontal.3"] identifier:nil
                                      handler:^(UIAction *action) { SGOpenModSettings(avatar); }];
    UIMenu *settings = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
        row(@"Settings and privacy", @"gearshape", @"SideDrawer.Settings"), mod,
    ]];
    UIAction *all = [UIAction actionWithTitle:@"Show all" image:[UIImage systemImageNamed:@"sidebar.left"] identifier:nil
                                      handler:^(UIAction *action) { if (avatar) SGRActivate(avatar); }];
    UIMenu *more = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
        row(@"Add account", @"person.badge.plus", @"AccountSwitching.AddAccountRow"), all,
    ]];
    return @[account, pages, settings, more];
}
