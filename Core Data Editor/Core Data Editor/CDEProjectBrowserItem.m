#import "CDEProjectBrowserItem.h"

@interface CDEProjectBrowserItem ()

#pragma mark - Properties
@property (nonatomic, copy, readwrite) NSString *storePath;
@property (nonatomic, copy, readwrite) NSString *storeName;

@property (nonatomic, copy, readwrite) NSString *modelPath;
@property (nonatomic, copy, readwrite) NSString *modelName;

@property (nonatomic, copy, readwrite) NSString *device;
@property (nonatomic, copy, readwrite) NSString *tableNames;
@property (nonatomic, copy, readwrite) NSDate *fileModDate;

@property (nonatomic, copy, readwrite) NSString *projectName;

@property (nonatomic, strong, readwrite) NSImage *icon;

@end

@implementation CDEProjectBrowserItem : NSObject

#pragma mark - Creating
- (instancetype)initWithStorePath:(NSString *)storePath modelPath:(NSString *)modelPath device:(NSString *)device tableNames:(NSString *)tableNames {
    self = [super init];
    if(self) {
        self.storePath = storePath;
        self.modelPath = modelPath;
        self.device = device;
        self.tableNames = tableNames;
        [self createNamesAndIcon];
    }
    return self;
}

- (instancetype)init {
    return [self initWithStorePath:@"" modelPath:@"" device:@"" tableNames:@""];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"store:%@, model:%@, device:%@, tables:%@", self.storePath, self.modelPath, self.device, self.tableNames];
}

- (void)createNamesAndIcon {
    NSDate *fileModDate;
    NSError *error;
    NSURL *url=[NSURL fileURLWithPath:self.storePath];
    [url getResourceValue:&fileModDate forKey:NSURLContentModificationDateKey error:&error];
    
    //Also look for: .sqlite-wal (write-ahead log).  Use most recent, although the wal should be most recent if found.
    NSURL *walUrl=[NSURL fileURLWithPath:[NSString stringWithFormat:@"%@-wal",self.storePath]];
    NSDate *walDate;
    [walUrl getResourceValue:&walDate forKey:NSURLContentModificationDateKey error:&error];
    
    if ([fileModDate compare:walDate]==NSOrderedAscending) {
        fileModDate=walDate;
    }
    // use store modified date for sorting in project browser
    self.fileModDate = fileModDate;
    
    self.storeName=[NSString stringWithFormat:@"%@  (%@)",[self.storePath lastPathComponent], [self relativeDateStringForDate:fileModDate]];
    
    NSDate *modelModDate;
    NSURL *modelUrl=[NSURL fileURLWithPath:self.modelPath];
    [modelUrl getResourceValue:&modelModDate forKey:NSURLContentModificationDateKey error:&error];

    self.modelName=[NSString stringWithFormat:@"%@  (%@)",[self.modelPath lastPathComponent], [self relativeDateStringForDate:modelModDate]];
    
    self.projectName = [self.modelName stringByDeletingPathExtension];

    NSArray *components = [self.modelPath pathComponents];
    [components enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(NSString *component, NSUInteger idx, BOOL *stop) {
        if([[component pathExtension] isEqualToString:@"app"]) {
            self.projectName = [component stringByDeletingPathExtension];
            NSArray *appBundleComponents = [components subarrayWithRange:NSMakeRange(0, idx+1)];
            NSURL *appBundleURL = [NSURL fileURLWithPathComponents:appBundleComponents];
            self.icon = [self iconFromBundleAtURL:appBundleURL];
            *stop = YES;
        }
    }];

    if ([self.device length] > 0) {
        self.projectName = [self.projectName stringByAppendingFormat:@" %@", self.device];
    }
}

- (NSImage *)iconFromBundleAtURL:(NSURL *)bundleURL {
    NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
    NSDictionary *infoDictionary = bundle.infoDictionary;
    NSDictionary *icons = infoDictionary[@"CFBundleIcons"];
    NSDictionary *primaryIcon = icons[@"CFBundlePrimaryIcon"];
    NSArray *iconFiles = primaryIcon[@"CFBundleIconFiles"];
    NSString *iconName = iconFiles.lastObject;

    if(iconName == nil) {
        return [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericApplicationIcon)];
    }
    
    NSURL *iconURL = [bundleURL URLByAppendingPathComponent:iconName isDirectory:NO];
    
    NSFileManager *fileManager = [NSFileManager new];
    
    if(![fileManager fileExistsAtPath:iconURL.path]) {
        return [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericApplicationIcon)];
    }
    
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:iconURL];
    return image;
}

typedef NS_ENUM(NSInteger, EDateType) {
    DateTypeToday = 0,
    DateTypeYesterday,
    DateTypeLastWeek,
    DateTypeThisMonth,
};

// get relative date
// - today: "3:45 PM"
// - this week: "Tues, 04/01 3:45 PM"
// - older: "04/01/15 3:45 PM"
- (NSString *)relativeDateStringForDate:(NSDate *)date {
    NSDateFormatter *dateFormatter = [NSDateFormatter new];

    NSDate *midnight = [self dateByType:DateTypeToday];
    if ([date compare:midnight] == NSOrderedDescending) {
        [dateFormatter setDateFormat:@"h:mm a"];
    }
    else {
        NSDate *lastWeek = [self dateByType:DateTypeLastWeek];
        if ([date compare:lastWeek] == NSOrderedDescending) {
            [dateFormatter setDateFormat:@"EEE, MM/dd h:mm a"];
        }
        else {
            // older than last week
            [dateFormatter setDateFormat:@"MM/dd/YY h:mm a"];
        }
    }

    return [dateFormatter stringFromDate:date];
}

// get a date object set to midnight for use in displaying conversations in sections (or other date groupings)
// DateTypeToday: today's date at midnight
// DateTypeYesterday: get yesterday's date at midnight
- (NSDate *)dateByType:(EDateType)dateType {
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    [cal setTimeZone:[NSTimeZone systemTimeZone]];
    NSDateComponents *comp = [cal components:( NSYearCalendarUnit| NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:[NSDate date]];

    // set values to '0' (midnight today)
    [comp setSecond:0];
    [comp setMinute:0];
    [comp setHour:0];

    if (dateType == DateTypeYesterday) {
        [comp setHour:comp.hour - 24];
    }
    else if (dateType == DateTypeLastWeek) {
        // using -6 so we don't show the same day of the week as today
        [comp setDay:comp.day - 6];
    }
    else if (dateType == DateTypeThisMonth) {
        // set day to first of the month
        [comp setDay:1];
    }

    return [cal dateFromComponents:comp];
}

@end