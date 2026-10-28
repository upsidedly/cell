#import "EnergyControl.h"
#import <dlfcn.h>
#import <stdbool.h>

@implementation CellEnergyControl
- (NSDictionary<NSString *,id> *)readStateWithError:(NSError **)error {
    // Apple IOKitUser's IOPMLibPrivate.h establishes these C signatures.
    void *library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL);
    CFDictionaryRef (*copyPreferences)(void) = library ? dlsym(library, "IOPMCopyPMPreferences") : NULL;
    bool (*featureAvailable)(CFStringRef, CFStringRef) = library ? dlsym(library, "IOPMFeatureIsAvailable") : NULL;
    NSDictionary *preferences = copyPreferences ? CFBridgingRelease(copyPreferences()) : nil;
    if (!featureAvailable || ![preferences isKindOfClass:NSDictionary.class]) {
        if (error) *error = [NSError errorWithDomain:@"dev.matthew.cell.energy" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"Native power modes are unavailable. Open Battery Settings instead."}];
        if (library) dlclose(library);
        return nil;
    }
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"battery", @"charger"]) {
        NSString *source = [key isEqualToString:@"battery"] ? @"Battery Power" : @"AC Power";
        NSDictionary *settings = preferences[source];
        if (![settings isKindOfClass:NSDictionary.class]) continue;
        NSMutableArray *choices = [NSMutableArray array];
        if (featureAvailable(CFSTR("LowPowerMode"), (__bridge CFStringRef)source)) [choices addObject:@1];
        [choices addObject:@0];
        if (featureAvailable(CFSTR("HighPowerMode"), (__bridge CFStringRef)source)) [choices addObject:@2];
        result[key] = @{@"mode": settings[@"LowPowerMode"] ?: @0, @"availableModes": choices};
    }
    dlclose(library);
    return result;
}
@end
