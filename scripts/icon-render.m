// Draws a compiled asset catalog's AppIcon at 128 pt as a PNG, so two catalogs' icons can be compared. A development aid.
//   icon-render Assets.car out.png
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

@interface CUICatalog : NSObject
- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error;
- (id)imageWithName:(NSString *)name scaleFactor:(double)scale;
- (NSArray *)allImageNames;
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) return 64;
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreUI.framework"] load];
        CUICatalog *catalog = [[NSClassFromString(@"CUICatalog") alloc] initWithURL:[NSURL fileURLWithPath:@(argv[1])] error:nil];
        id named = [catalog imageWithName:@"AppIcon" scaleFactor:3];
        CGImageRef image = named && [named respondsToSelector:@selector(image)] ? (__bridge CGImageRef)[named performSelector:@selector(image)] : NULL;
        if (!image) { fprintf(stderr, "no AppIcon image (%s)\n", [[named description] UTF8String]); return 2; }
        printf("AppIcon %zux%zu\n", CGImageGetWidth(image), CGImageGetHeight(image));
        size_t side = 128;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, side, side, 8, 0, space, kCGImageAlphaPremultipliedLast);
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        CGContextDrawImage(context, CGRectMake(0, 0, side, side), image);
        CGImageRef small = CGBitmapContextCreateImage(context);
        CGImageDestinationRef out = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:@(argv[2])], CFSTR("public.png"), 1, NULL);
        CGImageDestinationAddImage(out, small, NULL);
        CGImageDestinationFinalize(out);
    }
    return 0;
}
