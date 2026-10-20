// "Open in Vitrine", an action extension in the share sheet. A Spotify link shared from any app (Messages,
// Discord, Instagram, Safari) opens in this build instead of the App Store Spotify, which iOS gives
// open.spotify.com and spotify: to when both are installed. The link goes out as vitrine://..., the
// link type only this build claims; Shared/Navigation/VitrineLinks.x turns it back into one Spotify opens.
//
// Built by scripts/build-open-in-vitrine.sh, without an Xcode project.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/message.h>

@interface OIVViewController : UIViewController
@end

static BOOL oiv_isSpotifyHost(NSString *host) {
    host = host.lowercaseString;
    for (NSString *h in @[@"open.spotify.com", @"spotify.app.link", @"spotify.link", @"spotify.com"])
        if ([host isEqualToString:h] || [host hasSuffix:[@"." stringByAppendingString:h]]) return YES;
    return NO;
}

// https://open.spotify.com/track/<id>?si=... -> vitrine://open.spotify.com/track/<id>?si=...
// spotify:track:<id> -> vitrine:track:<id>. Anything else is nil.
static NSURL *oiv_vitrineURL(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"vitrine"]) return url;
    if ([scheme isEqualToString:@"spotify"]) {
        NSString *rest = [url.absoluteString substringFromIndex:@"spotify:".length];
        return [NSURL URLWithString:[@"vitrine:" stringByAppendingString:rest]];
    }
    if (([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) && oiv_isSpotifyHost(url.host)) {
        NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        c.scheme = @"vitrine";
        return c.URL;
    }
    return nil;
}

// The first Spotify link in shared text ("Listen to this https://open.spotify.com/...").
static NSURL *oiv_linkInText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return nil;
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
    for (NSTextCheckingResult *match in [detector matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        if (oiv_vitrineURL(match.URL)) return match.URL;
    }
    NSRange uri = [text rangeOfString:@"spotify:[A-Za-z]+:[A-Za-z0-9:]+" options:NSRegularExpressionSearch];
    return uri.location == NSNotFound ? nil : [NSURL URLWithString:[text substringWithRange:uri]];
}

@implementation OIVViewController {
    BOOL _started;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_started) return;
    _started = YES;
    [self findLink:^(NSURL *link) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSURL *target = oiv_vitrineURL(link);
            if (target) [self openAndFinish:target];
            else [self failWithMessage:@"There's no Spotify link in what was shared."];
        });
    }];
}

// URLs first, then text with a link in it; every provider is asked, since apps order them differently.
- (void)findLink:(void (^)(NSURL *))done {
    NSMutableArray<NSItemProvider *> *urls = [NSMutableArray array], *texts = [NSMutableArray array];
    for (NSExtensionItem *item in self.extensionContext.inputItems) {
        for (NSItemProvider *provider in item.attachments) {
            if ([provider hasItemConformingToTypeIdentifier:UTTypeURL.identifier]) [urls addObject:provider];
            else if ([provider hasItemConformingToTypeIdentifier:UTTypePlainText.identifier]) [texts addObject:provider];
        }
        NSURL *inTitle = oiv_linkInText(item.attributedContentText.string);
        if (inTitle) { done(inTitle); return; }
    }
    [self tryURLs:urls texts:texts done:done];
}

- (void)tryURLs:(NSMutableArray<NSItemProvider *> *)urls texts:(NSMutableArray<NSItemProvider *> *)texts done:(void (^)(NSURL *))done {
    if (urls.count) {
        NSItemProvider *provider = urls.firstObject;
        [urls removeObjectAtIndex:0];
        [provider loadItemForTypeIdentifier:UTTypeURL.identifier options:nil completionHandler:^(id item, NSError *error) {
            NSURL *url = [item isKindOfClass:NSURL.class] ? item : nil;
            if (!url && [item isKindOfClass:NSString.class]) url = [NSURL URLWithString:item];
            if (url && oiv_vitrineURL(url)) done(url);
            else [self tryURLs:urls texts:texts done:done];
        }];
        return;
    }
    if (texts.count) {
        NSItemProvider *provider = texts.firstObject;
        [texts removeObjectAtIndex:0];
        [provider loadItemForTypeIdentifier:UTTypePlainText.identifier options:nil completionHandler:^(id item, NSError *error) {
            NSURL *url = oiv_linkInText([item isKindOfClass:NSString.class] ? item : nil);
            if (url) done(url);
            else [self tryURLs:urls texts:texts done:done];
        }];
        return;
    }
    done(nil);
}

// An extension has no UIApplication of its own to call, but the host's is on the responder chain;
// -[NSExtensionContext openURL:] only works from widgets.
- (BOOL)openThroughResponderChain:(NSURL *)url {
    Class appClass = NSClassFromString(@"UIApplication");
    SEL open = NSSelectorFromString(@"openURL:options:completionHandler:");
    for (UIResponder *r = self; r; r = r.nextResponder) {
        if ([r isKindOfClass:appClass] && [r respondsToSelector:open]) {
            ((void (*)(id, SEL, NSURL *, NSDictionary *, id))objc_msgSend)(r, open, url, @{}, nil);
            return YES;
        }
    }
    return NO;
}

- (void)openAndFinish:(NSURL *)url {
    if ([self openThroughResponderChain:url]) {
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
        return;
    }
    [self.extensionContext openURL:url completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
            else [self failWithMessage:@"iOS didn't let the share sheet open Vitrine."];
        });
    }];
}

- (void)failWithMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Open in Vitrine" message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
