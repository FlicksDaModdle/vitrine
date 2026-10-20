// A probe for the profile menu, nothing more: when Spotify's side drawer (the avatar's) first appears, its view tree
// goes to the log (Share diagnostics), each view's class, size, accessibility identifier and text, so the drawer's
// rows can be offered from a menu of the mod's. It changes nothing.
#import <objc/runtime.h>
#import "Core/SGCore.h"

static const NSUInteger kMaxLines = 260;

static void dump(UIView *view, NSUInteger depth, NSMutableArray<NSString *> *lines) {
    if (lines.count >= kMaxLines || depth > 30) return;
    NSString *text = nil;
    if ([view isKindOfClass:UILabel.class]) text = ((UILabel *)view).text;
    else if ([view isKindOfClass:UIButton.class]) text = ((UIButton *)view).currentTitle;
    NSString *identifier = view.accessibilityIdentifier;
    NSString *label = view.isAccessibilityElement ? view.accessibilityLabel : nil;
    [lines addObject:[NSString stringWithFormat:@"%lu %@ %.0fx%.0f%@%@%@%@", (unsigned long)depth, NSStringFromClass(view.class),
                      view.bounds.size.width, view.bounds.size.height,
                      identifier.length ? [@" id=" stringByAppendingString:identifier] : @"",
                      text.length ? [NSString stringWithFormat:@" \"%@\"", text] : @"",
                      label.length ? [NSString stringWithFormat:@" ax=\"%@\"", label] : @"",
                      view.gestureRecognizers.count ? [NSString stringWithFormat:@" gestures=%lu", (unsigned long)view.gestureRecognizers.count] : @""]];
    for (UIView *sub in view.subviews) dump(sub, depth + 1, lines);
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *name = NSStringFromClass(((UIViewController *)self).class);
    if (![name.lowercaseString containsString:@"drawer"]) return;
    static NSMutableSet<NSString *> *seen;
    if (!seen) seen = [NSMutableSet set];
    if ([seen containsObject:name]) return;
    [seen addObject:name];
    UIViewController *controller = (UIViewController *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        if (controller.viewIfLoaded) dump(controller.viewIfLoaded, 0, lines);
        SGLog(@"drawer probe: %@, %lu views", name, (unsigned long)lines.count);
        NSMutableString *chunk = [NSMutableString string];
        for (NSString *line in lines) {
            if (chunk.length + line.length > 800) {
                SGLog(@"drawer probe: %@", chunk);
                [chunk setString:@""];
            }
            [chunk appendFormat:@"%@ ; ", line];
        }
        if (chunk.length) SGLog(@"drawer probe: %@", chunk);
    });
}
%end
