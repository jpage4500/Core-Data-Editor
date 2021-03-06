#import "CDEProjectBrowserWindowController.h"
#import "CDEProjectBrowserItem.h"
#import "CDEDocument.h"
#import "CDEConfiguration.h"
#import "CDEApplicationDelegate.h"
#import "NSURL+CDEAdditions.h"
#import "NSDirectoryEnumerator+ProjectBrowser.h"

#define kCDEFileModificationDateKey @"modificationDate"
#define kCDEStorePathKey @"storePath"
#define kCDEModelPathKey @"modelPath"
#define kCDETableNamesKey @"numTables"

typedef void(^ProjectBrowserReloadCompletionHandler)(NSArray *projectBrowserItems /* CDEProjectBrowserItem */);

@interface CDEProjectBrowserWindowController ()

#pragma mark - Properties
@property (copy) NSURL *projectDirectoryURL;

@property (strong) IBOutlet NSProgressIndicator *reloadProgressIndicator;
@property (strong) IBOutlet NSButton *reloadButton;

@property (strong) IBOutlet NSArrayController *items;
@property (strong) IBOutlet NSTableView *tableView;

@end

@implementation CDEProjectBrowserWindowController

#pragma mark - Working with the project browser
- (void)showWithProjectDirectoryURL:(NSURL *)projectDirectoryURL {
    self.projectDirectoryURL = projectDirectoryURL;
    [self showWindow:self];
    [self updateUI];
    [self reloadProjectBrowser:self];
}

- (void)updateProjectDirectoryURL:(NSURL *)projectDirectoryURL {
    self.projectDirectoryURL = projectDirectoryURL;
    [self reloadProjectBrowser:self];
}

- (void)updateUI {
    [self.reloadButton setEnabled:(self.projectDirectoryURL != nil)];
}

#pragma mark - Actions
- (IBAction)createProject:(id)sender {
    NSInteger row = [self.tableView rowForView:sender];
    [self createProjectByRow:row];
}

- (IBAction)onCellClick:(id)sender {
    NSInteger row = [self.tableView selectedRow];
    [self createProjectByRow:row];
}

- (void)createProjectByRow:(NSInteger)row {
    if (row < 0 || row >= [self.items.arrangedObjects count]) {
        NSLog(@"bad row: %d", (int)row);
        return;
    }
    CDEProjectBrowserItem *item = [self.items.arrangedObjects objectAtIndex:(NSUInteger)row];
    if(item == nil) {
        return;
    }
    NSLog(@"opening project: %@", item.projectName);
    CDEDocument *document = [[NSDocumentController sharedDocumentController] openUntitledDocumentAndDisplay:NO error:NULL];
    CDEConfiguration *c = [document createConfiguration];
    NSError *error = nil;
    NSURL *storeURL = [NSURL fileURLWithPath:item.storePath];
    NSURL *modelURL = [NSURL fileURLWithPath:item.modelPath];
    
    BOOL set = [c setBookmarkDataWithApplicationBundleURL:nil storeURL:storeURL modelURL:modelURL error:&error];
    if(!set) {
        NSLog(@"error: %@", error);
    }
    error = nil;
    BOOL setup = [document setupAndStartAccessingConfigurationRelatedURLsAndGetError:&error];
    if(!setup) {
        NSLog(@"error: %@", error);
    }
    [document makeWindowControllers];
    [document showWindows];
}

- (void)prepareUIForReload {
    [self.items setContent:[@[] mutableCopy]];
    [self.reloadButton setEnabled:NO];
    [self.reloadProgressIndicator startAnimation:self];
}

- (void)performReloadWithCompletionHandler:(ProjectBrowserReloadCompletionHandler)completionHandler {
    NSParameterAssert(completionHandler);
    NSAssert(self.projectDirectoryURL != nil, @"");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *allItems = [NSMutableArray new];
        // iterate over all simulator directories
        NSURL *devicesUrl = [self.projectDirectoryURL URLByAppendingPathComponent:@"Devices" isDirectory:YES];
        NSDirectoryEnumerator *devicesEnumerator = [self newDirectoryEnumerator:devicesUrl includeSubdirs:NO];
        for (NSURL *deviceUrl in devicesEnumerator) {
            // look for device.plist in this directory to get the simulator device and OS version
            NSURL *infoUrl = [deviceUrl URLByAppendingPathComponent:@"device.plist" isDirectory:NO];
            NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfFile:infoUrl.path];
            if (infoDict == nil) {
                continue;
            }
            NSString *deviceName = infoDict[@"name"];
            NSString *osName = infoDict[@"runtime"];
            if ([deviceName length] == 0 || [osName length] == 0) {
                continue;
            }
            // parse out last part (ie: com.apple.CoreSimulator.SimRuntime.iOS-8-1)
            NSArray *osArray = [osName componentsSeparatedByString: @"."];
            osName = osArray.lastObject;

            // deviceName = "iPhone 6 (iOS-8-3)"
            deviceName = [deviceName stringByAppendingFormat:@" (%@)", osName];

            // look for databases for this simulator
            NSDirectoryEnumerator *enumerator = [self newDirectoryEnumerator:deviceUrl includeSubdirs:YES];
            NSDictionary *metadataByStorePath;
            NSDictionary *modelByModelPath;
            [enumerator getMetadataByStorePath:&metadataByStorePath modelByModelPath:&modelByModelPath];
            NSArray *items = [self compatibleProjectBrowserItemsWithMetadataByStorePath:metadataByStorePath modelByModelPath:modelByModelPath device:deviceName];

            [allItems addObjectsFromArray:items];
        }

        NSLog(@"found %d projects", (int)[allItems count]);

        // sort all projects by modified date (descending)
        NSSortDescriptor* sortByDate = [NSSortDescriptor sortDescriptorWithKey:@"fileModDate" ascending:NO];
        [allItems sortUsingDescriptors:@[sortByDate]];

        double delayInSeconds = 0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            completionHandler(allItems);
        });
    });
}

- (NSArray *)compatibleProjectBrowserItemsWithMetadataByStorePath:(NSDictionary *)metadataByStorePath modelByModelPath:(NSDictionary*)modelByModelPath device:(NSString *)device {
    NSMutableArray *items = [NSMutableArray new];
    NSMutableArray *itemsWithDates= [NSMutableArray new]; // Each element is dictionary with {modificationDate:, storePath:, modelPath}
    
    // Find compatible combinations
    [modelByModelPath enumerateKeysAndObjectsUsingBlock:^(NSString *modelPath, NSManagedObjectModel *model, BOOL *stop) {
        [metadataByStorePath enumerateKeysAndObjectsUsingBlock:^(NSString *storePath, NSDictionary *metadata, BOOL *stop2) {
            BOOL isCompatible = [model isConfiguration:nil compatibleWithStoreMetadata:metadata];
            if(isCompatible) {
                //NSLog(@"modelPath:%@, storePath:%@", modelPath, storePath);
                //NSLog(@"metadata:%@", metadata);
                NSDate *storeModDate;
                NSURL *storeURL=[NSURL fileURLWithPath:storePath];
                NSError *error;
                [storeURL getResourceValue:&storeModDate forKey:NSURLContentModificationDateKey error:&error];
                
                //Also look for: .sqlite-wal (write-ahead log).  Use most recent, although the wal should be most recent if found.
                NSString *walPath=[NSString stringWithFormat:@"%@-wal",storeURL.absoluteString];
                NSURL *walUrl=[NSURL URLWithString:walPath];
                NSDate *walModDate;
                [walUrl getResourceValue:&walModDate forKey:NSURLContentModificationDateKey error:&error];
                
                if ([storeModDate compare:walModDate]==NSOrderedAscending) {
                    storeModDate=walModDate;
                }
                
                NSDate *modelModDate;
                NSURL *modelURL=[NSURL fileURLWithPath:modelPath];
                [modelURL getResourceValue:&modelModDate forKey:NSURLContentModificationDateKey error:&error];
                
                //NSSortDescriptor doesn't do NSDate, so use a string. Both dates concatenated for nesting.
                NSString *fileModDateString=[NSString stringWithFormat:@"%@ - %@",storeModDate,modelModDate];

                // try to determine # of tables defined in store
                NSString *tableNames = @"";
                NSDictionary *tableVersionDict = metadata[@"NSStoreModelVersionHashes"];
                if ([tableVersionDict count] > 0) {
                    tableNames = [[tableVersionDict allKeys] componentsJoinedByString:@", "];
                }
                
                NSDictionary *itemWithDate=@{kCDEFileModificationDateKey: fileModDateString,
                    kCDEStorePathKey: storePath,
                    kCDEModelPathKey: modelPath,
                    kCDETableNamesKey: tableNames};
                
                [itemsWithDates addObject:itemWithDate];
            }
        }];
    }];
    //Now sort and display
    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:kCDEFileModificationDateKey ascending:NO];
    NSArray *itemsSorted= [itemsWithDates sortedArrayUsingDescriptors:@[descriptor]];
    
    for (NSDictionary *itemWithDate in itemsSorted) {
        NSString *storePath=itemWithDate[kCDEStorePathKey];
        NSString *modelPath=itemWithDate[kCDEModelPathKey];
        NSString *tableNames=itemWithDate[kCDETableNamesKey];
        CDEProjectBrowserItem *item = [[CDEProjectBrowserItem alloc] initWithStorePath:storePath modelPath:modelPath device:device tableNames:tableNames];
        [items addObject:item];
    }

    return items;
}

- (NSDirectoryEnumerator *)newDirectoryEnumerator:(NSURL *)URL includeSubdirs:(BOOL)includeSubdirs {
    NSFileManager *fileManager = [NSFileManager defaultManager]; // there is no reason not to use the defaultManager
    NSDirectoryEnumerationOptions options = includeSubdirs ? NSDirectoryEnumerationSkipsHiddenFiles : NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsSubdirectoryDescendants;
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:URL includingPropertiesForKeys:nil options:options errorHandler:^BOOL(NSURL *url, NSError *error) {
        NSLog(@"error while enumerating contents of simulator directory: %@", error);
        return YES;
    }];
    return enumerator;
}

- (IBAction)reloadProjectBrowser:(id)sender {
    NSURL *simulatorURL = self.projectDirectoryURL;
    if(simulatorURL == nil) {
        NSLog(@"simulator url is nil");
        [self displayDelayedNoSimulatorDirectoryAlert];
        return;
    }
    
    [self prepareUIForReload];
    
    [self performReloadWithCompletionHandler:^(NSArray *projectBrowserItems) {
        [self.items setContent:projectBrowserItems];
        [self.reloadButton setEnabled:YES];
        [self.reloadProgressIndicator stopAnimation:self];
    }];
}

#pragma mark - Helper
- (void)displayDelayedNoSimulatorDirectoryAlert {
    double delayInSeconds = 2.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
      NSAlert *alert = [NSAlert new];
      alert.messageText = @"iPhone Simulator Directory not set";
      alert.informativeText = @"The Project Browser has to know where the iPhone Simulator directory is. Please go to the preferences and specify your iPhone Simulator directory in the Integration tab.";
      [alert addButtonWithTitle:@"Open Preferences…"];
      [alert addButtonWithTitle:@"Close Project Browser"];
      alert.alertStyle = NSInformationalAlertStyle;
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
          if(returnCode ==  NSAlertFirstButtonReturn) {
            // show prefs.
            [(CDEApplicationDelegate *)[NSApp delegate] showPreferences:self];
          }
          [self closeWindowSoon];
        }];
    });
}

- (void)closeWindowSoon {
    double delayInSeconds = 2.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self.window performClose:self];
    });
}

#pragma mark - NSWindowController
- (instancetype)init {
    self = [super initWithWindowNibName:@"CDEProjectBrowserWindowController" owner:self];
    if(self) {
        
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
}

@end
