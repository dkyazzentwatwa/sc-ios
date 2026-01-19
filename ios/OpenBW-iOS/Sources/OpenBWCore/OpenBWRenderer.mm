// OpenBWRenderer.mm
// Renders OpenBW game state to a framebuffer

#import "OpenBWRenderer.h"
#import "MPQLoader.h"

// OpenBW headers
#include "bwgame.h"
#include "data_loading.h"

// Include UI structures for tileset/image data
// We redefine the necessary structures here to avoid pulling in SDL dependencies

#include <vector>
#include <array>
#include <memory>
#include <cstring>

namespace ios_renderer {

// VR4 entry - tile bitmap data (8x8 pixels per tile piece)
struct vr4_entry {
    using bitmap_t = uint64_t;  // 8 bytes = 8 pixels
    std::array<bitmap_t, 8> bitmap;           // Normal orientation
    std::array<bitmap_t, 8> inverted_bitmap;  // Horizontally flipped
};

// VX4 entry - megatile composition (4x4 VR4 tiles = 32x32 pixels)
struct vx4_entry {
    std::array<uint16_t, 16> images;  // 16 image indices (4x4 grid)
};

// Tileset image data
struct tileset_image_data {
    std::vector<uint8_t> wpe;         // Palette (256 * 4 bytes RGBX)
    std::vector<vr4_entry> vr4;       // Tile graphics
    std::vector<vx4_entry> vx4;       // Megatile references
    bool loaded = false;
};

// Load VR4 data (tile graphics)
template<typename data_T>
void load_vr4(std::vector<vr4_entry>& vr4, const data_T& data) {
    size_t element_size = 64;  // 8x8 pixels
    size_t count = data.size() / element_size;
    vr4.resize(count);

    const uint8_t* src = data.data();
    for (size_t i = 0; i < count; ++i) {
        // Load bitmap (8 rows of 8 pixels)
        for (size_t row = 0; row < 8; ++row) {
            uint64_t bitmap_row = 0;
            for (size_t col = 0; col < 8; ++col) {
                bitmap_row |= (uint64_t)src[row * 8 + col] << (col * 8);
            }
            vr4[i].bitmap[row] = bitmap_row;

            // Create inverted (horizontally flipped) version
            uint64_t inv_row = 0;
            for (size_t col = 0; col < 8; ++col) {
                inv_row |= (uint64_t)src[row * 8 + (7 - col)] << (col * 8);
            }
            vr4[i].inverted_bitmap[row] = inv_row;
        }
        src += element_size;
    }
}

// Load VX4 data (megatile indices)
template<typename data_T>
void load_vx4(std::vector<vx4_entry>& vx4, const data_T& data) {
    size_t element_size = 32;  // 16 uint16_t values
    size_t count = data.size() / element_size;
    vx4.resize(count);

    bwgame::data_loading::data_reader_le r(data.data(), data.data() + data.size());
    for (size_t i = 0; i < count; ++i) {
        for (size_t j = 0; j < 16; ++j) {
            vx4[i].images[j] = r.get<uint16_t>();
        }
    }
}

// Draw a single 32x32 megatile to the framebuffer
void draw_tile(const tileset_image_data& img, size_t megatile_index,
               uint8_t* dst, size_t pitch,
               int offset_x, int offset_y, int width, int height) {
    if (megatile_index >= img.vx4.size()) return;

    const uint16_t* images = img.vx4[megatile_index].images.data();

    // Each megatile is 4x4 VR4 tiles (each VR4 tile is 8x8 pixels)
    for (int tile_y = 0; tile_y < 4; ++tile_y) {
        for (int tile_x = 0; tile_x < 4; ++tile_x) {
            uint16_t image_index = images[tile_y * 4 + tile_x];
            bool inverted = (image_index & 1) != 0;
            size_t vr4_index = image_index / 2;

            if (vr4_index >= img.vr4.size()) continue;

            const uint64_t* bitmap = inverted ?
                img.vr4[vr4_index].inverted_bitmap.data() :
                img.vr4[vr4_index].bitmap.data();

            int base_x = tile_x * 8;
            int base_y = tile_y * 8;

            // Draw 8x8 tile
            for (int row = 0; row < 8; ++row) {
                int screen_y = base_y + row;
                if (screen_y < offset_y || screen_y >= height) continue;

                uint64_t row_data = bitmap[row];
                uint8_t* row_dst = dst + screen_y * pitch + base_x;

                for (int col = 0; col < 8; ++col) {
                    int screen_x = base_x + col;
                    if (screen_x < offset_x || screen_x >= width) continue;

                    row_dst[col] = (uint8_t)(row_data >> (col * 8));
                }
            }
        }
    }
}

// ============================================================================
// GRP Sprite Rendering
// ============================================================================

// Color remapping functions
struct no_remap {
    uint8_t operator()(uint8_t new_value, uint8_t old_value) const {
        return new_value;
    }
};

struct player_color_remap {
    const uint8_t* color_table;  // 8 colors for this player
    uint8_t operator()(uint8_t new_value, uint8_t old_value) const {
        // Palette indices 8-15 are remapped to player colors
        if (new_value >= 8 && new_value < 16) {
            return color_table[new_value - 8];
        }
        return new_value;
    }
};

struct selection_circle_remap {
    uint8_t color;  // Single color for selection circle
    uint8_t operator()(uint8_t new_value, uint8_t old_value) const {
        // Selection circles use indices 0-7, remap to player color
        if (new_value < 8) {
            return color;
        }
        return new_value;
    }
};

struct shadow_remap {
    // Simple shadow - darken the underlying pixel
    uint8_t operator()(uint8_t new_value, uint8_t old_value) const {
        // Use a simple darkening by picking a darker palette entry
        // In real SC, this uses dark.pcx lookup table
        if (old_value > 16) return old_value - 16;
        return old_value;
    }
};

// Draw a single GRP frame to the framebuffer with RLE decompression
// This is the core sprite rendering function ported from ui/ui.h
template<bool bounds_check, bool flipped, typename remap_F>
void draw_grp_frame_impl(const bwgame::grp_t::frame_t& frame, uint8_t* dst, size_t pitch,
                         size_t offset_x, size_t offset_y, size_t width, size_t height,
                         remap_F&& remap_f) {
    // Skip rows above visible area
    for (size_t y = 0; y != offset_y; ++y) {
        dst += pitch;
    }

    // Render visible rows
    for (size_t y = offset_y; y != height; ++y) {
        if (flipped) dst += frame.size.x - 1;

        const uint8_t* d = frame.data_container.data() + frame.line_data_offset.at(y);

        for (size_t x = flipped ? frame.size.x - 1 : 0;
             x != (flipped ? (size_t)0 - 1 : frame.size.x);) {

            int v = *d++;
            if (v & 0x80) {
                // Skip command: skip (v & 0x7f) transparent pixels
                v &= 0x7f;
                x += flipped ? -v : v;
                dst += flipped ? -v : v;
            } else if (v & 0x40) {
                // RLE run: repeat next byte (v & 0x3f) times
                v &= 0x3f;
                int c = *d++;
                for (; v; --v) {
                    if (!bounds_check || (x >= offset_x && x < width)) {
                        *dst = remap_f(c, *dst);
                    }
                    dst += flipped ? -1 : 1;
                    x += flipped ? -1 : 1;
                }
            } else {
                // Literal pixels: copy v pixels directly
                for (; v; --v) {
                    int c = *d++;
                    if (!bounds_check || (x >= offset_x && x < width)) {
                        *dst = remap_f(c, *dst);
                    }
                    dst += flipped ? -1 : 1;
                    x += flipped ? -1 : 1;
                }
            }
        }

        if (!flipped) dst -= frame.size.x;
        else ++dst;
        dst += pitch;
    }
}

// Convenience wrapper that selects the right template instantiation
template<typename remap_F = no_remap>
void draw_grp_frame(const bwgame::grp_t::frame_t& frame, bool flipped,
                    uint8_t* dst, size_t pitch,
                    size_t offset_x, size_t offset_y, size_t width, size_t height,
                    remap_F&& remap_f = remap_F()) {
    if (offset_x == 0 && offset_y == 0 && width == frame.size.x && height == frame.size.y) {
        // No bounds checking needed - frame fits exactly
        if (flipped) {
            draw_grp_frame_impl<false, true>(frame, dst, pitch, offset_x, offset_y, width, height, std::forward<remap_F>(remap_f));
        } else {
            draw_grp_frame_impl<false, false>(frame, dst, pitch, offset_x, offset_y, width, height, std::forward<remap_F>(remap_f));
        }
    } else {
        // Bounds checking needed for clipping
        if (flipped) {
            draw_grp_frame_impl<true, true>(frame, dst, pitch, offset_x, offset_y, width, height, std::forward<remap_F>(remap_f));
        } else {
            draw_grp_frame_impl<true, false>(frame, dst, pitch, offset_x, offset_y, width, height, std::forward<remap_F>(remap_f));
        }
    }
}

// Image data storage (player colors, HP bar colors)
struct sprite_image_data {
    std::array<std::array<uint8_t, 8>, 16> player_unit_colors;   // 16 players × 8 colors
    std::array<uint8_t, 24> hp_bar_colors;                        // HP bar palette
    bool loaded = false;
};

} // namespace ios_renderer

#pragma mark - OpenBWRenderer Implementation

@implementation OpenBWRenderer {
    std::vector<uint8_t> _framebuffer;
    std::vector<uint8_t> _palette;
    std::array<ios_renderer::tileset_image_data, 8> _tilesets;
    int _currentTileset;
    bwgame::data_loading::data_files_loader<> _dataLoader;
    bool _dataLoaderInitialized;
    std::vector<uint16_t> _mapTiles;
    int _mapTileWidth;
    int _mapTileHeight;
    bool _hasMapTiles;
    std::vector<RenderUnitInfo> _units;

    // Sprite rendering data
    ios_renderer::sprite_image_data _spriteImageData;
    std::vector<RenderSpriteInfo> _sprites;
    std::vector<RenderImageInfo> _spriteImages;  // Flat storage for all images
    std::vector<BOOL> _selectedMask;
    std::vector<const bwgame::grp_t*> _selectionCircleGRPs;
}

- (instancetype)initWithWidth:(int)width height:(int)height {
    self = [super init];
    if (self) {
        _width = width;
        _height = height;
        _currentTileset = 0;
        _dataLoaderInitialized = NO;
        _mapTileWidth = 0;
        _mapTileHeight = 0;
        _hasMapTiles = NO;

        // Allocate framebuffer
        _framebuffer.resize(width * height, 0);

        // Initialize default grayscale palette
        _palette.resize(256 * 4);
        for (int i = 0; i < 256; i++) {
            _palette[i * 4 + 0] = i;      // R
            _palette[i * 4 + 1] = i;      // G
            _palette[i * 4 + 2] = i;      // B
            _palette[i * 4 + 3] = 255;    // A
        }
    }
    return self;
}

- (const uint8_t*)framebuffer {
    return _framebuffer.data();
}

- (const uint8_t*)palette {
    return _palette.data();
}

- (BOOL)isReady {
    return _dataLoaderInitialized && _tilesets[_currentTileset].loaded;
}

- (BOOL)loadImageDataFromPath:(NSString*)path error:(NSError**)error {
    @try {
        // Initialize data loader
        _dataLoader = bwgame::data_loading::data_files_loader<>();

        // Add MPQs in priority order
        MPQLoader* loader = [MPQLoader shared];
        NSArray<NSString*>* mpqFiles = @[@"patch_rt.mpq", @"BROODAT.MPQ", @"STARDAT.MPQ"];
        NSFileManager* fm = [NSFileManager defaultManager];
        for (NSString* mpq in mpqFiles) {
            NSString* resolvedPath = [loader resolvedPathForFile:mpq];
            if (resolvedPath.length > 0) {
                _dataLoader.add_mpq_file([resolvedPath UTF8String]);
                continue;
            }

            // Fallback to direct path resolution if MPQLoader is not initialized
            NSString* directPath = [path stringByAppendingPathComponent:mpq];
            if ([fm fileExistsAtPath:directPath]) {
                _dataLoader.add_mpq_file([directPath UTF8String]);
                continue;
            }

            NSString* lowerPath = [path stringByAppendingPathComponent:[mpq lowercaseString]];
            if ([fm fileExistsAtPath:lowerPath]) {
                _dataLoader.add_mpq_file([lowerPath UTF8String]);
                continue;
            }

            NSString* upperPath = [path stringByAppendingPathComponent:[mpq uppercaseString]];
            if ([fm fileExistsAtPath:upperPath]) {
                _dataLoader.add_mpq_file([upperPath UTF8String]);
            }
        }

        _dataLoaderInitialized = YES;

        // Load all tilesets
        NSArray<NSString*>* tilesetNames = @[
            @"badlands", @"platform", @"install", @"AshWorld",
            @"Jungle", @"Desert", @"Ice", @"Twilight"
        ];

        for (int i = 0; i < 8; i++) {
            [self loadTileset:i name:tilesetNames[i]];
        }

        // Load sprite image data (player colors, HP bar colors)
        NSError* spriteError = nil;
        [self loadSpriteImageData:&spriteError];
        if (spriteError) {
            NSLog(@"OpenBWRenderer: Warning - %@", spriteError.localizedDescription);
        }

        NSLog(@"OpenBWRenderer: Image data loaded successfully");
        return YES;
    }
    @catch (NSException* exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenBWRenderer"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Failed to load image data: %@",
                                          exception.reason ?: @"Unknown"]}];
        }
        return NO;
    }
}

- (void)loadTileset:(int)index name:(NSString*)name {
    if (!_dataLoaderInitialized) return;

    auto& tileset = _tilesets[index];

    @try {
        bwgame::a_vector<uint8_t> data;
        std::string prefix = "Tileset/" + std::string([name UTF8String]);

        // Load WPE (palette)
        try {
            _dataLoader(data, prefix + ".wpe");
            if (data.size() >= 256 * 4) {
                tileset.wpe.assign(data.begin(), data.end());
                NSLog(@"OpenBWRenderer: Loaded %@ palette (%zu bytes)", name, data.size());
            }
        }
        catch (...) {
            NSLog(@"OpenBWRenderer: Could not load %@.wpe", name);
        }

        // Load VR4 (tile graphics)
        try {
            _dataLoader(data, prefix + ".vr4");
            ios_renderer::load_vr4(tileset.vr4, data);
            NSLog(@"OpenBWRenderer: Loaded %@ VR4 (%zu tiles)", name, tileset.vr4.size());
        }
        catch (...) {
            NSLog(@"OpenBWRenderer: Could not load %@.vr4", name);
        }

        // Load VX4 (megatile indices)
        try {
            _dataLoader(data, prefix + ".vx4");
            ios_renderer::load_vx4(tileset.vx4, data);
            NSLog(@"OpenBWRenderer: Loaded %@ VX4 (%zu megatiles)", name, tileset.vx4.size());
        }
        catch (...) {
            NSLog(@"OpenBWRenderer: Could not load %@.vx4", name);
        }

        tileset.loaded = !tileset.vr4.empty() && !tileset.vx4.empty();

        // If this is the current tileset and we have a palette, update it
        if (index == _currentTileset && !tileset.wpe.empty()) {
            [self updatePaletteFromTileset:index];
        }
    }
    @catch (...) {
        NSLog(@"OpenBWRenderer: Failed to load tileset %@", name);
    }
}

- (void)updatePaletteFromTileset:(int)index {
    auto& tileset = _tilesets[index];
    if (tileset.wpe.size() >= 256 * 4) {
        for (int i = 0; i < 256; i++) {
            _palette[i * 4 + 0] = tileset.wpe[i * 4 + 0];  // R
            _palette[i * 4 + 1] = tileset.wpe[i * 4 + 1];  // G
            _palette[i * 4 + 2] = tileset.wpe[i * 4 + 2];  // B
            _palette[i * 4 + 3] = (i == 0) ? 0 : 255;      // A (index 0 transparent)
        }
    }
}

- (void)setTilesetIndex:(int)tilesetIndex {
    if (tilesetIndex >= 0 && tilesetIndex < 8) {
        _currentTileset = tilesetIndex;
        [self updatePaletteFromTileset:tilesetIndex];
    }
}

- (void)clear {
    std::memset(_framebuffer.data(), 0, _framebuffer.size());
}

- (void)setMapTiles:(const uint16_t*)tiles
              count:(NSUInteger)count
          tileWidth:(int)tileWidth
         tileHeight:(int)tileHeight {
    _mapTiles.clear();
    if (!tiles || count == 0 || tileWidth <= 0 || tileHeight <= 0) {
        _hasMapTiles = NO;
        _mapTileWidth = 0;
        _mapTileHeight = 0;
        return;
    }

    _mapTiles.assign(tiles, tiles + count);
    _mapTileWidth = tileWidth;
    _mapTileHeight = tileHeight;
    _hasMapTiles = YES;
}

- (void)setUnits:(const RenderUnitInfo*)units count:(NSUInteger)count {
    _units.clear();
    if (units && count > 0) {
        _units.assign(units, units + count);
    }
}

- (void)setSprites:(const RenderSpriteInfo*)sprites
             count:(NSUInteger)count
      selectedMask:(const BOOL*)selectedMask {
    _sprites.clear();
    _selectedMask.clear();

    if (sprites && count > 0) {
        _sprites.assign(sprites, sprites + count);
        if (selectedMask) {
            _selectedMask.assign(selectedMask, selectedMask + count);
        } else {
            _selectedMask.resize(count, NO);
        }
    }
}

- (void)setSelectionCircleGRPs:(const void* const*)grps count:(NSUInteger)count {
    _selectionCircleGRPs.clear();
    if (grps && count > 0) {
        for (NSUInteger i = 0; i < count; i++) {
            _selectionCircleGRPs.push_back(static_cast<const bwgame::grp_t*>(grps[i]));
        }
    }
}

- (BOOL)loadSpriteImageData:(NSError**)error {
    if (!_dataLoaderInitialized) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenBWRenderer" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Data loader not initialized"}];
        }
        return NO;
    }

    @try {
        bwgame::a_vector<uint8_t> data;

        // Load tunit.pcx for player colors (128 bytes = 16 players × 8 colors)
        try {
            _dataLoader(data, "game/tunit.pcx");
            // PCX files have a header we need to skip - find the actual palette data
            // tunit.pcx is a simple 128x1 indexed image
            if (data.size() >= 128 + 128) {  // Header + pixel data
                // The PCX format: 128 byte header, then pixel data
                // For a 128x1 image, pixel data starts at offset 128
                size_t data_start = 128;
                for (int player = 0; player < 16; player++) {
                    for (int color = 0; color < 8; color++) {
                        if (data_start + player * 8 + color < data.size()) {
                            _spriteImageData.player_unit_colors[player][color] =
                                data[data_start + player * 8 + color];
                        }
                    }
                }
                NSLog(@"OpenBWRenderer: Loaded player colors from tunit.pcx");
            }
        } catch (...) {
            // Use default player colors if file not found
            NSLog(@"OpenBWRenderer: Could not load tunit.pcx, using defaults");
            // Default colors based on original StarCraft palette
            const uint8_t default_colors[16][8] = {
                {111, 111, 111, 111, 111, 111, 111, 111},  // 0: Red
                {165, 165, 165, 165, 165, 165, 165, 165},  // 1: Blue
                {159, 159, 159, 159, 159, 159, 159, 159},  // 2: Teal
                {164, 164, 164, 164, 164, 164, 164, 164},  // 3: Purple
                {179, 179, 179, 179, 179, 179, 179, 179},  // 4: Orange
                {19,  19,  19,  19,  19,  19,  19,  19 },  // 5: Brown
                {255, 255, 255, 255, 255, 255, 255, 255},  // 6: White
                {135, 135, 135, 135, 135, 135, 135, 135},  // 7: Yellow
                {111, 111, 111, 111, 111, 111, 111, 111},  // 8+: repeat
                {165, 165, 165, 165, 165, 165, 165, 165},
                {159, 159, 159, 159, 159, 159, 159, 159},
                {164, 164, 164, 164, 164, 164, 164, 164},
                {179, 179, 179, 179, 179, 179, 179, 179},
                {19,  19,  19,  19,  19,  19,  19,  19 },
                {255, 255, 255, 255, 255, 255, 255, 255},
                {135, 135, 135, 135, 135, 135, 135, 135},
            };
            for (int p = 0; p < 16; p++) {
                for (int c = 0; c < 8; c++) {
                    _spriteImageData.player_unit_colors[p][c] = default_colors[p][c];
                }
            }
        }

        // Load thpbar.pcx for HP bar colors
        try {
            _dataLoader(data, "game/thpbar.pcx");
            if (data.size() >= 128 + 24) {
                size_t data_start = 128;
                for (int i = 0; i < 24 && data_start + i < data.size(); i++) {
                    _spriteImageData.hp_bar_colors[i] = data[data_start + i];
                }
                NSLog(@"OpenBWRenderer: Loaded HP bar colors from thpbar.pcx");
            }
        } catch (...) {
            NSLog(@"OpenBWRenderer: Could not load thpbar.pcx, using defaults");
            // Default HP bar colors: green (0-2), yellow (3-5), red (6-8), bg (15-17), grid (18)
            _spriteImageData.hp_bar_colors = {
                // Green gradient
                82, 83, 84,
                // Yellow gradient
                135, 136, 137,
                // Red gradient
                111, 112, 113,
                // Unused
                0, 0, 0, 0, 0, 0,
                // Background (dark)
                0, 1, 2,
                // Grid line
                0,
                // Extra
                0, 0, 0, 0, 0
            };
        }

        _spriteImageData.loaded = true;
        return YES;
    }
    @catch (NSException* exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenBWRenderer" code:3
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Failed to load sprite image data: %@",
                                          exception.reason ?: @"Unknown"]}];
        }
        return NO;
    }
}

#pragma mark - Sprite Rendering

- (void)drawImage:(const RenderImageInfo&)image toBuffer:(uint8_t*)fb pitch:(size_t)pitch {
    if (!image.grpFrame) return;

    const auto* frame = static_cast<const bwgame::grp_t::frame_t*>(image.grpFrame);

    int screenX = image.screenX;
    int screenY = image.screenY;

    // Early culling - completely off screen
    if (screenX >= _width || screenY >= _height) return;
    if (screenX + image.frameWidth <= 0 || screenY + image.frameHeight <= 0) return;

    // Calculate clipping
    size_t offset_x = 0, offset_y = 0;
    if (screenX < 0) offset_x = -screenX;
    if (screenY < 0) offset_y = -screenY;

    size_t width = std::min((size_t)image.frameWidth, (size_t)(_width - std::max(0, screenX)));
    size_t height = std::min((size_t)image.frameHeight, (size_t)(_height - std::max(0, screenY)));

    // Get destination pointer
    uint8_t* dst = fb + std::max(0, screenY) * pitch + std::max(0, screenX);

    // Render based on modifier
    if (image.modifier == 10) {
        // Shadow modifier - darken underlying pixels
        ios_renderer::shadow_remap remap;
        ios_renderer::draw_grp_frame(*frame, image.flipped, dst, pitch,
                                     offset_x, offset_y, width, height, remap);
    } else {
        // Normal rendering with player color
        int colorIdx = std::max(0, std::min(15, image.colorIndex));
        ios_renderer::player_color_remap remap{_spriteImageData.player_unit_colors[colorIdx].data()};
        ios_renderer::draw_grp_frame(*frame, image.flipped, dst, pitch,
                                     offset_x, offset_y, width, height, remap);
    }
}

- (void)drawSelectionCircleForSprite:(const RenderSpriteInfo&)sprite
                            toBuffer:(uint8_t*)fb
                               pitch:(size_t)pitch {
    if (sprite.selectionCircleIndex < 0 ||
        sprite.selectionCircleIndex >= (int)_selectionCircleGRPs.size()) {
        return;
    }

    const auto* grp = _selectionCircleGRPs[sprite.selectionCircleIndex];
    if (!grp || grp->frames.empty()) return;

    const auto& frame = grp->frames[0];

    // Calculate screen position (centered on sprite, offset by vpos)
    int screenX = sprite.screenCenterX - (int)grp->width / 2 + (int)frame.offset.x;
    int screenY = sprite.screenCenterY + sprite.selectionCircleVPos - (int)grp->height / 2 + (int)frame.offset.y;

    // Early culling
    if (screenX >= _width || screenY >= _height) return;
    if (screenX + (int)frame.size.x <= 0 || screenY + (int)frame.size.y <= 0) return;

    // Calculate clipping
    size_t offset_x = 0, offset_y = 0;
    if (screenX < 0) offset_x = -screenX;
    if (screenY < 0) offset_y = -screenY;

    size_t width = std::min(frame.size.x, (size_t)(_width - std::max(0, screenX)));
    size_t height = std::min(frame.size.y, (size_t)(_height - std::max(0, screenY)));

    uint8_t* dst = fb + std::max(0, screenY) * pitch + std::max(0, screenX);

    // Get player color for selection circle
    int colorIdx = std::max(0, std::min(15, sprite.owner));
    uint8_t circleColor = _spriteImageData.player_unit_colors[colorIdx][0];

    ios_renderer::selection_circle_remap remap{circleColor};
    ios_renderer::draw_grp_frame(frame, false, dst, pitch,
                                 offset_x, offset_y, width, height, remap);
}

- (void)drawHealthBarsForSprite:(const RenderSpriteInfo&)sprite
                       toBuffer:(uint8_t*)fb
                          pitch:(size_t)pitch {
    if (sprite.healthBarWidth <= 0 || sprite.invincible) return;

    // Calculate bar dimensions
    int barWidth = sprite.healthBarWidth;
    barWidth -= (barWidth - 1) % 3;  // Round to 3-pixel grid
    if (barWidth < 19) barWidth = 19;

    int barHeight = 5;  // HP bar height
    bool hasShields = sprite.maxShields > 0;
    bool hasEnergy = sprite.maxEnergy > 0;

    if (hasShields) barHeight += 2;
    if (hasEnergy) barHeight += 6;

    // Position above selection circle
    int screenX = sprite.screenCenterX - barWidth / 2;
    int screenY = sprite.screenCenterY + sprite.selectionCircleVPos - barHeight - 4;

    // Early culling
    if (screenX >= _width || screenY >= _height) return;
    if (screenX + barWidth <= 0 || screenY + barHeight <= 0) return;

    // Calculate HP percentage
    int hpPercent = sprite.maxHp > 0 ? (sprite.hp * 100 / sprite.maxHp) : 0;
    hpPercent = std::max(0, std::min(100, hpPercent));

    // Calculate filled width (must be multiple of 3)
    auto filledWidth = [&](int percent) -> int {
        int r = percent * barWidth / 100;
        if (r < 3) r = 3;
        else if (r % 3) {
            if (r % 3 > 1) r += 3 - (r % 3);
            else r -= r % 3;
        }
        return std::min(r, barWidth);
    };

    // Color indices from hp_bar_colors
    // Green: 0-2, Yellow: 3-5, Red: 6-8, Dark BG: 15-17, Grid: 18
    auto& colors = _spriteImageData.hp_bar_colors;
    const int* barColors;
    int greenColors[] = {(int)colors[0], (int)colors[1], (int)colors[2]};
    int yellowColors[] = {(int)colors[3], (int)colors[4], (int)colors[5]};
    int redColors[] = {(int)colors[6], (int)colors[7], (int)colors[8]};
    int bgColors[] = {(int)colors[15], (int)colors[16], (int)colors[17]};

    if (hpPercent >= 66) barColors = greenColors;
    else if (hpPercent >= 33) barColors = yellowColors;
    else barColors = redColors;

    int dw = filledWidth(hpPercent);
    int currentY = screenY;

    // Draw HP bar (5 rows)
    for (int row = 0; row < 5; row++) {
        int y = currentY + row;
        if (y < 0 || y >= _height) continue;

        uint8_t* rowPtr = fb + y * pitch;

        // Determine color for this row (gradient)
        int colorIdx = (row == 0 || row == 4) ? 0 : (row == 2 ? 2 : 1);
        uint8_t fillColor = barColors[colorIdx];
        uint8_t bgColor = bgColors[colorIdx];

        for (int x = 0; x < barWidth; x++) {
            int screenPixelX = screenX + x;
            if (screenPixelX < 0 || screenPixelX >= _width) continue;

            rowPtr[screenPixelX] = (x < dw) ? fillColor : bgColor;
        }
    }
    currentY += 5;

    // Draw shield bar if applicable (2 rows above HP)
    if (hasShields && sprite.screenCenterY - barHeight - 6 >= 0) {
        int shieldPercent = sprite.maxShields > 0 ? (sprite.shields * 100 / sprite.maxShields) : 0;
        int sw = filledWidth(shieldPercent);

        // Shield uses blue tones - we'll use palette indices around 165
        for (int row = 0; row < 2; row++) {
            int y = screenY - 2 + row;
            if (y < 0 || y >= _height) continue;

            uint8_t* rowPtr = fb + y * pitch;
            uint8_t fillColor = 165;  // Blue
            uint8_t bgColor = 0;      // Black

            for (int x = 0; x < barWidth; x++) {
                int screenPixelX = screenX + x;
                if (screenPixelX < 0 || screenPixelX >= _width) continue;

                rowPtr[screenPixelX] = (x < sw) ? fillColor : bgColor;
            }
        }
    }

    // Draw grid lines every 3 pixels
    uint8_t gridColor = colors[18];
    for (int x = 0; x < barWidth; x += 3) {
        int screenPixelX = screenX + x;
        if (screenPixelX < 0 || screenPixelX >= _width) continue;

        // Top and bottom grid
        if (screenY >= 0 && screenY < _height) {
            fb[screenY * pitch + screenPixelX] = gridColor;
        }
        if (screenY + 4 >= 0 && screenY + 4 < _height) {
            fb[(screenY + 4) * pitch + screenPixelX] = gridColor;
        }
    }
}

- (void)drawSprite:(const RenderSpriteInfo&)sprite
          selected:(BOOL)isSelected
          toBuffer:(uint8_t*)fb
             pitch:(size_t)pitch {
    bool drewSelectionCircle = false;

    // Draw images in reverse order (back to front)
    for (int i = sprite.imageCount - 1; i >= 0; --i) {
        const RenderImageInfo& image = sprite.images[i];

        // Draw selection circle before first non-shadow image
        if (isSelected && !drewSelectionCircle && image.modifier != 10) {
            [self drawSelectionCircleForSprite:sprite toBuffer:fb pitch:pitch];
            drewSelectionCircle = true;
        }

        [self drawImage:image toBuffer:fb pitch:pitch];
    }

    // Draw health bars for selected units
    if (isSelected) {
        [self drawHealthBarsForSprite:sprite toBuffer:fb pitch:pitch];
    }
}

- (void)drawSprites {
    if (_sprites.empty() || !_spriteImageData.loaded) return;

    uint8_t* fb = _framebuffer.data();
    size_t pitch = _width;

    for (size_t i = 0; i < _sprites.size(); ++i) {
        const RenderSpriteInfo& sprite = _sprites[i];
        BOOL isSelected = (i < _selectedMask.size()) ? _selectedMask[i] : NO;
        [self drawSprite:sprite selected:isSelected toBuffer:fb pitch:pitch];
    }
}

- (void)renderWithCameraX:(float)cameraX
                  cameraY:(float)cameraY
                 mapWidth:(int)mapWidth
                mapHeight:(int)mapHeight {
    if (!self.isReady) {
        [self renderTestPatternWithCameraX:cameraX cameraY:cameraY
                                  mapWidth:mapWidth mapHeight:mapHeight];
        return;
    }

    auto& tileset = _tilesets[_currentTileset];
    uint8_t* fb = _framebuffer.data();

    // Calculate visible tile range
    int startTileX = std::max(0, (int)(cameraX - _width / 2) / 32);
    int startTileY = std::max(0, (int)(cameraY - _height / 2) / 32);
    int endTileX = std::min(mapWidth / 32, (int)(cameraX + _width / 2) / 32 + 1);
    int endTileY = std::min(mapHeight / 32, (int)(cameraY + _height / 2) / 32 + 1);

    int mapTileWidth = _hasMapTiles ? _mapTileWidth : (mapWidth / 32);

    // Clear framebuffer
    [self clear];

    // Render visible tiles
    for (int tileY = startTileY; tileY < endTileY; tileY++) {
        for (int tileX = startTileX; tileX < endTileX; tileX++) {
            // Calculate screen position
            int screenX = tileX * 32 - (int)cameraX + _width / 2;
            int screenY = tileY * 32 - (int)cameraY + _height / 2;

            // Skip if completely off screen
            if (screenX + 32 <= 0 || screenX >= _width) continue;
            if (screenY + 32 <= 0 || screenY >= _height) continue;

            // Calculate megatile index
            // Note: In actual game, this comes from st.tiles_mega_tile_index
            // For now, use a simple repeating pattern based on position
            size_t megatileIndex = 0;
            if (_hasMapTiles && mapTileWidth > 0) {
                size_t tileIndex = static_cast<size_t>(tileX + tileY * mapTileWidth);
                if (tileIndex < _mapTiles.size()) {
                    uint16_t tile = _mapTiles[tileIndex];
                    megatileIndex = static_cast<size_t>(tile & 0x7fff);
                } else {
                    megatileIndex = (tileX + tileY * mapTileWidth) % tileset.vx4.size();
                }
            } else {
                megatileIndex = (tileX + tileY * mapTileWidth) % tileset.vx4.size();
            }

            // Calculate clipping
            int offsetX = std::max(0, -screenX);
            int offsetY = std::max(0, -screenY);
            int drawWidth = std::min(32, _width - screenX);
            int drawHeight = std::min(32, _height - screenY);

            // Get destination pointer
            uint8_t* dst = fb + std::max(0, screenY) * _width + std::max(0, screenX);

            // Draw the tile
            ios_renderer::draw_tile(tileset, megatileIndex, dst, _width,
                                   offsetX, offsetY, drawWidth, drawHeight);
        }
    }

    // Render sprites on top of tiles
    [self drawSprites];
}

- (void)renderTestPatternWithCameraX:(float)cameraX
                             cameraY:(float)cameraY
                            mapWidth:(int)mapWidth
                           mapHeight:(int)mapHeight {
    uint8_t* fb = _framebuffer.data();
    int tileSize = 32;

    for (int y = 0; y < _height; y++) {
        for (int x = 0; x < _width; x++) {
            int worldX = x + (int)cameraX - _width / 2;
            int worldY = y + (int)cameraY - _height / 2;

            // Checkerboard pattern
            int tileX = worldX / tileSize;
            int tileY = worldY / tileSize;
            bool isDark = ((tileX + tileY) % 2) == 0;

            uint8_t color;
            if (worldX < 0 || worldY < 0 || worldX >= mapWidth || worldY >= mapHeight) {
                color = 1;  // Out of bounds - dark
            } else if (isDark) {
                color = 20 + (worldX % 8);  // Green terrain
            } else {
                color = 36 + (worldY % 8);  // Brown terrain
            }

            // Draw a marker in the center
            int centerX = mapWidth / 2;
            int centerY = mapHeight / 2;
            int dx = worldX - centerX;
            int dy = worldY - centerY;
            if (dx * dx + dy * dy < 400) {
                color = 130;  // Player color
            }

            fb[y * _width + x] = color;
        }
    }
}

@end
