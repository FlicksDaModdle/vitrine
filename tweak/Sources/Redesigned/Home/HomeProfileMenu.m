// Home redesign: the avatar in the title row's pill opens a menu of the system's (Liquid Glass from iOS 26) with the
// side drawer's rows, in place of the drawer sliding in: View profile, Your Premium, Listening stats, Recents, Taste
// Profile, Your Updates, Settings and privacy, Mod Settings, Add account, and Show all for the drawer itself
// (friends' activity, messages).
//
// A row is opened through the drawer, which is the only thing that knows where each one leads: the window is
// covered by a still picture of itself, the drawer is opened under it by the avatar's own button, the row is found
// by its accessibility identifier and its list row fired the way a tap fires it (the cell's own taps if that does
// not take), and the picture fades once the drawer has closed behind the page it opened. A row not found in time
// leaves the drawer open, the picture gone, for a tap by hand.
//
// The drawer (Diagnostics/DrawerProbe.x, Spotify 9.1.90): SideDrawer_ECMKit.SideDrawerContainer >
// SideDrawer_ListPageImpl.ListViewController > SideDrawerListCollectionView, its rows Element_List cells:
// SideDrawer.YourSoundCapsule (Listening stats), .Recents, .TasteProfile, .YourUpdates, .Settings,
// Components.UI.YourPlanRowSideDrawer (Your Premium), AccountSwitching.AddAccountRow, and the profile card's
// Encore.ListRow holding "View profile".
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Settings/SGPage.h"
#import "Home.h"

static const NSTimeInterval kFindEvery = 0.1, kFindFor = 2.5, kSettle = 0.35, kCloseFor = 2.5;

// The still picture of the screen, in a window of its own above every other: the drawer comes in a container
// Spotify adds over the page after the picture, so a picture inside the page's window ends up under it.
static UIWindow *sg_cover;

static void cover(UIWindow *window) {
    UIView *picture = [window snapshotViewAfterScreenUpdates:NO];
    if (!picture || !window.windowScene) return;
    sg_cover = [[UIWindow alloc] initWithWindowScene:window.windowScene];
    sg_cover.windowLevel = UIWindowLevelStatusBar + 50;
    sg_cover.frame = window.frame;
    UIViewController *holder = [UIViewController new];
    holder.view.backgroundColor = UIColor.blackColor;
    picture.frame = holder.view.bounds;
    picture.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [holder.view addSubview:picture];
    sg_cover.rootViewController = holder;
    sg_cover.hidden = NO;   // shown, not made key: the app's own window keeps the keyboard and its presentations
}

static void uncover(void) {
    UIWindow *window = sg_cover;
    sg_cover = nil;
    [UIView animateWithDuration:0.25 animations:^{ window.alpha = 0; } completion:^(BOOL finished) { window.hidden = YES; }];
}

// Whether the drawer is still on screen, in any of the scene's windows but the cover.
static BOOL drawerShown(UIWindowScene *scene) {
    for (UIWindow *window in scene.windows) {
        if (window == sg_cover || window.hidden) continue;
        __block BOOL shown = NO;
        SGForEachView(window, ^(UIView *v) {
            if (!shown && [v.accessibilityIdentifier isEqualToString:@"SideDrawerView"] && v.window && v.alpha > 0.01 && !v.hidden) {
                CGRect onScreen = [v convertRect:v.bounds toView:nil];
                shown = CGRectIntersectsRect(onScreen, window.bounds) && CGRectGetMaxX(onScreen) > 20;
            }
        });
        if (shown) return YES;
    }
    return NO;
}

static UIView *rowIn(UIWindowScene *scene, NSString *identifier) {
    __block UIView *row = nil;
    BOOL profile = [identifier isEqualToString:@"profile"];
    for (UIWindow *window in scene.windows) {
        if (window == sg_cover || row) continue;
        SGForEachView(window, ^(UIView *v) {
            if (row) return;
            if (!profile && [v.accessibilityIdentifier isEqualToString:identifier]) row = v;
            if (profile && [v isKindOfClass:UILabel.class] && [((UILabel *)v).text isEqualToString:@"View profile"]) {
                for (UIView *up = v.superview; up; up = up.superview) {
                    if ([up.accessibilityIdentifier isEqualToString:@"Encore.ListRow"]) { row = up; break; }
                }
            }
        });
    }
    return row;
}

// The row's Encore list row, the view that answers a tap: the row itself (Your Premium, Add account, the profile)
// or the one inside its container (the navigation rows, SideDrawer.Recents > Encore.ListRow).
static UIView *listRowIn(UIView *row) {
    if ([NSStringFromClass(row.class) containsString:@"ListRow"]) return row;
    __block UIView *found = nil;
    SGForEachView(row, ^(UIView *v) {
        if (!found && [NSStringFromClass(v.class) containsString:@"ListRow"]) found = v;
    });
    return found ?: row;
}

// The taps the row's cell listens for, fired as a tap would: what Element_List rows answer when their list row has
// no control of its own to fire.
static BOOL fireTaps(UIView *row) {
    BOOL fired = NO;
    for (UIView *v = row; v && ![v isKindOfClass:UICollectionView.class]; v = v.superview) {
        for (UIGestureRecognizer *gesture in v.gestureRecognizers) {
            if (![gesture isKindOfClass:UITapGestureRecognizer.class]) continue;
            Ivar targetsIvar = class_getInstanceVariable(UIGestureRecognizer.class, "_targets");
            NSArray *targets = targetsIvar ? object_getIvar(gesture, targetsIvar) : nil;
            for (id entry in [targets isKindOfClass:NSArray.class] ? targets : @[]) {
                Ivar targetIvar = class_getInstanceVariable([entry class], "_target");
                Ivar actionIvar = class_getInstanceVariable([entry class], "_action");
                if (!targetIvar || !actionIvar) continue;
                id target = object_getIvar(entry, targetIvar);
                SEL action = *(SEL *)((uint8_t *)(__bridge void *)entry + ivar_getOffset(actionIvar));
                if (!target || !action || ![target respondsToSelector:action]) continue;
                ((void (*)(id, SEL, id))objc_msgSend)(target, action, gesture);
                fired = YES;
            }
            if (fired) return YES;
        }
    }
    return NO;
}

static void openRow(UIView *row, UIWindowScene *scene) {
    UIView *listRow = listRowIn(row);
    SGLog(@"redesign home: profile menu fires %@ (%@)", row.accessibilityIdentifier, NSStringFromClass(listRow.class));
    SGRActivate(listRow);
    // Still in the drawer a moment on: the cell's own taps instead.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!drawerShown(scene) || !row.window) return;
        BOOL fired = fireTaps(listRow);
        SGLog(@"redesign home: profile menu %@ through the cell's taps", fired ? @"opened it" : @"found no tap to fire");
    });
}

// The cover goes once the drawer has closed behind the page it opened, or after kCloseFor, whichever comes first.
static void uncoverWhenClosed(UIWindowScene *scene, NSTimeInterval waited) {
    if (!drawerShown(scene) || waited >= kCloseFor) {
        if (waited >= kCloseFor) SGLog(@"redesign home: profile menu left the drawer open");
        uncover();
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFindEvery * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        uncoverWhenClosed(scene, waited + kFindEvery);
    });
}

static void lookFor(NSString *identifier, UIWindowScene *scene, NSTimeInterval waited) {
    UIView *row = rowIn(scene, identifier);
    if (row) {
        // The drawer's slide in finished first: a row fired mid-animation does nothing.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            openRow(row, scene);
            uncoverWhenClosed(scene, 0);
        });
        return;
    }
    if (waited >= kFindFor) {
        SGLog(@"redesign home: profile menu did not find %@ in the drawer; left open", identifier);
        uncover();
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFindEvery * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        lookFor(identifier, scene, waited + kFindEvery);
    });
}

static void openThroughDrawer(UIControl *avatar, NSString *identifier) {
    UIWindow *window = avatar.window;
    UIWindowScene *scene = window.windowScene;
    if (!window || !scene || sg_cover) return;
    cover(window);
    SGRActivate(avatar);
    lookFor(identifier, scene, 0);
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

#pragma mark - the avatar's button and pill

// The profile menu's button is clear over Spotify's avatar, so the menu grows out of the avatar and shrinks back
// into it, as the filter button's does into its glyph, rather than out of nothing.
@implementation SGRAvatarMenuButton
- (UITargetedPreview *)avatarPreview {
    UIView *source = self.source;
    if (!source.window || CGRectIsEmpty(source.bounds)) return nil;
    UIPreviewParameters *parameters = [UIPreviewParameters new];
    parameters.backgroundColor = UIColor.clearColor;
    parameters.visiblePath = [UIBezierPath bezierPathWithOvalInRect:source.bounds];
    return [[UITargetedPreview alloc] initWithView:source parameters:parameters];
}
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
    previewForHighlightingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self avatarPreview] ?: [super contextMenuInteraction:interaction previewForHighlightingMenuWithConfiguration:configuration];
}
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
    previewForDismissingMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self avatarPreview] ?: [super contextMenuInteraction:interaction previewForDismissingMenuWithConfiguration:configuration];
}
@end

static char kPillGlassKey, kPillShapeKey, kPillButtonKey;
static const CGFloat kPillPad = 6;

void SGRProfilePillAround(UIView *face) {
    UIView *host = face.superview;
    if (!host || !face.window || CGRectIsEmpty(face.bounds)) return;
    UIView *glass = objc_getAssociatedObject(host, &kPillGlassKey);
    SGRAvatarMenuButton *button = objc_getAssociatedObject(host, &kPillButtonKey);
    if (!SGEnabled(SGRKeyHomeProfileMenu)) {
        glass.hidden = YES;
        button.hidden = YES;
        return;
    }
    if (!glass) {
        glass = [UIView new];
        glass.userInteractionEnabled = NO;
        objc_setAssociatedObject(host, &kPillGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!button) {
        button = [SGRAvatarMenuButton buttonWithType:UIButtonTypeCustom];
        button.accessibilityLabel = @"Profile";
        button.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        __weak UIView *weakFace = face;
        button.menu = [UIMenu menuWithChildren:@[[UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
            completion(SGRHomeProfileMenuElements(weakFace));
        }]]];
        button.showsMenuAsPrimaryAction = YES;
        objc_setAssociatedObject(host, &kPillButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    glass.hidden = NO;
    button.hidden = NO;
    // face.frame carries the move a page gives the avatar by transform (Library), so the pill follows it.
    CGRect avatar = face.frame;
    CGFloat side = MAX(avatar.size.width, avatar.size.height) + 2 * kPillPad;
    CGRect pill = CGRectMake(round(CGRectGetMidX(avatar) - side / 2), round(CGRectGetMidY(avatar) - side / 2), side, side);
    if (!CGRectEqualToRect(glass.frame, pill)) glass.frame = pill;
    SGRGlassCapsuleInside(glass, &kPillShapeKey, pill.size, NO);
    if (glass.superview != host) [host insertSubview:glass belowSubview:face];
    __block UIView *control = nil;
    SGForEachView(face, ^(UIView *v) { if (!control && [v isKindOfClass:UIControl.class]) control = v; });
    button.source = control ?: face;
    if (!CGRectEqualToRect(button.frame, avatar)) button.frame = avatar;
    if (button.superview != host) [host addSubview:button];
    else if (host.subviews.lastObject != button) [host bringSubviewToFront:button];
}
