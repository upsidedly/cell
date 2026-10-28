#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface CellEnergyControl : NSObject
- (nullable NSDictionary<NSString *, id> *)readStateWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(readState());
@end
NS_ASSUME_NONNULL_END
