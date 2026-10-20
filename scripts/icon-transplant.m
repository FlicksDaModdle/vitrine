// Moves an app icon from one compiled asset catalog into another: every rendition of the names that start with
// "AppIcon" in FROM (the icon, its layered glass stack, its layers) replaces those names' renditions in INTO, the
// rest of INTO left as it is. Built and run on macOS by the IPA workflow (Old icon), through CoreUI's own reader
// and writer, which are private: what they answer to is checked and logged, and anything missing ends the run
// with INTO untouched.
//
//   clang -fobjc-arc -framework Foundation -F/System/Library/PrivateFrameworks -framework CoreUI \
//         scripts/icon-transplant.m -o icon-transplant
//   ./icon-transplant FROM.car INTO.car
//
// A rendition's key is a row of 16-bit values, one per attribute in its catalog's key format, and catalogs can
// order and pick their attributes differently, so each key is read in FROM's format and written in INTO's. A
// name's facet (its own short list of attributes and values, the identifier among them) says which keys are its;
// a name INTO also has keeps INTO's facet values, one it lacks gets values no other name of INTO uses.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

struct sg_keytoken { uint16_t identifier; uint16_t value; };
static const uint16_t kIdentifier = 17;   // kCRThemeIdentifierName
struct sg_keyfmt { uint32_t tag; uint32_t version; uint32_t count; uint32_t attributes[]; };

@interface CUICommonAssetStorage : NSObject
- (instancetype)initWithPath:(NSString *)path;
- (const struct sg_keyfmt *)keyFormat;
- (NSArray<NSData *> *)allAssetKeys;
- (NSData *)assetForKey:(NSData *)key;
- (const struct sg_keytoken *)renditionKeyForName:(const char *)name hotSpot:(CGPoint *)hotSpot;
- (NSArray<NSString *> *)allRenditionNames;
@end

@interface CUIMutableCommonAssetStorage : CUICommonAssetStorage
- (instancetype)initWithPath:(NSString *)path forWriting:(BOOL)writing;
- (BOOL)setAsset:(NSData *)asset forKey:(NSData *)key;
- (BOOL)removeAssetForKey:(NSData *)key;
- (BOOL)setRenditionKey:(const struct sg_keytoken *)key hotSpot:(CGPoint)hotSpot forName:(const char *)name;
- (BOOL)writeToDiskAndCompact:(BOOL)compact;
- (void)setRenditionCount:(unsigned int)count;
- (BOOL)useBitmapIndex;
- (void)updateBitmapInfo;
@end

// A name's facet, its attributes and their values.
static const struct sg_keytoken *facetFor(CUICommonAssetStorage *storage, NSString *name) {
    CGPoint hotSpot = CGPointZero;
    return [storage renditionKeyForName:name.UTF8String hotSpot:&hotSpot];
}

static void need(id object, SEL selector) {
    if ([object respondsToSelector:selector]) return;
    fprintf(stderr, "icon-transplant: %s does not answer %s; its methods:\n", class_getName([object class]), sel_getName(selector));
    unsigned int count = 0;
    for (Class c = [object class]; c && c != NSObject.class; c = class_getSuperclass(c)) {
        Method *methods = class_copyMethodList(c, &count);
        for (unsigned int i = 0; i < count; i++) fprintf(stderr, "  %s -%s\n", class_getName(c), sel_getName(method_getName(methods[i])));
        free(methods);
    }
    exit(2);
}

// A key's attributes by their identifiers, read in its catalog's format.
static NSDictionary<NSNumber *, NSNumber *> *attributesOf(NSData *key, const struct sg_keyfmt *format) {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    const uint16_t *values = key.bytes;
    NSUInteger n = MIN(key.length / 2, format->count);
    for (NSUInteger i = 0; i < n; i++) attributes[@(format->attributes[i])] = @(values[i]);
    return attributes;
}

static NSData *keyFrom(NSDictionary<NSNumber *, NSNumber *> *attributes, const struct sg_keyfmt *format, NSUInteger length) {
    NSMutableData *key = [NSMutableData dataWithLength:MAX(length, format->count * 2)];
    uint16_t *values = key.mutableBytes;
    for (NSUInteger i = 0; i < format->count; i++) values[i] = attributes[@(format->attributes[i])].unsignedShortValue;
    return key;
}

static NSArray<NSArray<NSNumber *> *> *tokensOf(const struct sg_keytoken *tokens) {
    NSMutableArray *list = [NSMutableArray array];
    for (const struct sg_keytoken *t = tokens; t && (t->identifier || t->value); t++) [list addObject:@[@(t->identifier), @(t->value)]];
    return list;
}

static BOOL matches(NSDictionary<NSNumber *, NSNumber *> *attributes, NSArray<NSArray<NSNumber *> *> *facet) {
    if (!facet.count) return NO;
    for (NSArray<NSNumber *> *t in facet) {
        if (![attributes[t[0]] isEqualToNumber:t[1]]) return NO;
    }
    return YES;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "usage: icon-transplant FROM.car INTO.car\n");
            return 64;
        }
        NSString *fromPath = @(argv[1]), *intoPath = @(argv[2]);
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreUI.framework"] load];
        Class reader = NSClassFromString(@"CUICommonAssetStorage"), writer = NSClassFromString(@"CUIMutableCommonAssetStorage");
        if (!reader || !writer) {
            fprintf(stderr, "icon-transplant: CoreUI's asset storage classes are not there\n");
            return 2;
        }
        CUICommonAssetStorage *from = [[reader alloc] initWithPath:fromPath];
        CUIMutableCommonAssetStorage *into = [[writer alloc] initWithPath:intoPath forWriting:YES];
        if (!from || !into) {
            fprintf(stderr, "icon-transplant: a catalog did not open\n");
            return 2;
        }
        for (NSString *sel in @[@"keyFormat", @"allAssetKeys", @"assetForKey:", @"renditionKeyForName:hotSpot:", @"allRenditionNames"]) need(from, NSSelectorFromString(sel));
        for (NSString *sel in @[@"setAsset:forKey:", @"removeAssetForKey:", @"setRenditionKey:hotSpot:forName:", @"writeToDiskAndCompact:"]) need(into, NSSelectorFromString(sel));

        const struct sg_keyfmt *fromFormat = [from keyFormat], *intoFormat = [into keyFormat];
        NSMutableString *fmt = [NSMutableString string];
        for (uint32_t i = 0; i < fromFormat->count; i++) [fmt appendFormat:@" %u", fromFormat->attributes[i]];
        [fmt appendString:@" |"];
        for (uint32_t i = 0; i < intoFormat->count; i++) [fmt appendFormat:@" %u", intoFormat->attributes[i]];
        printf("key formats (from | into):%s\n", fmt.UTF8String);

        NSArray<NSString *> *fromNames = [from allRenditionNames], *intoNames = [into allRenditionNames];
        NSMutableArray<NSString *> *icon = [NSMutableArray array];
        for (NSString *name in fromNames) if ([name hasPrefix:@"AppIcon"]) [icon addObject:name];
        printf("names: %lu in from, %lu in into; icon names in from: %s\n", (unsigned long)fromNames.count, (unsigned long)intoNames.count,
               [icon componentsJoinedByString:@", "].UTF8String);
        NSMutableArray<NSString *> *intoIcon = [NSMutableArray array];
        for (NSString *name in intoNames) if ([name hasPrefix:@"AppIcon"]) [intoIcon addObject:name];
        printf("icon names in into: %s\n", [intoIcon componentsJoinedByString:@", "].UTF8String);
        if (!icon.count) {
            fprintf(stderr, "icon-transplant: FROM has no AppIcon\n");
            return 3;
        }

        // Values each facet attribute already takes in INTO, so a new name's facet takes free ones.
        NSMutableDictionary<NSNumber *, NSMutableSet<NSNumber *> *> *taken = [NSMutableDictionary dictionary];
        for (NSString *name in intoNames) {
            for (NSArray<NSNumber *> *t in tokensOf(facetFor(into, name))) {
                if (!taken[t[0]]) taken[t[0]] = [NSMutableSet set];
                [taken[t[0]] addObject:t[1]];
            }
        }

        NSArray<NSData *> *fromKeys = [from allAssetKeys], *intoKeys = [into allAssetKeys];
        NSUInteger removed = 0, copied = 0;
        for (NSString *name in icon) {
            NSArray *fromFacet = tokensOf(facetFor(from, name));
            NSArray *intoFacet = [intoNames containsObject:name] ? tokensOf(facetFor(into, name)) : nil;
            if (!fromFacet.count) {
                printf("  %s: no facet in from, left out\n", name.UTF8String);
                continue;
            }
            if (intoFacet.count) {
                for (NSData *key in intoKeys) {
                    if (!matches(attributesOf(key, intoFormat), intoFacet)) continue;
                    if ([into removeAssetForKey:key]) removed++;
                }
            } else {
                // The same attributes, each with a value INTO's names do not use.
                NSMutableArray *made = [NSMutableArray array];
                for (NSArray<NSNumber *> *t in fromFacet) {
                    uint16_t value = t[1].unsignedShortValue;
                    NSMutableSet *used = taken[t[0]] ?: [NSMutableSet set];
                    // Only the identifier (CoreUI's attribute 17) tells names apart; the element and the part stay.
                    if (t[0].unsignedShortValue == kIdentifier) while ([used containsObject:@(value)]) value++;
                    [used addObject:@(value)];
                    taken[t[0]] = used;
                    [made addObject:@[t[0], @(value)]];
                }
                struct sg_keytoken tokens[made.count + 1];
                for (NSUInteger i = 0; i < made.count; i++) tokens[i] = (struct sg_keytoken){[made[i][0] unsignedShortValue], [made[i][1] unsignedShortValue]};
                tokens[made.count] = (struct sg_keytoken){0, 0};
                if (![into setRenditionKey:tokens hotSpot:CGPointZero forName:name.UTF8String]) {
                    fprintf(stderr, "icon-transplant: %s could not be named in into\n", name.UTF8String);
                    return 4;
                }
                intoFacet = made;
            }
            NSUInteger mine = 0;
            for (NSData *key in fromKeys) {
                NSMutableDictionary *attributes = [attributesOf(key, fromFormat) mutableCopy];
                if (!matches(attributes, fromFacet)) continue;
                for (NSArray<NSNumber *> *t in intoFacet) attributes[t[0]] = t[1];
                for (NSNumber *attribute in attributes) {
                    BOOL known = NO;
                    for (uint32_t i = 0; i < intoFormat->count; i++) known |= intoFormat->attributes[i] == attribute.unsignedIntValue;
                    if (!known && [attributes[attribute] unsignedShortValue]) printf("  %s: attribute %u = %u has no place in into's keys\n",
                                                                                    name.UTF8String, attribute.unsignedIntValue, [attributes[attribute] unsignedShortValue]);
                }
                NSData *asset = [from assetForKey:key];
                if (asset && [into setAsset:asset forKey:keyFrom(attributes, intoFormat, 0)]) {
                    copied++;
                    mine++;
                }
            }
            printf("  %s: %lu renditions\n", name.UTF8String, (unsigned long)mine);
        }
        printf("removed %lu of into's icon renditions, copied %lu from from\n", (unsigned long)removed, (unsigned long)copied);
        if (!copied) {
            fprintf(stderr, "icon-transplant: nothing was copied\n");
            return 5;
        }
        if ([into respondsToSelector:@selector(setRenditionCount:)]) [into setRenditionCount:(unsigned int)[into allAssetKeys].count];
        if ([into respondsToSelector:@selector(useBitmapIndex)] && [into useBitmapIndex] && [into respondsToSelector:@selector(updateBitmapInfo)]) [into updateBitmapInfo];
        if (![into writeToDiskAndCompact:YES]) {
            fprintf(stderr, "icon-transplant: into could not be written\n");
            return 6;
        }
        printf("written\n");
    }
    return 0;
}
