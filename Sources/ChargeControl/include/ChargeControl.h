#import <Foundation/Foundation.h>
#import "NativeBatteryImage.h"
#import "EnergyControl.h"

NS_ASSUME_NONNULL_BEGIN
@interface CellChargeControl : NSObject
- (nullable NSDictionary<NSString *, id> *)readStateWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(readState());
- (BOOL)setLimit:(NSInteger)limit error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setLimit(_:));
@end
NS_ASSUME_NONNULL_END
