// OpenBWBridge.mm
// Objective-C++ implementation bridging Swift to OpenBW C++

#import "OpenBWBridge.h"

#include <memory>
#include <string>
#include <vector>

// OpenBW headers
#include "bwgame.h"
#include "actions.h"
#include "replay.h"

// Include game runner
#import "OpenBWGameRunner.h"

// Namespace aliases for convenience
namespace bw = bwgame;

#pragma mark - OpenBWUnit Implementation

@implementation OpenBWUnit {
    int _unitId;
    int _typeId;
    int _playerId;
    int _x;
    int _y;
    int _health;
    int _maxHealth;
    BOOL _isSelected;
}

- (instancetype)initWithId:(int)unitId
                    typeId:(int)typeId
                  playerId:(int)playerId
                         x:(int)x
                         y:(int)y
                    health:(int)health
                 maxHealth:(int)maxHealth
                isSelected:(BOOL)isSelected {
    self = [super init];
    if (self) {
        _unitId = unitId;
        _typeId = typeId;
        _playerId = playerId;
        _x = x;
        _y = y;
        _health = health;
        _maxHealth = maxHealth;
        _isSelected = isSelected;
    }
    return self;
}

- (int)unitId { return _unitId; }
- (int)typeId { return _typeId; }
- (int)playerId { return _playerId; }
- (int)x { return _x; }
- (int)y { return _y; }
- (int)health { return _health; }
- (int)maxHealth { return _maxHealth; }
- (BOOL)isSelected { return _isSelected; }

@end

#pragma mark - OpenBWGameState Implementation

@implementation OpenBWGameState {
    int _frameCount;
    int _currentPlayer;
    int _minerals;
    int _gas;
    int _supply;
    int _supplyMax;
    NSArray<OpenBWUnit*>* _visibleUnits;
}

- (instancetype)initWithFrame:(int)frame
                       player:(int)player
                     minerals:(int)minerals
                          gas:(int)gas
                       supply:(int)supply
                    supplyMax:(int)supplyMax
                        units:(NSArray<OpenBWUnit*>*)units {
    self = [super init];
    if (self) {
        _frameCount = frame;
        _currentPlayer = player;
        _minerals = minerals;
        _gas = gas;
        _supply = supply;
        _supplyMax = supplyMax;
        _visibleUnits = [units copy];
    }
    return self;
}

- (int)frameCount { return _frameCount; }
- (int)currentPlayer { return _currentPlayer; }
- (int)minerals { return _minerals; }
- (int)gas { return _gas; }
- (int)supply { return _supply; }
- (int)supplyMax { return _supplyMax; }
- (NSArray<OpenBWUnit*>*)visibleUnits { return _visibleUnits; }

@end

#pragma mark - OpenBWConfig Implementation

@implementation OpenBWConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _mapPath = @"";
        _replayPath = nil;
        _playerRace = 0;  // Terran
        _aiDifficulty = 1;
        _enableSound = YES;
        _enableMusic = YES;
    }
    return self;
}

@end

#pragma mark - OpenBWEngine Implementation

@interface OpenBWEngine ()
@property (nonatomic, strong) dispatch_queue_t gameQueue;
@property (nonatomic, assign) BOOL initialized;
@property (nonatomic, strong) NSString* assetPath;
@property (nonatomic, strong) OpenBWGameRunner* gameRunner;
@end

@implementation OpenBWEngine {
    // C++ game state
    // Note: In a full implementation, these would be the actual OpenBW game objects
    // For now, they're placeholders to demonstrate the architecture

    // Game loop state
    BOOL _isPaused;
    int _currentFrame;

    // Camera state
    float _cameraX;
    float _cameraY;
    float _zoomLevel;

    // Selection state
    std::vector<int> _selectedUnits;
    std::vector<std::vector<int>> _controlGroups;
}

static OpenBWEngine* _sharedInstance = nil;

+ (OpenBWEngine*)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[OpenBWEngine alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _gameQueue = dispatch_queue_create("com.openbw.gameloop", DISPATCH_QUEUE_SERIAL);
        _initialized = NO;
        _isPaused = NO;
        _currentFrame = 0;
        _cameraX = 0;
        _cameraY = 0;
        _zoomLevel = 1.0f;
        _controlGroups.resize(10);  // 10 control groups (0-9)
    }
    return self;
}

- (BOOL)isGameRunning {
    return _initialized && !_isPaused;
}

- (BOOL)initializeWithAssetPath:(NSString*)assetPath error:(NSError**)error {
    @try {
        _assetPath = assetPath;

        // Verify required files exist
        NSFileManager* fm = [NSFileManager defaultManager];
        NSArray* requiredFiles = @[@"StarDat.mpq", @"BrooDat.mpq", @"Patch_rt.mpq"];

        for (NSString* file in requiredFiles) {
            NSString* path = [assetPath stringByAppendingPathComponent:file];
            NSLog(@"OpenBWBridge: Checking for file at path: %@", path);
            BOOL exists = [fm fileExistsAtPath:path];
            NSLog(@"OpenBWBridge: File exists: %@", exists ? @"YES" : @"NO");
            if (!exists) {
                // Try case variations
                NSArray* variants = @[file, [file lowercaseString], [file uppercaseString]];
                BOOL found = NO;
                for (NSString* variant in variants) {
                    NSString* variantPath = [assetPath stringByAppendingPathComponent:variant];
                    if ([fm fileExistsAtPath:variantPath]) {
                        NSLog(@"OpenBWBridge: Found file with variant name: %@", variant);
                        found = YES;
                        break;
                    }
                }
                if (!found) {
                    if (error) {
                        *error = [NSError errorWithDomain:@"OpenBW"
                                                     code:1
                                                 userInfo:@{NSLocalizedDescriptionKey:
                                                                [NSString stringWithFormat:@"Missing required file: %@", file]}];
                    }
                    return NO;
                }
            }
        }

        // Create Metal device
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            if (error) {
                *error = [NSError errorWithDomain:@"OpenBW"
                                             code:5
                                         userInfo:@{NSLocalizedDescriptionKey: @"Metal not available on this device"}];
            }
            return NO;
        }

        // Create game runner
        _gameRunner = [[OpenBWGameRunner alloc] initWithDevice:device];
        if (!_gameRunner) {
            if (error) {
                *error = [NSError errorWithDomain:@"OpenBW"
                                             code:6
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to create game runner"}];
            }
            return NO;
        }

        // Load assets
        NSError* loadError = nil;
        if (![_gameRunner loadAssetsFromPath:assetPath error:&loadError]) {
            if (error) *error = loadError;
            return NO;
        }

        _initialized = YES;
        return YES;
    }
    @catch (NSException* exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenBW"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown error"}];
        }
        return NO;
    }
}

- (BOOL)startGameWithConfig:(OpenBWConfig*)config error:(NSError**)error {
    if (!_initialized) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenBW"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Engine not initialized"}];
        }
        return NO;
    }

    // Start game via game runner
    NSError* gameError = nil;
    if (![_gameRunner startGameWithMap:config.mapPath
                            playerRace:config.playerRace
                          aiDifficulty:config.aiDifficulty
                                 error:&gameError]) {
        if (error) *error = gameError;
        return NO;
    }

    _currentFrame = 0;
    _isPaused = NO;

    // Set up frame update callback
    __weak typeof(self) weakSelf = self;
    _gameRunner.onFrameUpdate = ^(int frameCount, int minerals, int gas, int supply, int supplyMax) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf->_currentFrame = frameCount;

        if ([strongSelf.delegate respondsToSelector:@selector(frameDidUpdate:)]) {
            OpenBWGameState* state = [strongSelf createGameState];
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf.delegate frameDidUpdate:state];
            });
        }
    };

    // Notify delegate
    if ([self.delegate respondsToSelector:@selector(gameDidStart)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate gameDidStart];
        });
    }

    // Start game loop on background queue
    [self startGameLoop];

    return YES;
}

- (void)startGameLoop {
    dispatch_async(_gameQueue, ^{
        // Game loop runs at ~24 FPS (StarCraft's native frame rate)
        while (!self->_isPaused && self->_initialized) {
            // Process one game frame
            [self processFrame];

            // Sleep to maintain frame rate
            usleep(41667);  // ~24 FPS
        }
    });
}

- (void)processFrame {
    // Advance game via game runner
    [_gameRunner tick];
    _currentFrame = _gameRunner.currentFrame;
}

- (OpenBWGameState*)createGameState {
    // TODO: Extract actual game state from OpenBW
    // For now, return placeholder data

    NSArray<OpenBWUnit*>* units = @[];
    return [[OpenBWGameState alloc] initWithFrame:_currentFrame
                                           player:0
                                         minerals:50
                                              gas:0
                                           supply:4
                                        supplyMax:10
                                            units:units];
}

- (void)pause {
    _isPaused = YES;
}

- (void)resume {
    if (_isPaused) {
        _isPaused = NO;
        [self startGameLoop];
    }
}

- (void)stop {
    _isPaused = YES;
    _currentFrame = 0;
    _selectedUnits.clear();

    if ([self.delegate respondsToSelector:@selector(gameDidEnd:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate gameDidEnd:NO];
        });
    }
}

#pragma mark - Input Handling

- (void)touchBeganAtX:(CGFloat)x y:(CGFloat)y {
    // Touch input handled directly - converted to game commands
    // TODO: Convert screen coordinates to game world coordinates
}

- (void)touchMovedToX:(CGFloat)x y:(CGFloat)y {
    // Touch moved - update selection box or camera drag
    // TODO: Implement touch tracking
}

- (void)touchEndedAtX:(CGFloat)x y:(CGFloat)y {
    // Touch ended - finalize selection or command
    // TODO: Issue game commands based on touch gesture
}

- (void)pinchWithScale:(CGFloat)scale {
    _zoomLevel *= scale;
    _zoomLevel = fmax(0.5f, fmin(2.0f, _zoomLevel));  // Clamp zoom
}

- (void)panWithDeltaX:(CGFloat)dx deltaY:(CGFloat)dy {
    _cameraX += dx / _zoomLevel;
    _cameraY += dy / _zoomLevel;
}

#pragma mark - Commands

- (void)selectUnitAtX:(CGFloat)x y:(CGFloat)y {
    // Forward to game runner
    [_gameRunner selectUnitAtX:x y:y];
    _selectedUnits.clear();
    // TODO: Get selected unit IDs from game runner
}

- (void)boxSelectFromX:(CGFloat)x1 y:(CGFloat)y1 toX:(CGFloat)x2 y:(CGFloat)y2 {
    // Forward to game runner
    CGRect rect = CGRectMake(fmin(x1, x2), fmin(y1, y2), fabs(x2 - x1), fabs(y2 - y1));
    [_gameRunner selectUnitsInRect:rect];
    _selectedUnits.clear();
    // TODO: Get selected unit IDs from game runner
}

- (void)moveSelectedToX:(CGFloat)x y:(CGFloat)y {
    // Forward to game runner
    [_gameRunner moveSelectedToX:x y:y];
}

- (void)attackMoveToX:(CGFloat)x y:(CGFloat)y {
    // Forward to game runner
    [_gameRunner attackMoveToX:x y:y];
}

- (void)buildStructure:(int)structureTypeId atX:(CGFloat)x y:(CGFloat)y {
    // Forward to game runner
    [_gameRunner buildStructure:structureTypeId atX:x y:y];
}

- (void)trainUnit:(int)unitTypeId {
    // Forward to game runner
    [_gameRunner trainUnit:unitTypeId];
}

- (void)assignToControlGroup:(int)groupNumber {
    if (groupNumber >= 0 && groupNumber < 10) {
        _controlGroups[groupNumber] = _selectedUnits;
    }
}

- (void)selectControlGroup:(int)groupNumber {
    if (groupNumber >= 0 && groupNumber < 10) {
        _selectedUnits = _controlGroups[groupNumber];
    }
}

#pragma mark - Camera Control

- (void)setCameraX:(CGFloat)x y:(CGFloat)y {
    _cameraX = x;
    _cameraY = y;
}

- (CGPoint)cameraPosition {
    return CGPointMake(_cameraX, _cameraY);
}

- (void)setZoomLevel:(CGFloat)zoom {
    _zoomLevel = fmax(0.5f, fmin(2.0f, zoom));
}

#pragma mark - Rendering

- (void)renderToTexture:(id<MTLTexture>)texture {
    // TODO: Render current game state to Metal texture
    // This would use OpenBW's rendering code adapted for Metal
}

- (CGSize)preferredRenderSize {
    // StarCraft's native resolution was 640x480
    // We can render at higher resolution and scale
    return CGSizeMake(1280, 960);
}

- (OpenBWGameState*)gameState {
    if (!_initialized) return nil;
    return [self createGameState];
}

@end
