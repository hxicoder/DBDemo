//
//  FTSService.m
//  DBDemo
//
//  Created by Cruz on 2022/8/15.
//

#import "FTSService.h"

#import <SQLCipher/sqlite3.h>

#ifdef __cplusplus
extern "C" {
#endif

void sqlite3_simple_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi);

#ifdef __cplusplus
}
#endif

@implementation FTSService

+ (void)registerFTS {
    sqlite3_auto_extension((void (*)(void))sqlite3_simple_init);
}

@end
