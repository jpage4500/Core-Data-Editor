#import "CDEProjectBrowserItemTableCellView.h"

@interface CDEProjectBrowserItemTableCellView ()
@property (nonatomic, weak) IBOutlet NSTextField *storeLabel;
@property (nonatomic, weak) IBOutlet NSTextField *modelLabel;
@property (nonatomic, weak) IBOutlet NSTextField *storeValueLabel;
@property (nonatomic, weak) IBOutlet NSTextField *modelValueLabel;
@property (nonatomic, weak) IBOutlet NSTextField *tablesLabel;
@property (nonatomic, weak) IBOutlet NSTextField *tablesValueLabel;

@property CGFloat lastTableWidth;
@end

@implementation CDEProjectBrowserItemTableCellView

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    [super setBackgroundStyle:backgroundStyle];
    [self adjustTextColorOfTextField:self.storeLabel];
    [self adjustTextColorOfTextField:self.modelLabel];
    [self adjustTextColorOfTextField:self.storeValueLabel];
    [self adjustTextColorOfTextField:self.modelValueLabel];
    [self adjustTextColorOfTextField:self.tablesLabel];
    [self adjustTextColorOfTextField:self.tablesValueLabel];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];

    // show tooltip for tables if truncated
    CGFloat labelW = CGRectGetWidth(self.tablesValueLabel.frame);
    if (self.lastTableWidth != labelW) {
        NSSize textBounds = [self.tablesValueLabel sizeThatFits:NSMakeSize(labelW + 10, 30)];
        if (labelW < textBounds.width) {
            [self setToolTip:[self.tablesValueLabel stringValue]];
        }
        else {
            [self setToolTip:nil];
        }
        self.lastTableWidth = labelW;
    }
}

- (void)adjustTextColorOfTextField:(NSTextField *)textField {
    NSBackgroundStyle style = self.backgroundStyle;
    //NSTableView *tableView = self.enclosingScrollView.documentView;
    //BOOL tableViewIsFirstResponder = [tableView isEqual:[self.window firstResponder]];
    
    NSColor *color = nil;
    if(style == NSBackgroundStyleLight) {
        color = [NSColor darkGrayColor];
        //color = tableViewIsFirstResponder ? [NSColor lightGrayColor] : [NSColor darkGrayColor];
    } else {
        color = [NSColor whiteColor];
    }
    textField.textColor = color;
}

@end
