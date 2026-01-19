// MPQLoader.h
// iOS wrapper for OpenBW MPQ file loading
// Handles iOS sandbox constraints and case-insensitive file matching

#ifndef MPQLOADER_H
#define MPQLOADER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Result of MPQ validation
@interface MPQValidationResult : NSObject
@property (nonatomic, assign) BOOL isValid;
@property (nonatomic, copy, nullable) NSString* error;
@property (nonatomic, copy) NSArray<NSString*>* foundFiles;
@property (nonatomic, copy) NSArray<NSString*>* missingFiles;
@end

/// Handles loading StarCraft MPQ data files for iOS
@interface MPQLoader : NSObject

/// Shared instance
@property (class, readonly) MPQLoader* shared;

/// The path where MPQ files are located (typically Documents directory)
@property (nonatomic, copy, nullable, readonly) NSString* dataPath;

/// Whether MPQ files have been successfully loaded
@property (nonatomic, assign, readonly) BOOL isLoaded;

/// Validate that required MPQ files exist at the given path
/// @param path Directory containing MPQ files
/// @return Validation result with details about found/missing files
- (MPQValidationResult*)validateMPQFilesAtPath:(NSString*)path;

/// Initialize the loader with a path to MPQ files
/// @param path Directory containing MPQ files
/// @param error On failure, contains error details
/// @return YES if initialization succeeded
- (BOOL)loadFromPath:(NSString*)path error:(NSError**)error;

/// Get the actual file path for an MPQ file (handles case sensitivity)
/// @param filename The canonical filename (e.g., "STARDAT.MPQ")
/// @return The actual path on disk, or nil if not found
- (nullable NSString*)resolvedPathForFile:(NSString*)filename;

/// Get the Documents directory path
+ (NSString*)documentsDirectory;

/// Get the app bundle resources path
+ (NSString*)bundleResourcesPath;

/// List all .mpq files in a directory
+ (NSArray<NSString*>*)mpqFilesInDirectory:(NSString*)path;

/// Copy MPQ files from source to Documents directory
/// @param sourcePath Source directory containing MPQ files
/// @param error On failure, contains error details
/// @return YES if copy succeeded
- (BOOL)copyMPQFilesFromPath:(NSString*)sourcePath error:(NSError**)error;

@end

NS_ASSUME_NONNULL_END

#endif // MPQLOADER_H
