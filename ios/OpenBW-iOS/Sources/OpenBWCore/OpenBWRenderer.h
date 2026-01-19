// OpenBWRenderer.h
// Renders OpenBW game state to a framebuffer for Metal display

#ifndef OPENBWRENDERER_H
#define OPENBWRENDERER_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// Renderer for OpenBW game state
/// Renders tiles, sprites, and UI to an indexed framebuffer
@interface OpenBWRenderer : NSObject

/// Framebuffer dimensions
@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;

/// Pointer to the indexed (8-bit) framebuffer data
@property (nonatomic, readonly) const uint8_t* framebuffer;

/// Pointer to the RGBA palette (256 * 4 bytes)
@property (nonatomic, readonly) const uint8_t* palette;

/// Whether the renderer is ready to render
@property (nonatomic, readonly) BOOL isReady;

/// Initialize renderer with framebuffer dimensions
- (instancetype)initWithWidth:(int)width height:(int)height;

/// Load tileset and image data from game data path
/// Must be called after OpenBW is initialized
- (BOOL)loadImageDataFromPath:(NSString*)path error:(NSError**)error;

/// Set the tileset to use for rendering (0-7)
- (void)setTilesetIndex:(int)tilesetIndex;

/// Provide map tile indices for rendering (megatile indices, size = tileWidth * tileHeight)
/// @param tiles Pointer to tile indices (uint16_t values)
/// @param count Number of entries in tiles
/// @param tileWidth Map width in tiles
/// @param tileHeight Map height in tiles
- (void)setMapTiles:(const uint16_t*)tiles
              count:(NSUInteger)count
          tileWidth:(int)tileWidth
         tileHeight:(int)tileHeight;

/// Simple unit info for rendering (legacy - kept for compatibility)
typedef struct {
    float x;
    float y;
    int owner;
    int typeId;
    int health;
    int maxHealth;
    int shields;
    int maxShields;
    BOOL isSelected;
    BOOL isBuilding;
} RenderUnitInfo;

/// Information about a single GRP frame to render
typedef struct {
    const void* grpFrame;       // Pointer to grp_t::frame_t (opaque to Obj-C)
    int screenX;                // Screen X position (top-left of frame)
    int screenY;                // Screen Y position (top-left of frame)
    int frameWidth;             // Frame width in pixels
    int frameHeight;            // Frame height in pixels
    BOOL flipped;               // Horizontally flipped
    int modifier;               // Image modifier (0=normal, 10=shadow)
    int colorIndex;             // Player color index (0-15)
} RenderImageInfo;

/// Information about a sprite to render (contains multiple images)
typedef struct {
    const RenderImageInfo* images;  // Array of images for this sprite
    int imageCount;                 // Number of images
    int owner;                      // Owner player index
    int screenCenterX;              // Screen X center for selection circle
    int screenCenterY;              // Screen Y center for selection circle

    // Selection circle info
    int selectionCircleIndex;       // Circle size index (0-9), -1 = none
    int selectionCircleVPos;        // Vertical offset for circle

    // Health bar info
    int healthBarWidth;             // Width in pixels (0 = no bar)
    int hp;                         // Current HP
    int maxHp;                      // Max HP
    int shields;                    // Current shields
    int maxShields;                 // Max shields
    int energy;                     // Current energy
    int maxEnergy;                  // Max energy
    BOOL invincible;                // Skip HP bar if true
} RenderSpriteInfo;

/// Render the current game state to the framebuffer
/// @param cameraX Camera X position in world coordinates
/// @param cameraY Camera Y position in world coordinates
/// @param mapWidth Map width in pixels
/// @param mapHeight Map height in pixels
- (void)renderWithCameraX:(float)cameraX
                  cameraY:(float)cameraY
                 mapWidth:(int)mapWidth
                mapHeight:(int)mapHeight;

/// Set units to render (legacy placeholder rendering)
/// @param units Array of RenderUnitInfo
/// @param count Number of units
- (void)setUnits:(const RenderUnitInfo*)units count:(NSUInteger)count;

/// Set sprites to render this frame (full GRP sprite rendering)
/// @param sprites Array of RenderSpriteInfo
/// @param count Number of sprites
/// @param selectedMask Array of BOOL indicating which sprites are selected
- (void)setSprites:(const RenderSpriteInfo*)sprites
             count:(NSUInteger)count
      selectedMask:(const BOOL* _Nullable)selectedMask;

/// Set selection circle GRP data pointers
/// @param grps Array of pointers to grp_t structures (opaque)
/// @param count Number of selection circle sizes (typically 10)
- (void)setSelectionCircleGRPs:(const void* const* _Nullable)grps count:(NSUInteger)count;

/// Load sprite-related image data (player colors, HP bar colors)
/// Called internally by loadImageDataFromPath but can be called separately
- (BOOL)loadSpriteImageData:(NSError**)error;

/// Render a test pattern (for debugging)
- (void)renderTestPatternWithCameraX:(float)cameraX
                             cameraY:(float)cameraY
                            mapWidth:(int)mapWidth
                           mapHeight:(int)mapHeight;

/// Clear the framebuffer
- (void)clear;

@end

NS_ASSUME_NONNULL_END

#endif // OPENBWRENDERER_H
