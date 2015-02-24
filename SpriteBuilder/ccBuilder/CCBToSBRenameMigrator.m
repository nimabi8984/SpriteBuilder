#import "CCBToSBRenameMigrator.h"
#import "CCRenderer_Private.h"
#import "NSString+Misc.h"
#import "FileCommandProtocol.h"
#import "CCBDocumentManipulator.h"
#import "BackupFileCommand.h"
#import "NSError+SBErrors.h"
#import "Errors.h"
#import "MoveFileCommand.h"
#import "MigrationLogger.h"

static NSString *const LOGGER_SECTION = @"CCBToSBRenameMigrator";
static NSString *const LOGGER_ERROR = @"Error";
static NSString *const LOGGER_ROLLBACK = @"Rollback";

@interface CCBToSBRenameMigrator()

@property (nonatomic, strong) NSString *dirPath;
@property (nonatomic, strong) NSMutableArray *commands;
@property (nonatomic, strong) NSArray *allDocuments;
@property (nonatomic, strong) MigrationLogger *logger;

@end


@implementation CCBToSBRenameMigrator

- (id)initWithDirPath:(NSString *)dirPath
{
    NSAssert(dirPath != nil, @"dirPath must not be nil");

    self = [super init];

    if (self)
    {
        self.dirPath = dirPath;
        self.commands = [NSMutableArray array];
    }

    return self;
}

- (void)setLogger:(MigrationLogger *)migrationLogger
{
    _logger = migrationLogger;
}

- (NSArray *)allDocuments
{
    if (!_allDocuments)
    {
        self.allDocuments = [_dirPath allFilesInDirWithFilterBlock:^BOOL(NSURL *fileURL)
        {
            NSString *filename;
            [fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil];

            NSNumber *isDirectory;
            [fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];

            return ![isDirectory boolValue]
                   && ([[fileURL relativeString] hasSuffix:@"ccb"]);
        }];
    }

    return _allDocuments;
}

- (NSString *)htmlInfoText
{
    return @"Some old ccb file extensions found. Renaming of files to sb extension required, also references to ccb files within those documents.";
}

- (BOOL)isMigrationRequired
{
    return [self.allDocuments count] > 0;
}

- (BOOL)migrateWithError:(NSError **)error
{
    if (![self isMigrationRequired])
    {
        return YES;
    }

    [_logger log:@"Starting..." section:@[LOGGER_SECTION]];

    for (NSString *documentPath in self.allDocuments)
    {
        if (![self renameCCBFileToSB:documentPath error:error])
        {
            return NO;
        }
    }

    [_logger log:@"Finished successfully!" section:@[LOGGER_SECTION]];

    return YES;
}

- (BOOL)renameCCBFileToSB:(NSString *)path error:(NSError **)error
{
    NSString *newPath = [path replaceExtension:@"sb"];

    MoveFileCommand *moveFileCommand = [[MoveFileCommand alloc] initWithFromPath:path toPath:newPath];

    if (![moveFileCommand execute:error])
    {
        [_logger log:[NSString stringWithFormat:@"ccb to sb renaming failed: %@", *error] section:@[LOGGER_SECTION, LOGGER_ERROR]];
        return NO;
    }

    [_logger log:[NSString stringWithFormat:@"ccb to sb renaming successful from '%@' to '%@'", path, newPath] section:@[LOGGER_SECTION]];

    [_commands addObject:moveFileCommand];

    return YES;
}

- (void)rollback
{
    [_logger log:@"Starting..." section:@[LOGGER_SECTION, LOGGER_ROLLBACK]];

    for (id <FileCommandProtocol> command in _commands)
    {
        NSError *error;
        if (![command undo:&error])
        {
            [_logger log:[NSString stringWithFormat:@"Could not rollback ccb to sb renaming : %@", error] section:@[LOGGER_SECTION, LOGGER_ROLLBACK, LOGGER_ERROR]];
        }
    }

    [_logger log:@"Finished" section:@[LOGGER_SECTION, LOGGER_ROLLBACK]];
}

- (void)tidyUp
{
    for (id <FileCommandProtocol> command in _commands)
    {
        if ([command respondsToSelector:@selector(tidyUp)])
        {
            [command tidyUp];
        }
    }
}

@end
