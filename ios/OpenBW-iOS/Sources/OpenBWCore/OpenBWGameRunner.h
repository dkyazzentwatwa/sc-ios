// OpenBWGameRunner.h
// Core game runner that manages the OpenBW game loop and rendering

#ifndef OpenBWGameRunner_h
#define OpenBWGameRunner_h

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Callback for frame updates
typedef void (^FrameUpdateCallback)(int frameCount, int minerals, int gas, int supply, int supplyMax);

/// Callback for game events
typedef void (^GameEventCallback)(NSString* eventType, NSDictionary* eventData);

/// Information about a selected unit
@interface SelectedUnitInfo : NSObject
@property (nonatomic, readonly) int unitId;
@property (nonatomic, readonly) int typeId;
@property (nonatomic, readonly, copy) NSString* typeName;
@property (nonatomic, readonly) int owner;
@property (nonatomic, readonly) float x;
@property (nonatomic, readonly) float y;
@property (nonatomic, readonly) int health;
@property (nonatomic, readonly) int maxHealth;
@property (nonatomic, readonly) int shields;
@property (nonatomic, readonly) int maxShields;
@property (nonatomic, readonly) int energy;
@property (nonatomic, readonly) int maxEnergy;
@property (nonatomic, readonly) BOOL isBuilding;
@property (nonatomic, readonly) BOOL isWorker;
@property (nonatomic, readonly) BOOL canAttack;
@property (nonatomic, readonly) BOOL canMove;

- (instancetype)initWithId:(int)unitId
                    typeId:(int)typeId
                  typeName:(NSString*)typeName
                     owner:(int)owner
                         x:(float)x
                         y:(float)y
                    health:(int)health
                 maxHealth:(int)maxHealth
                   shields:(int)shields
                maxShields:(int)maxShields
                    energy:(int)energy
                 maxEnergy:(int)maxEnergy
                isBuilding:(BOOL)isBuilding
                  isWorker:(BOOL)isWorker
                 canAttack:(BOOL)canAttack
                   canMove:(BOOL)canMove;
@end

/// Core game runner managing the OpenBW engine
@interface OpenBWGameRunner : NSObject

/// Initialize with Metal device
- (instancetype)initWithDevice:(id<MTLDevice>)device;

/// Load game assets from the specified path (containing MPQ files)
- (BOOL)loadAssetsFromPath:(NSString*)path error:(NSError**)error;

/// Start a new game on the specified map
- (BOOL)startGameWithMap:(NSString*)mapPath
              playerRace:(int)race
            aiDifficulty:(int)difficulty
                   error:(NSError**)error;

/// Load and play a replay file
- (BOOL)loadReplay:(NSString*)replayPath error:(NSError**)error;

/// Advance the game by one frame
- (void)tick;

/// Render current game state to the provided render pass
- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder;

/// Render to the MTKView
- (void)renderToView:(MTKView*)view;

/// Pause/resume game
- (void)pause;
- (void)resume;
- (BOOL)isPaused;

/// Stop and cleanup
- (void)stop;

/// Camera control
- (void)setCameraX:(float)x y:(float)y;
- (void)getCameraX:(float*)x y:(float*)y;
- (void)setZoom:(float)zoom;
- (float)zoom;

/// Viewport dimensions (call when view size changes)
- (void)setViewportWidth:(float)width height:(float)height;
- (float)viewportWidth;
- (float)viewportHeight;

/// Screen to world coordinate conversion
- (void)screenToWorld:(CGPoint)screen worldX:(float*)x worldY:(float*)y;
- (CGPoint)worldToScreen:(float)worldX worldY:(float)worldY;

/// Game commands - Selection
- (void)selectUnitAtX:(CGFloat)x y:(CGFloat)y;
- (void)selectUnitsInRect:(CGRect)screenRect;
- (BOOL)hasSelectedUnits;
- (NSInteger)selectedUnitCount;
- (nullable NSArray<SelectedUnitInfo*>*)getSelectedUnitsInfo;

/// Game commands - Unit orders
- (void)moveSelectedToX:(CGFloat)x y:(CGFloat)y;
- (void)attackMoveToX:(CGFloat)x y:(CGFloat)y;
- (void)stopSelected;
- (void)holdPosition;
- (void)patrolToX:(CGFloat)x y:(CGFloat)y;
- (void)commandSelectedToPosition:(CGPoint)worldPos rightClick:(BOOL)rightClick;
- (void)issueCommand:(int)commandId targetX:(float)x targetY:(float)y targetUnit:(int)unitId;

/// Game commands - Building/Training
- (void)buildStructure:(int)structureTypeId atX:(CGFloat)x y:(CGFloat)y;
- (void)trainUnit:(int)unitTypeId;

/// Game commands - Abilities
/// Get available abilities for currently selected unit(s)
/// Returns array of dictionaries with: id, name, energyCost, needsTarget (bool), targetType (0=none, 1=ground, 2=unit)
- (nullable NSArray<NSDictionary*>*)getAvailableAbilities;

/// Use ability without target (e.g., Stim Pack, Siege Mode, Burrow)
- (void)useAbility:(int)abilityId;

/// Use ability on ground target (e.g., Psionic Storm, Scanner Sweep)
- (void)useAbilityOnGround:(int)abilityId atX:(CGFloat)x y:(CGFloat)y;

/// Use ability on unit target (e.g., Yamato Cannon, Lockdown)
- (void)useAbilityOnUnit:(int)abilityId targetUnitId:(int)targetId;

/// Control Groups (0-9)
/// Assign currently selected units to a control group
- (void)assignControlGroup:(int)group;

/// Add currently selected units to a control group (without replacing)
- (void)addToControlGroup:(int)group;

/// Select all units in a control group
- (void)selectControlGroup:(int)group;

/// Get the number of units in a control group
- (int)getControlGroupSize:(int)group;

/// Rally Points
/// Set rally point for selected production building at world coordinates
- (void)setRallyPointAtX:(CGFloat)x y:(CGFloat)y;

/// Set rally point to follow a specific unit
- (void)setRallyPointToUnit:(int)targetUnitId;

/// Callbacks
@property (nonatomic, copy, nullable) FrameUpdateCallback onFrameUpdate;
@property (nonatomic, copy, nullable) GameEventCallback onGameEvent;

/// Game state queries
@property (nonatomic, readonly) int currentFrame;
@property (nonatomic, readonly) int mapWidth;
@property (nonatomic, readonly) int mapHeight;
@property (nonatomic, readonly) BOOL isGameRunning;

/// Minimap support
/// Returns minimap as RGBA pixel data (caller must free with free())
/// Width and height are returned in outWidth/outHeight
- (nullable uint8_t*)getMinimapRGBA:(int*)outWidth height:(int*)outHeight;

/// Get minimap size in pixels
- (CGSize)minimapSize;

@end

NS_ASSUME_NONNULL_END

#endif /* OpenBWGameRunner_h */
