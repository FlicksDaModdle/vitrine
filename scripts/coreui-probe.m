// Lists the methods and their type encodings of CoreUI's asset storage classes, for icon-transplant.m. A development aid.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
int main(void) {
    @autoreleasepool {
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreUI.framework"] load];
        NSString *ctd = @"/Applications/Xcode.app/Contents/SharedFrameworks/CoreThemeDefinition.framework";
        if (![[NSBundle bundleWithPath:ctd] load]) printf("CoreThemeDefinition did not load\n");
        for (NSString *name in @[@"CUICommonAssetStorage", @"CUIMutableCommonAssetStorage", @"CUIStructuredThemeStore", @"CUIMutableStructuredThemeStore", @"CoreThemeDocument", @"TDDistiller"]) {
            Class c = NSClassFromString(name);
            if (!c) { printf("%s missing\n", name.UTF8String); continue; }
            unsigned int count = 0;
            Method *methods = class_copyMethodList(c, &count);
            for (unsigned int i = 0; i < count; i++)
                printf("%s -%s %s\n", name.UTF8String, sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i]));
            free(methods);
        }
    }
    return 0;
}
