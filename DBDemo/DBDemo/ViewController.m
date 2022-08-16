//
//  ViewController.m
//  DBDemo
//
//  Created by Cruz on 2022/8/16.
//

#import "ViewController.h"
#import <FMDB/FMDB.h>

#define kDBPath [NSString stringWithFormat:@"%@test.db", NSTemporaryDirectory()]

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UITextField *textField;
@property (weak, nonatomic) IBOutlet UITextView *textView;

@property (nonatomic, strong) FMDatabaseQueue *queue;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:kDBPath]) {
        [fileManager createFileAtPath:kDBPath
                             contents:nil
                           attributes:nil];
    }
    
    _queue = [FMDatabaseQueue databaseQueueWithPath:kDBPath];
    
    [_queue inDatabase:^(FMDatabase * _Nonnull db) {
        BOOL isExisted = [db tableExists:@"t1"];
        
        if (!isExisted) {
            NSString *fts = @"CREATE VIRTUAL TABLE t1 USING fts5(x, tokenize = 'simple')";
            BOOL result = [db executeUpdate:fts];
            
            if (result) {
                [self.textView insertText:@"虚表t1创建成功!\n"];
            } else {
                [self.textView insertText:@"虚表t1创建失败!\n"];
            }

            result = [db executeUpdate:@"insert into 't1' values(?)"
                  withArgumentsInArray:@[@"周杰伦 Jay Chou:最美的不是下雨天，是曾与你躲过雨的屋檐"]];
            
            if (result) {
                NSString *text = [NSString stringWithFormat:@"%@%@", self.textView.text, @"插入数据：\n周杰伦 Jay Chou:最美的不是下雨天，是曾与你躲过雨的屋檐\n"];
                self.textView.text = text;
            } else {
                NSString *text = [NSString stringWithFormat:@"%@%@", self.textView.text, @"插入数据失败!\n"];
                self.textView.text = text;
            }
        }
    }];
}

- (IBAction)insert:(id)sender {
    [_queue inDatabase:^(FMDatabase * _Nonnull db) {
        NSString *text = self.textField.text;
        text = text ? text : @"";
        BOOL result = [db executeUpdate:@"insert into 't1' values(?)" withArgumentsInArray:@[text]];
        
        if (result) {
            NSString *textS = [NSString stringWithFormat:@"%@%@", self.textView.text,
                              [NSString stringWithFormat:@"插入数据：\n%@\n", text]];
            self.textView.text = textS;
        } else {
            NSString *textS = [NSString stringWithFormat:@"%@%@", self.textView.text,
                              @"插入数据失败!\n"];
            self.textView.text = textS;
        }
    }];
}

- (IBAction)query:(id)sender {
    [_queue inDatabase:^(FMDatabase * _Nonnull db) {
        NSString *text = self.textField.text;
        text = text ? text : @"";
        NSString *sql = [NSString stringWithFormat:@"select * from t1 where x match simple_query('%@')", text];
        FMResultSet *result = [db executeQuery:sql];
        
        if (result) {
            while ([result next]) {
                NSString *r = [result objectForColumn:@"x"];
                if (r) {
                    NSString *textS = [NSString stringWithFormat:@"%@%@", self.textView.text,
                                       [NSString stringWithFormat:@"查询%@结果:\n%@\n", text,r]];
                    self.textView.text = textS;
                }
            }
        } else {
            NSString *textS = [NSString stringWithFormat:@"%@%@", self.textView.text,
                               [NSString stringWithFormat:@"查询%@结果:\n%@\n", text,@"无结果"]];
            self.textView.text = textS;
        }
    }];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.textField resignFirstResponder];
}

@end
