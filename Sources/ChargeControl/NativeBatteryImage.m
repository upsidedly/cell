#import "NativeBatteryImage.h"
#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL CellMethodMatches(Method method, NSString *expected) {
    if (!method) return NO;
    NSMutableString *signature = [NSMutableString string];
    char *result = method_copyReturnType(method);
    if (result) { [signature appendString:@(result)]; free(result); }
    for (unsigned int index = 0; index < method_getNumberOfArguments(method); index++) {
        char *argument = method_copyArgumentType(method, index);
        if (argument) { [signature appendString:@(argument)]; free(argument); }
    }
    return [signature isEqualToString:expected];
}

@implementation CellBatteryImage
+ (NSImage *)imageForLevel:(double)level charging:(BOOL)charging pluggedIn:(BOOL)pluggedIn
             lowPowerMode:(BOOL)lowPowerMode useRed:(BOOL)useRed {
    static id cache;
    static SEL render;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/PrivateFrameworks/BatteryUIKit.framework/BatteryUIKit", RTLD_NOW | RTLD_LOCAL)) return;
        Class type = objc_getClass("BUIImage");
        SEL shared = NSSelectorFromString(@"sharedBUIImageCache");
        render = NSSelectorFromString(@"_modernBatteryImageForLevel:charging:pluggedIn:noBattery:needsReplacement:lowPowerMode:showPercentage:useRed:");
        if (!CellMethodMatches(class_getClassMethod(type, shared), @"@@:")) return;
        id candidate = ((id(*)(id, SEL))objc_msgSend)(type, shared);
        if (!CellMethodMatches(class_getInstanceMethod([candidate class], render), @"@@:dBBBBBBB")) return;
        cache = candidate;
    });
    if (!cache || !isfinite(level)) return nil;
    id result = ((id(*)(id, SEL, double, BOOL, BOOL, BOOL, BOOL, BOOL, BOOL, BOOL))objc_msgSend)(
        cache, render, fmin(1.0, fmax(0.0, level)), charging, pluggedIn, NO, NO, lowPowerMode, NO, useRed);
    if (![result isKindOfClass:NSImage.class]) return nil;
    // Copy before the status button owns the image; never mutate Apple's cache.
#if __has_feature(objc_arc)
    return [result copy];
#else
    return [[result copy] autorelease];
#endif
}
@end
