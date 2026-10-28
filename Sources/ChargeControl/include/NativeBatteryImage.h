#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface CellBatteryImage : NSObject
+ (nullable NSImage *)imageForLevel:(double)level
                          charging:(BOOL)charging
                         pluggedIn:(BOOL)pluggedIn
                      lowPowerMode:(BOOL)lowPowerMode
                            useRed:(BOOL)useRed
    NS_SWIFT_NAME(image(level:charging:pluggedIn:lowPowerMode:useRed:));
@end
NS_ASSUME_NONNULL_END
