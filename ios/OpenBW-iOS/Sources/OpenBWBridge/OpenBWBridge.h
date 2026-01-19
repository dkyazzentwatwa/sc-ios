// OpenBWBridge.h
// Objective-C/C++ bridge for Swift integration with OpenBW

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Forward declare the game runner
@class OpenBWGameRunner;

NS_ASSUME_NONNULL_BEGIN

/// Represents a unit in the game
@interface OpenBWUnit : NSObject
@property (nonatomic, readonly) int unitId;
@property (nonatomic, readonly) int typeId;
@property (nonatomic, readonly) int playerId;
@property (nonatomic, readonly) int x;
@property (nonatomic, readonly) int y;
@property (nonatomic, readonly) int health;
@property (nonatomic, readonly) int maxHealth;
@property (nonatomic, readonly) BOOL isSelected;
@end

/// Represents the current game state
@interface OpenBWGameState : NSObject
@property (nonatomic, readonly) int frameCount;
@property (nonatomic, readonly) int currentPlayer;
@property (nonatomic, readonly) int minerals;
@property (nonatomic, readonly) int gas;
@property (nonatomic, readonly) int supply;
@property (nonatomic, readonly) int supplyMax;
@property (nonatomic, readonly) NSArray<OpenBWUnit*>* visibleUnits;
@end

/// Game configuration options
@interface OpenBWConfig : NSObject
@property (nonatomic, copy) NSString* mapPath;
@property (nonatomic, copy, nullable) NSString* replayPath;
@property (nonatomic, assign) int playerRace;  // 0=Terran, 1=Protoss, 2=Zerg
@property (nonatomic, assign) int aiDifficulty;
@property (nonatomic, assign) BOOL enableSound;
@property (nonatomic, assign) BOOL enableMusic;
@end

/// Delegate for receiving game events
@protocol OpenBWGameDelegate <NSObject>
@optional
- (void)gameDidStart;
- (void)gameDidEnd:(BOOL)victory;
- (void)frameDidUpdate:(OpenBWGameState*)state;
- (void)unitDidSpawn:(OpenBWUnit*)unit;
- (void)unitDidDie:(OpenBWUnit*)unit;
- (void)errorOccurred:(NSError*)error;
@end

/// Main game engine interface
@interface OpenBWEngine : NSObject

/// Shared instance (singleton pattern for now)
@property (class, readonly) OpenBWEngine* shared;

/// Game delegate for receiving events
@property (nonatomic, weak, nullable) id<OpenBWGameDelegate> delegate;

/// Current game state (nil if no game running)
@property (nonatomic, readonly, nullable) OpenBWGameState* gameState;

/// Whether a game is currently running
@property (nonatomic, readonly) BOOL isGameRunning;

/// Initialize the engine with asset paths
- (BOOL)initializeWithAssetPath:(NSString*)assetPath error:(NSError**)error;

/// Start a new game with configuration
- (BOOL)startGameWithConfig:(OpenBWConfig*)config error:(NSError**)error;

/// Pause the game
- (void)pause;

/// Resume the game
- (void)resume;

/// Stop the current game
- (void)stop;

// Input Flow:
// 1. TouchInputManager (gesture recognition in Swift)
// 2. GameController (command routing in Swift)
// 3. OpenBWGameRunner (game state modification in Objective-C++)
// Input methods previously defined here have been removed - use the above flow instead.

#pragma mark - Commands

/// Select unit at screen position
- (void)selectUnitAtX:(CGFloat)x y:(CGFloat)y;

/// Box select units in rectangle
- (void)boxSelectFromX:(CGFloat)x1 y:(CGFloat)y1 toX:(CGFloat)x2 y:(CGFloat)y2;

/// Command selected units to move to position
- (void)moveSelectedToX:(CGFloat)x y:(CGFloat)y;

/// Command selected units to attack position
- (void)attackMoveToX:(CGFloat)x y:(CGFloat)y;

/// Build a structure at position
- (void)buildStructure:(int)structureTypeId atX:(CGFloat)x y:(CGFloat)y;

/// Train a unit from selected building
- (void)trainUnit:(int)unitTypeId;

/// Assign selected units to control group
- (void)assignToControlGroup:(int)groupNumber;

/// Select control group
- (void)selectControlGroup:(int)groupNumber;

#pragma mark - Camera Control

/// Move camera to world position
- (void)setCameraX:(CGFloat)x y:(CGFloat)y;

/// Get current camera position
- (CGPoint)cameraPosition;

/// Set zoom level (1.0 = normal)
- (void)setZoomLevel:(CGFloat)zoom;

#pragma mark - Rendering

/// Render the current frame to a Metal texture
- (void)renderToTexture:(id<MTLTexture>)texture;

/// Get the preferred render size
- (CGSize)preferredRenderSize;

/// Get the underlying game runner for advanced usage
@property (nonatomic, readonly, nullable) OpenBWGameRunner* gameRunner;

@end

NS_ASSUME_NONNULL_END

// Re-export the game runner header
#import "OpenBWGameRunner.h"
