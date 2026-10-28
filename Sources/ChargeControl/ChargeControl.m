#import "ChargeControl.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSError *JError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"dev.matthew.cell.charging" code:code
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}

@implementation CellChargeControl {
    id _client;
    NSError *_initialError;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    if (!dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW | RTLD_LOCAL)) {
        _initialError = JError(1, @"Native charge control is unavailable on this macOS version.");
        return self;
    }
    Class type = objc_getClass("PowerUISmartChargeClient");
    // Validate the observed ABI before sending messages to an undocumented framework.
    NSDictionary *signatures = @{
        @"initWithClientName:":@"@@:@", @"isMCLSupported":@"B@:",
        @"getMCLLimitWithError:":@"C@:^@", @"availableChargeLimitsWithError:":@"@@:^@",
        @"setMCLLimit:error:":@"B@:C^@"
    };
    for (NSString *name in signatures) {
        Method method = class_getInstanceMethod(type, NSSelectorFromString(name));
        if (!method) { _initialError = JError(2, @"Native charge control changed. Open Battery settings instead."); return self; }
        NSMutableString *actual = [NSMutableString string];
        char *returnType = method_copyReturnType(method);
        if (returnType) { [actual appendString:@(returnType)]; free(returnType); }
        for (unsigned int i=0; i<method_getNumberOfArguments(method); i++) {
            char *argument = method_copyArgumentType(method,i);
            if (argument) { [actual appendString:@(argument)]; free(argument); }
        }
        if (![actual isEqualToString:signatures[name]]) {
            _initialError = JError(2, @"Native charge control changed. Open Battery settings instead."); return self;
        }
    }
    _client = ((id(*)(id, SEL, id))objc_msgSend)([type alloc], NSSelectorFromString(@"initWithClientName:"), @"dev.matthew.cell");
    if (!_client) _initialError = JError(3, @"Could not connect to native charge control. Try again.");
    return self;
}

- (NSDictionary<NSString *,id> *)readStateWithError:(NSError **)error {
    if (!_client) { if(error) *error=_initialError; return nil; }
    if (!((BOOL(*)(id,SEL))objc_msgSend)(_client, NSSelectorFromString(@"isMCLSupported"))) {
        if(error) *error=JError(4, @"Charge limits need an Apple silicon Mac and macOS 26.4 or later.");
        return nil;
    }
    NSError *failure=nil;
    NSArray *limits=((id(*)(id,SEL,NSError**))objc_msgSend)(_client, NSSelectorFromString(@"availableChargeLimitsWithError:"), &failure);
    if(failure || ![limits isKindOfClass:NSArray.class] || limits.count==0) {
        if(error) *error=failure ?: JError(5,@"The available charge limits could not be read."); return nil;
    }
    NSMutableArray *validated=[NSMutableArray array];
    for(id value in limits) {
        if(![value isKindOfClass:NSNumber.class] || [value integerValue]<80 || [value integerValue]>100
           || [value doubleValue] != [value integerValue]) {
            if(error) *error=JError(6,@"macOS returned an unsupported charge limit."); return nil;
        }
        if(![validated containsObject:value]) [validated addObject:value];
    }
    unsigned char limit=((unsigned char(*)(id,SEL,NSError**))objc_msgSend)(_client,NSSelectorFromString(@"getMCLLimitWithError:"),&failure);
    if(failure || ![validated containsObject:@(limit)]) {
        if(error) *error=failure ?: JError(7,@"The current charge limit could not be read."); return nil;
    }
    return @{@"limit":@(limit), @"availableLimits":[validated sortedArrayUsingSelector:@selector(compare:)]};
}

- (BOOL)setLimit:(NSInteger)limit error:(NSError **)error {
    NSDictionary *state=[self readStateWithError:error];
    if(!state) return NO;
    if(![state[@"availableLimits"] containsObject:@(limit)]) {
        if(error) *error=JError(8,@"Choose one of the charge limits supported by macOS."); return NO;
    }
    NSError *failure=nil;
    BOOL success=((BOOL(*)(id,SEL,unsigned char,NSError**))objc_msgSend)(_client,NSSelectorFromString(@"setMCLLimit:error:"),(unsigned char)limit,&failure);
    if(!success || failure) {
        if(error) *error=failure ?: JError(9,@"The charge limit did not change. Try again."); return NO;
    }
    NSDictionary *confirmed=[self readStateWithError:error];
    if(!confirmed) return NO;
    if([confirmed[@"limit"] integerValue] != limit) {
        if(error) *error=JError(10,@"macOS has not confirmed the new limit. Refresh to check it."); return NO;
    }
    return YES;
}
@end
