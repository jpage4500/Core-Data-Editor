#import <Foundation/Foundation.h>

@interface CDEProjectBrowserItem : NSObject

#pragma mark - Creating
- (instancetype)initWithStorePath:(NSString *)storePath modelPath:(NSString *)modelPath device:(NSString *)device tableNames:(NSString *)tableNames;

#pragma mark - Properties
@property (nonatomic, readonly, copy) NSString *storePath;
@property (nonatomic, readonly, copy) NSString *modelPath;
@property (nonatomic, readonly, copy) NSString *device;
@property (nonatomic, readonly, copy) NSString *tableNames;
@property (nonatomic, readonly, copy) NSString *projectName;

@property (nonatomic, readonly, copy) NSDate *fileModDate;

@end