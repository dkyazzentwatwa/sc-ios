// MPQLoader.mm
// iOS wrapper for OpenBW MPQ file loading

#import "MPQLoader.h"

// OpenBW headers
#include "data_loading.h"

#include <string>
#include <memory>
#include <vector>

#pragma mark - MPQValidationResult Implementation

@implementation MPQValidationResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _isValid = NO;
        _foundFiles = @[];
        _missingFiles = @[];
    }
    return self;
}

@end

#pragma mark - MPQLoader Implementation

@interface MPQLoader ()
@property (nonatomic, copy, readwrite) NSString* dataPath;
@property (nonatomic, assign, readwrite) BOOL isLoaded;
@end

@implementation MPQLoader {
    // Store resolved paths for each MPQ file
    NSMutableDictionary<NSString*, NSString*>* _resolvedPaths;
}

static MPQLoader* _sharedInstance = nil;

+ (MPQLoader*)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[MPQLoader alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _resolvedPaths = [NSMutableDictionary dictionary];
        _isLoaded = NO;
    }
    return self;
}

#pragma mark - Class Methods

+ (NSString*)documentsDirectory {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.firstObject ?: @"";
}

+ (NSString*)bundleResourcesPath {
    return [[NSBundle mainBundle] resourcePath] ?: @"";
}

+ (NSArray<NSString*>*)mpqFilesInDirectory:(NSString*)path {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSError* error = nil;
    NSArray* contents = [fm contentsOfDirectoryAtPath:path error:&error];

    if (error) {
        NSLog(@"MPQLoader: Error listing directory %@: %@", path, error);
        return @[];
    }

    NSMutableArray* mpqFiles = [NSMutableArray array];
    for (NSString* file in contents) {
        if ([[file.pathExtension lowercaseString] isEqualToString:@"mpq"]) {
            [mpqFiles addObject:file];
        }
    }

    return mpqFiles;
}

#pragma mark - Required MPQ Files

// The canonical names (case variations we'll search for)
static NSArray<NSString*>* RequiredMPQFiles() {
    return @[@"STARDAT.MPQ", @"BROODAT.MPQ", @"patch_rt.mpq"];
}

// Alternative case variations to search for
static NSArray<NSArray<NSString*>*>* MPQFileVariants() {
    return @[
        @[@"STARDAT.MPQ", @"StarDat.mpq", @"stardat.mpq", @"Stardat.MPQ"],
        @[@"BROODAT.MPQ", @"BrooDat.mpq", @"broodat.mpq", @"Broodat.MPQ"],
        @[@"patch_rt.mpq", @"Patch_rt.mpq", @"PATCH_RT.MPQ", @"Patch_RT.mpq"]
    ];
}

#pragma mark - Path Resolution

- (nullable NSString*)findFileInDirectory:(NSString*)directory
                              withVariants:(NSArray<NSString*>*)variants {
    NSFileManager* fm = [NSFileManager defaultManager];

    for (NSString* variant in variants) {
        NSString* fullPath = [directory stringByAppendingPathComponent:variant];
        if ([fm fileExistsAtPath:fullPath]) {
            return fullPath;
        }
    }

    // Also try a case-insensitive search of directory contents
    NSError* error = nil;
    NSArray* contents = [fm contentsOfDirectoryAtPath:directory error:&error];
    if (!error) {
        NSString* targetLower = [variants.firstObject lowercaseString];
        for (NSString* file in contents) {
            if ([[file lowercaseString] isEqualToString:targetLower]) {
                return [directory stringByAppendingPathComponent:file];
            }
        }
    }

    return nil;
}

- (nullable NSString*)resolvedPathForFile:(NSString*)filename {
    return _resolvedPaths[filename];
}

#pragma mark - Validation

- (MPQValidationResult*)validateMPQFilesAtPath:(NSString*)path {
    MPQValidationResult* result = [[MPQValidationResult alloc] init];

    NSFileManager* fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;

    if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        result.error = [NSString stringWithFormat:@"Path does not exist or is not a directory: %@", path];
        return result;
    }

    NSMutableArray* found = [NSMutableArray array];
    NSMutableArray* missing = [NSMutableArray array];

    NSArray<NSArray<NSString*>*>* variants = MPQFileVariants();
    NSArray<NSString*>* canonical = RequiredMPQFiles();

    for (NSUInteger i = 0; i < variants.count; i++) {
        NSString* resolvedPath = [self findFileInDirectory:path withVariants:variants[i]];
        if (resolvedPath) {
            [found addObject:canonical[i]];
        } else {
            [missing addObject:canonical[i]];
        }
    }

    result.foundFiles = found;
    result.missingFiles = missing;
    result.isValid = (missing.count == 0);

    if (!result.isValid) {
        result.error = [NSString stringWithFormat:@"Missing required files: %@",
                        [missing componentsJoinedByString:@", "]];
    }

    return result;
}

#pragma mark - Loading

- (BOOL)loadFromPath:(NSString*)path error:(NSError**)error {
    NSLog(@"MPQLoader: Loading from path: %@", path);

    // Validate files exist
    MPQValidationResult* validation = [self validateMPQFilesAtPath:path];
    if (!validation.isValid) {
        if (error) {
            *error = [NSError errorWithDomain:@"MPQLoader"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: validation.error ?: @"Unknown error"}];
        }
        return NO;
    }

    // Resolve all paths
    NSArray<NSArray<NSString*>*>* variants = MPQFileVariants();
    NSArray<NSString*>* canonical = RequiredMPQFiles();

    [_resolvedPaths removeAllObjects];

    for (NSUInteger i = 0; i < variants.count; i++) {
        NSString* resolvedPath = [self findFileInDirectory:path withVariants:variants[i]];
        if (resolvedPath) {
            _resolvedPaths[canonical[i]] = resolvedPath;
            NSLog(@"MPQLoader: Resolved %@ -> %@", canonical[i], resolvedPath);
        }
    }

    self.dataPath = path;
    self.isLoaded = YES;

    NSLog(@"MPQLoader: Successfully loaded MPQ files from %@", path);
    return YES;
}

#pragma mark - Copying

- (BOOL)copyMPQFilesFromPath:(NSString*)sourcePath error:(NSError**)error {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSString* destPath = [MPQLoader documentsDirectory];

    NSArray<NSString*>* mpqFiles = [MPQLoader mpqFilesInDirectory:sourcePath];

    if (mpqFiles.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"MPQLoader"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"No MPQ files found in source directory"}];
        }
        return NO;
    }

    NSLog(@"MPQLoader: Copying %lu MPQ files from %@ to %@",
          (unsigned long)mpqFiles.count, sourcePath, destPath);

    for (NSString* file in mpqFiles) {
        NSString* srcFile = [sourcePath stringByAppendingPathComponent:file];
        NSString* dstFile = [destPath stringByAppendingPathComponent:file];

        // Remove existing file if present
        if ([fm fileExistsAtPath:dstFile]) {
            NSError* removeError = nil;
            if (![fm removeItemAtPath:dstFile error:&removeError]) {
                NSLog(@"MPQLoader: Warning - could not remove existing file: %@", removeError);
            }
        }

        NSError* copyError = nil;
        if (![fm copyItemAtPath:srcFile toPath:dstFile error:&copyError]) {
            if (error) {
                *error = [NSError errorWithDomain:@"MPQLoader"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"Failed to copy %@: %@",
                                                         file, copyError.localizedDescription]}];
            }
            return NO;
        }

        NSLog(@"MPQLoader: Copied %@", file);
    }

    return YES;
}

@end

#pragma mark - C++ Integration

// Create a data loader using the iOS-resolved paths
namespace bwgame {
namespace data_loading {

/// iOS-specific data files loader that uses resolved paths from MPQLoader
template<typename mpq_file_T = mpq_file<>>
struct ios_data_files_loader {
    a_list<mpq_file_T> mpqs;

    void add_mpq_file(a_string filename) {
        mpqs.emplace_back(std::move(filename));
    }

    void operator()(a_vector<uint8_t>& dst, a_string filename) {
        for (auto& v : mpqs) {
            if (v.mpq.file_exists(filename)) {
                v(dst, std::move(filename));
                return;
            }
        }
        error("ios_data_files_loader: %s: file not found", filename);
    }

    bool file_exists(const a_string& filename) {
        for (auto& v : mpqs) {
            if (v.mpq.file_exists(filename)) {
                return true;
            }
        }
        return false;
    }
};

/// Create an iOS data loader using MPQLoader's resolved paths
template<typename data_files_loader_T = ios_data_files_loader<>>
data_files_loader_T ios_data_files_directory() {
    data_files_loader_T r;

    MPQLoader* loader = [MPQLoader shared];
    if (!loader.isLoaded) {
        error("ios_data_files_directory: MPQLoader not initialized");
    }

    // Add MPQs in priority order (patches first)
    NSString* patchPath = [loader resolvedPathForFile:@"patch_rt.mpq"];
    NSString* broodPath = [loader resolvedPathForFile:@"BROODAT.MPQ"];
    NSString* starPath = [loader resolvedPathForFile:@"STARDAT.MPQ"];

    if (patchPath) {
        r.add_mpq_file([patchPath UTF8String]);
    }
    if (broodPath) {
        r.add_mpq_file([broodPath UTF8String]);
    }
    if (starPath) {
        r.add_mpq_file([starPath UTF8String]);
    }

    return r;
}

} // namespace data_loading
} // namespace bwgame
