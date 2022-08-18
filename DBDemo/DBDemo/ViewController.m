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
        BOOL result = NO;
        
        NSString *sql = @"create table if not exists message (       \
                          _id INTEGER PRIMARY KEY AUTOINCREMENT,    \
                          body TEXT);";
                    
        result = [db executeUpdate:sql];
        
        if (!result) {
            [self insertLog:@"创建主表执行失败!!!"];
            return;
        }
                
        sql = @"create virtual table if not exists virtual_message using fts5( \
                body, \
                content='message', \
                content_rowid='_id', \
                tokenize = 'simple')";
        
        result = [db executeUpdate:sql];
        
        if (!result) {
            [self insertLog:@"创建虚拟表执行失败!!!"];
            return;
        }
        
        FMResultSet *resultSet = [db executeQuery:@"SELECT name FROM sqlite_master WHERE type = 'trigger';"];
        
        if (![resultSet next]) {
            NSString *message_ai = @"CREATE TRIGGER message_ai AFTER INSERT ON message BEGIN \
                                        INSERT INTO virtual_message(rowid, body) VALUES (new._id, new.body); \
                                     END; ";
            NSString *message_ad = @"CREATE TRIGGER message_ad AFTER DELETE ON message BEGIN \
                                        INSERT INTO virtual_message(virtual_message, rowid, body) VALUES('delete', old._id, old.body); \
                                     END;";
            NSString *message_au = @"CREATE TRIGGER message_au AFTER UPDATE ON message BEGIN \
                                        INSERT INTO virtual_message(virtual_message, rowid, body) VALUES('delete', old._id, old.body); \
                                        INSERT INTO virtual_message(rowid, body) VALUES (new._id, new.body); \
                                     END;";
            
            if (![db executeUpdate:message_ai]) {
                [self insertLog:@"TRIGGER 创建失败！!!"];
                return;
            }
            
            if (![db executeUpdate:message_ad]) {
                [self insertLog:@"TRIGGER 创建失败！!!"];
                return;
            }
            
            if (![db executeUpdate:message_au]) {
                [self insertLog:@"TRIGGER 创建失败！!!"];
                return;
            }
        }
        
        NSString *jiebaPath = kJiebaPath;
        sql = [NSString stringWithFormat:@"select jieba_dict('%@')", jiebaPath];
        result = [db executeStatements:sql];
        if (!result) {
            [self insertLog:@"jieba_dict()失败！!!"];
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
        NSMutableArray *idArray = [NSMutableArray array];
        
        NSString *sql = [NSString stringWithFormat:@"select _id from message where body = '%@';", self.textField.text];
        FMResultSet *rs = [db executeQuery:sql];
        
        while ([rs next]) {
            NSString *rowId = [rs stringForColumn:@"_id"];
            if (rowId.length > 0) {
                [idArray addObject:rowId];
            }
        }
        
        BOOL result = NO;
        
        if (idArray.count > 0) {
            NSString *idsString = [idArray componentsJoinedByString:@","];
            
            sql = @"delete from message where _id in (%@);";
            sql = [NSString stringWithFormat:sql, idsString];
            result = [db executeUpdate:sql];
        }
                
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
