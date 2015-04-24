#import <Foundation/Foundation.h>

@interface CDEProjectBrowserItem : NSObject

#pragma mark - Creating
- (instancetype)initWithStorePath:(NSString *)storePath modelPath:(NSString *)modelPath device:(NSString *)device;

#pragma mark - Properties


@property (nonatomic, readonly, copy) NSString *storePath;
@property (nonatomic, readonly, copy) NSString *modelPath;
@property (nonatomic, readonly, copy) NSString *device;

@end