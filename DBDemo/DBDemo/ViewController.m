//
//  ViewController.m
//  DBDemo
//
//  Created by Cruz on 2022/8/16.
//

#import "ViewController.h"
#import <FMDB/FMDB.h>

#define kDocPath            [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject]
#define kDBPath             [NSString stringWithFormat:@"%@test.db", NSTemporaryDirectory()]
#define kJiebaPath          [NSString stringWithFormat:@"%@/%@", kDocPath, @"dict"]
#define kTableName          @"message"
#define kVirtualTableName   @"virtual_message"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UITextField *textField;
@property (weak, nonatomic) IBOutlet UITextView *textView;
@property (weak, nonatomic) IBOutlet UISwitch *highlightSwitch;

@property (nonatomic, strong) FMDatabaseQueue *queue;
@property (weak, nonatomic) IBOutlet UISwitch *jiebaSwitch;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [_highlightSwitch setOn:NO];
    [_jiebaSwitch setOn:NO];
    
    // 将jieba dict目录内容写入沙盒
    [self writeJiebaDataToSandbox];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:kDBPath]) {
        [fileManager createFileAtPath:kDBPath
                             contents:nil
                           attributes:nil];
    }
        
    _queue = [FMDatabaseQueue databaseQueueWithPath:kDBPath];
    
    [_queue inDatabase:^(FMDatabase * _Nonnull db) {
        BOOL isMsgTabelExist = [db tableExists:@"message"];
        
        BOOL result = NO;
        
        if (!isMsgTabelExist) {
            NSString *sql = @"create table message (                    \
                              _id INTEGER PRIMARY KEY AUTOINCREMENT,    \
                              body TEXT);";
                        
            result = [db executeUpdate:sql];
            
            if (!result) {
                [self insertLog:@"主表创建失败!!!"];
                return;
            }
            
            [self insertLog:@"主表创建成功!"];
        }
        
        BOOL isVirtualTableExist = [db tableExists:@"virtual_message"];
        
        if (!isVirtualTableExist) {
            NSString *sql = @"create virtual table virtual_message using fts5(       \
                              body,                                                  \
                              content='message',                                     \
                              content_rowid='_id',                                   \
                              tokenize = 'simple')";
            BOOL result = [db executeUpdate:sql];
            
            if (result) {
                [self insertLog:@"虚拟表创建成功!"];
            } else {
                [self insertLog:@"虚拟表创建失败!!!"];
                
                return;
            }
        }
        
        FMResultSet *resultSet = [db executeQuery:@"SELECT name FROM sqlite_master WHERE type = 'trigger';"];
        
        if (![resultSet next]) {
            NSString *sql = @"CREATE TRIGGER message_ai AFTER INSERT ON message BEGIN \
                                INSERT INTO virtual_message(rowid, body) VALUES (new._id, new.body); \
                              END; \
                              CREATE TRIGGER message_ad AFTER DELETE ON message BEGIN \
                                INSERT INTO virtual_message(virtual_message, rowid, body) VALUES('delete', old._id, old.body); \
                              END;\
                              CREATE TRIGGER message_au AFTER UPDATE ON message BEGIN \
                                INSERT INTO virtual_message(virtual_message, rowid, body) VALUES('delete', old._id, old.body); \
                                INSERT INTO virtual_message(rowid, body) VALUES (new._id, new.body); \
                              END;";
            
            result = [db executeUpdate:sql];
            
            if (!result) {
                [self insertLog:@"TRIGGER 创建失败！!!"];
                return;
            } else {
                [self insertLog:@"TRIGGER 创建成功！"];
            }
        }
        
        NSString *jiebaPath = kJiebaPath;
        NSString *sql = [NSString stringWithFormat:@"select jieba_dict('%@')", jiebaPath];
        result = [db executeStatements:sql];
        if (result) {
            
        }
    }];
}

- (IBAction)insert:(id)sender {
    [self.textField resignFirstResponder];
    
    if (self.textField.text.length == 0) {
        return;
    }
    
    [_queue inDatabase:^(FMDatabase * _Nonnull db) {
        NSString *text = self.textField.text;
        BOOL result = [db executeUpdate:@"insert into message (body) values(?)" withArgumentsInArray:@[text]];
        
        if (result) {
            [self insertLog:@"插入成功！"];
        } else {
            [self insertLog:@"插入失败!!!"];
        }
    }];
}

- (IBAction)query:(id)sender {
    [self.textField resignFirstResponder];
    
    if (self.textField.text.length == 0) {
        return;
    }
    [_queue inDatabase:^(FMDatabase * _Nonnull db) {
        NSString *text = self.textField.text;
        
        NSMutableString *sql = [NSMutableString string];
        
        if (self.highlightSwitch.isOn) {
            [sql appendString:@"select simple_highlight(virtual_message, 0, '[', ']') as body from virtual_message where body match "];
        } else {
            [sql appendString:@"select body from virtual_message where body match "];
        }
        
        if (self.jiebaSwitch.isOn) {
            [sql appendFormat:@"jieba_query('%@');", text];
        } else {
            [sql appendFormat:@"simple_query('%@');", text];
        }
                
        FMResultSet *result = [db executeQuery:sql];
        
        NSMutableString *resultString = [NSMutableString string];
        
        NSUInteger count = 0;
        
        while ([result next]) {
            NSString *body = [result stringForColumn:@"body"];
            if (body) {
                [resultString appendString:body];
                [resultString appendString:@"\n"];
                
                count++;
            }
        }
        
        [resultString insertString:[NSString stringWithFormat:@"查询结果(%zd个)：\n", count]
                           atIndex:0];
        
        [self insertLog:resultString];
    }];
    

}

- (IBAction)delete:(id)sender {
    [self.textField resignFirstResponder];
    
    if (self.textField.text.length == 0) {
        return;
    }
    
    [_queue inDatabase:^(FMDatabase * _Nonnull db) {
        NSString *sql = @"delete from message where body = '%@';";
        sql = [NSString stringWithFormat:sql, self.textField.text];
        
        BOOL result = [db executeUpdate:sql];
        
        if (result) {
            [self insertLog:@"删除成功！"];
        } else {
            [self insertLog:@"删除失败"];
        }
    }];
}

- (void)insertLog:(NSString *)log {
    [self.textField resignFirstResponder];
    
    if (!log || log.length == 0) return;
    
    NSString *text = self.textView.text;
    text = text ? text : @"";
    
    self.textView.text = [NSString stringWithFormat:@"%@%@\n", text, log];
}

- (void)writeJiebaDataToSandbox {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSString * docDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];

        
    NSString *dictDir = [NSString stringWithFormat:@"%@/%@", docDir, @"dict"];
    NSString *pos_dictDir = [NSString stringWithFormat:@"%@/%@", dictDir, @"pos_dict"];
    
    BOOL result = NO;
    if (![fileManager fileExistsAtPath:dictDir]) {
        result = [fileManager createDirectoryAtPath:dictDir withIntermediateDirectories:YES attributes:nil error:nil];
        if (result) {
            
        }
    }
    
    if (![fileManager fileExistsAtPath:pos_dictDir]) {
        result = [fileManager createDirectoryAtPath:pos_dictDir withIntermediateDirectories:YES attributes:nil error:nil];
        if (result) {
            
        }
    }
    
    if (![fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/hmm_model.utf8", dictDir]]) {
        NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"hmm_model.utf8" ofType:nil]];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/hmm_model.utf8", dictDir];
        
        if (![fileManager fileExistsAtPath:filePath]) {
            result = [fileManager createFileAtPath:filePath contents:data attributes:nil];
        }
        
        if (!result) {
            NSLog(@"写入数据失败");
        }
    }
    
    if (![fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/idf.utf8", dictDir]]) {
        NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"idf.utf8" ofType:nil]];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/idf.utf8", dictDir];
        
        if (![fileManager fileExistsAtPath:filePath]) {
            result = [fileManager createFileAtPath:filePath contents:data attributes:nil];
        }
        if (!result) {
            NSLog(@"写入数据失败");
        }
    }
    
    if (![fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/jieba.dict.utf8", dictDir]]) {
        NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"jieba.dict.utf8" ofType:nil]];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/jieba.dict.utf8", dictDir];
        
        if (![fileManager fileExistsAtPath:filePath]) {
            result = [fileManager createFileAtPath:filePath contents:data attributes:nil];
        }
        if (!result) {
            NSLog(@"写入数据失败");
        }
    }
    
    if (![fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/stop_words.utf8", dictDir]]) {
        NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"stop_words.utf8" ofType:nil]];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/stop_words.utf8", dictDir];
        
        if (![fileManager fileExistsAtPath:filePath]) {
            result = [fileManager createFileAtPath:filePath contents:data attributes:nil];
        }
        if (!result) {
            NSLog(@"写入数据失败");
        }
    }
    
    if (![fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/user.dict.utf8", dictDir]]) {
        NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"user.dict.utf8" ofType:nil]];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/user.dict.utf8", dictDir];
        
        if (![fileManager fileExistsAtPath:filePath]) {
            result = [fileManager createFileAtPath:filePath contents:data attributes:nil];
        }
        if (!result) {
            NSLog(@"写入数据失败");
        }
    }
    
    if (![fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/char_state_tab.utf8", pos_dictDir]]) {
        NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"char_state_tab.utf8" ofType:nil]];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/char_state_tab.utf8", pos_dictDir];
        
        if (![fileManager fileExistsAtPath:filePath]) {
            result = [fileManager createFileAtPath:filePath contents:data attributes:nil];
        }
        if (!result) {
            NSLog(@"写入数据失败");
        }
    }
    
    if (![fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/prob_emit.utf8", pos_dictDir]]) {
        NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"prob_emit.utf8" ofType:nil]];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/prob_emit.utf8", pos_dictDir];
        
        if (![fileManager fileExistsAtPath:filePath]) {
            result = [fileManager createFileAtPath:filePath contents:data attributes:nil];
        }
        if (!result) {
            NSLog(@"写入数据失败");
        }
    }
    
    if (![fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/prob_start.utf8", pos_dictDir]]) {
        NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"prob_start.utf8" ofType:nil]];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/prob_start.utf8", pos_dictDir];
        
        if (![fileManager fileExistsAtPath:filePath]) {
            result = [fileManager createFileAtPath:filePath contents:data attributes:nil];
        }
        if (!result) {
            NSLog(@"写入数据失败");
        }
    }
    
    if (![fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/prob_trans.utf8", pos_dictDir]]) {
        NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"prob_trans.utf8" ofType:nil]];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/prob_trans.utf8", pos_dictDir];
        
        if (![fileManager fileExistsAtPath:filePath]) {
            result = [fileManager createFileAtPath:filePath contents:data attributes:nil];
        }
        if (!result) {
            NSLog(@"写入数据失败");
        }
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.textField resignFirstResponder];
}

@end
