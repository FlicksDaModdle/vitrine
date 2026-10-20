// vitrine: links, Vitrine's own link type. A re-signed Spotify shares spotify: with the App Store
// Spotify when both are installed, and iOS hands a shared scheme to the one it registered first, so a
// link that must reach this app is written vitrine:track:<id> (the Safari extension's, from the IPA build
// workflow). scripts/pipeline.sh adds the scheme to Info.plist from plist/liquid-glass.plist; here it is
// turned back into spotify:track:<id> before Spotify reads it, so Spotify's own routing opens it, cold
// launch included.
//
// Accepted forms: vitrine:track:<id>, vitrine://track/<id>, vitrine://open.spotify.com/track/<id>.
#import "Core/SGCore.h"
#import <objc/runtime.h>

static NSURL *sg_vitrineToSpotify(NSURL *url) {
    if (![url.scheme.lowercaseString isEqualToString:@"vitrine"]) return url;
    NSString *rest = [url.absoluteString substringFromIndex:@"vitrine:".length];
    while ([rest hasPrefix:@"/"]) rest = [rest substringFromIndex:1];
    if ([rest hasPrefix:@"open.spotify.com/"]) rest = [rest substringFromIndex:@"open.spotify.com/".length];
    // The web's path form (track/<id>?si=...) becomes the URI form (track:<id>), and its query goes.
    if ([rest rangeOfString:@":"].location == NSNotFound) {
        rest = [rest componentsSeparatedByString:@"?"].firstObject;
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *p in [rest componentsSeparatedByString:@"/"])
            if (p.length && ![p hasPrefix:@"intl-"]) [parts addObject:p];
        rest = [parts componentsJoinedByString:@":"];
    }
    NSURL *out = rest.length ? [NSURL URLWithString:[@"spotify:" stringByAppendingString:rest]] : nil;
    SGLog(@"links: %@ -> %@", url, out);
    return out ?: url;
}

// A scene-based launch or open reads the link off its UIOpenURLContext.
%hook UIOpenURLContext
- (NSURL *)URL {
    return sg_vitrineToSpotify(%orig);
}
%end

// One without scenes gets -application:openURL:options: on the app delegate, whose class is known only
// once it is set.
static BOOL (*sg_origOpenURL)(id, SEL, UIApplication *, NSURL *, NSDictionary *);

static BOOL sg_openURL(id self, SEL _cmd, UIApplication *app, NSURL *url, NSDictionary *options) {
    return sg_origOpenURL(self, _cmd, app, sg_vitrineToSpotify(url), options);
}

static void sg_hookDelegateClass(Class cls) {
    if (sg_origOpenURL) return;
    SEL sel = @selector(application:openURL:options:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    sg_origOpenURL = (BOOL (*)(id, SEL, UIApplication *, NSURL *, NSDictionary *))method_getImplementation(m);
    // Added on the delegate's own class when it only inherits the method, so its superclass is untouched.
    if (!class_addMethod(cls, sel, (IMP)sg_openURL, method_getTypeEncoding(m)))
        method_setImplementation(m, (IMP)sg_openURL);
}

%hook UIApplication
- (void)setDelegate:(id)delegate {
    if (delegate) sg_hookDelegateClass(object_getClass(delegate));
    %orig;
}
%end

%ctor {
    %init;
}
