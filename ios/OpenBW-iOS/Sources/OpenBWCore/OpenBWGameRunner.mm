// OpenBWGameRunner.mm
// Core game runner implementation

#import "OpenBWGameRunner.h"
#import "MetalRenderer.h"
#import "MPQLoader.h"
#import "OpenBWRenderer.h"

// OpenBW headers
#include "bwgame.h"
#include "actions.h"
#include "replay.h"
#include "data_loading.h"

#include <memory>
#include <vector>
#include <string>
#include <fstream>
#include <functional>

// Use OpenBW's UI types for rendering
namespace bwgame {
    // Forward declare what we need from ui.h
    struct tileset_image_data;
    struct image_data;
}

#pragma mark - Data Loading Helpers

// Simple file reader for iOS
static std::vector<uint8_t> loadFileData(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        return {};
    }

    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    std::vector<uint8_t> buffer(size);
    if (!file.read(reinterpret_cast<char*>(buffer.data()), size)) {
        return {};
    }

    return buffer;
}

#pragma mark - OpenBW State Wrapper

// Unit info structure for bridging to Objective-C
struct UnitInfo {
    int unitId;
    int typeId;
    int owner;
    float x;
    float y;
    int health;
    int maxHealth;
    int shields;
    int maxShields;
    bool isSelected;
    bool isCompleted;
};

// Wrapper to hold OpenBW game state with proper initialization
struct OpenBWStateHolder {
    std::unique_ptr<bwgame::game_player> player;
    bwgame::data_loading::data_files_loader<> dataLoader;
    std::string dataPath;
    bool isInitialized = false;

    // Selected units (stored as raw pointers, valid only during frame)
    std::vector<bwgame::unit_t*> selectedUnits;

    // Current player (0 = player 1)
    int currentPlayer = 0;

    bool initialize(const std::string& path) {
        try {
            // Store the data path
            dataPath = path;
            if (!dataPath.empty() && dataPath.back() != '/') {
                dataPath += '/';
            }

            NSLog(@"OpenBW: Initializing from path: %s", dataPath.c_str());

            // Create and initialize the game player
            player = std::make_unique<bwgame::game_player>();
            player->init(dataPath.c_str());

            isInitialized = true;
            NSLog(@"OpenBW: Game player initialized successfully");
            return true;
        }
        catch (const std::exception& e) {
            NSLog(@"OpenBW: Initialization failed: %s", e.what());
            return false;
        }
        catch (...) {
            NSLog(@"OpenBW: Initialization failed with unknown error");
            return false;
        }
    }

    bool loadMap(const std::string& mapPath) {
        if (!player || !isInitialized) {
            NSLog(@"OpenBW: Cannot load map - not initialized");
            return false;
        }

        try {
            NSLog(@"OpenBW: Loading map: %s", mapPath.c_str());
            player->load_map_file(mapPath);
            NSLog(@"OpenBW: Map loaded successfully");
            return true;
        }
        catch (const std::exception& e) {
            NSLog(@"OpenBW: Failed to load map: %s", e.what());
            return false;
        }
        catch (...) {
            NSLog(@"OpenBW: Failed to load map with unknown error");
            return false;
        }
    }

    // Set up a melee game with starting units
    bool setupMeleeGame(int playerRace, int aiRace) {
        if (!player || !isInitialized) {
            NSLog(@"OpenBW: Cannot setup game - not initialized");
            return false;
        }

        try {
            auto& st = player->st();
            auto& funcs = player->funcs();

            // Get race types
            bwgame::race_t humanRace = bwgame::race_t::terran;
            if (playerRace == 1) humanRace = bwgame::race_t::protoss;
            else if (playerRace == 2) humanRace = bwgame::race_t::zerg;

            bwgame::race_t computerRace = bwgame::race_t::zerg;
            if (aiRace == 0) computerRace = bwgame::race_t::terran;
            else if (aiRace == 1) computerRace = bwgame::race_t::protoss;

            NSLog(@"OpenBW: Setting up melee game - Player race: %d, AI race: %d", playerRace, aiRace);

            // Find start locations
            auto* game_st = st.game;
            if (!game_st) {
                NSLog(@"OpenBW: No game state available");
                return false;
            }

            // Get start locations from the map
            std::vector<bwgame::xy> startLocations;
            for (size_t i = 0; i < 8; ++i) {
                if (game_st->start_locations[i] != bwgame::xy()) {
                    startLocations.push_back(game_st->start_locations[i]);
                    NSLog(@"OpenBW: Found start location %zu at (%d, %d)",
                          i, game_st->start_locations[i].x, game_st->start_locations[i].y);
                }
            }

            if (startLocations.size() < 2) {
                NSLog(@"OpenBW: Not enough start locations found (%zu), creating default positions",
                      startLocations.size());
                // Create default start locations
                startLocations.clear();
                startLocations.push_back(bwgame::xy(game_st->map_width / 4, game_st->map_height / 4));
                startLocations.push_back(bwgame::xy(game_st->map_width * 3 / 4, game_st->map_height * 3 / 4));
            }

            // Create starting units for player 0 (human)
            createStartingUnits(0, startLocations[0], humanRace);

            // Create starting units for player 1 (computer)
            createStartingUnits(1, startLocations[1], computerRace);

            // Set player as active
            currentPlayer = 0;

            // Center camera on player's starting location
            // (will be done by the caller)

            NSLog(@"OpenBW: Melee game setup complete");
            return true;
        }
        catch (const std::exception& e) {
            NSLog(@"OpenBW: Failed to setup melee game: %s", e.what());
            return false;
        }
        catch (...) {
            NSLog(@"OpenBW: Failed to setup melee game with unknown error");
            return false;
        }
    }

    // Create starting units at a location for a player
    void createStartingUnits(int owner, bwgame::xy position, bwgame::race_t race) {
        if (!player || !isInitialized) return;

        auto& st = player->st();
        auto& funcs = player->funcs();

        NSLog(@"OpenBW: Creating starting units for player %d at (%d, %d), race %d",
              owner, position.x, position.y, (int)race);

        try {
            // Get unit types based on race
            const bwgame::unit_type_t* mainBuildingType = nullptr;
            const bwgame::unit_type_t* workerType = nullptr;
            const bwgame::unit_type_t* overlordType = nullptr;

            if (race == bwgame::race_t::terran) {
                mainBuildingType = funcs.get_unit_type(bwgame::UnitTypes::Terran_Command_Center);
                workerType = funcs.get_unit_type(bwgame::UnitTypes::Terran_SCV);
            } else if (race == bwgame::race_t::protoss) {
                mainBuildingType = funcs.get_unit_type(bwgame::UnitTypes::Protoss_Nexus);
                workerType = funcs.get_unit_type(bwgame::UnitTypes::Protoss_Probe);
            } else { // Zerg
                mainBuildingType = funcs.get_unit_type(bwgame::UnitTypes::Zerg_Hatchery);
                workerType = funcs.get_unit_type(bwgame::UnitTypes::Zerg_Drone);
                overlordType = funcs.get_unit_type(bwgame::UnitTypes::Zerg_Overlord);
            }

            if (!mainBuildingType || !workerType) {
                NSLog(@"OpenBW: Could not get unit types for race %d", (int)race);
                return;
            }

            // Calculate building position (centered and aligned to grid)
            bwgame::xy buildingPos = position;
            buildingPos.x = (buildingPos.x / 32) * 32 + 16;
            buildingPos.y = (buildingPos.y / 32) * 32 + 16;

            // Create main building
            bwgame::unit_t* mainBuilding = funcs.create_unit(mainBuildingType, buildingPos, owner);
            if (mainBuilding) {
                funcs.finish_building_unit(mainBuilding);
                NSLog(@"OpenBW: Created %s at (%d, %d)",
                      mainBuildingType->id == bwgame::UnitTypes::Terran_Command_Center ? "Command Center" :
                      mainBuildingType->id == bwgame::UnitTypes::Protoss_Nexus ? "Nexus" : "Hatchery",
                      buildingPos.x, buildingPos.y);

                // For Zerg, spread creep
                if (race == bwgame::race_t::zerg) {
                    // Creep spreading is handled automatically by OpenBW
                }
            } else {
                NSLog(@"OpenBW: Failed to create main building");
            }

            // Create overlord for Zerg
            if (overlordType) {
                bwgame::xy overlordPos = position;
                overlordPos.y -= 64;
                bwgame::unit_t* overlord = funcs.create_unit(overlordType, overlordPos, owner);
                if (overlord) {
                    NSLog(@"OpenBW: Created Overlord");
                }
            }

            // Create 4 workers
            for (int i = 0; i < 4; ++i) {
                bwgame::xy workerPos = position;
                // Spread workers around the building
                workerPos.x += (i % 2) * 32 - 16;
                workerPos.y += (i / 2) * 32 - 16 + 48;

                bwgame::unit_t* worker = funcs.create_unit(workerType, workerPos, owner);
                if (worker) {
                    NSLog(@"OpenBW: Created worker %d", i + 1);
                }
            }

            // Set initial resources for the player
            st.current_minerals[owner] = 50;
            st.current_gas[owner] = 0;

        } catch (const std::exception& e) {
            NSLog(@"OpenBW: Error creating starting units: %s", e.what());
        } catch (...) {
            NSLog(@"OpenBW: Unknown error creating starting units");
        }
    }

    void nextFrame() {
        if (player && isInitialized) {
            player->next_frame();
        }
    }

    bwgame::state& getState() {
        return player->st();
    }

    const bwgame::game_state* getGameState() const {
        if (player && isInitialized) {
            return player->st().game;
        }
        return nullptr;
    }

    void reset() {
        player.reset();
        selectedUnits.clear();
        isInitialized = false;
    }

    // Find unit at world position
    bwgame::unit_t* findUnitAtPosition(float worldX, float worldY) {
        if (!player || !isInitialized) return nullptr;

        auto& st = player->st();
        bwgame::xy pos((int)worldX, (int)worldY);

        // Search in a small area around the click point
        int searchRadius = 32;  // Half a tile
        bwgame::rect searchArea;
        searchArea.from = bwgame::xy(pos.x - searchRadius, pos.y - searchRadius);
        searchArea.to = bwgame::xy(pos.x + searchRadius, pos.y + searchRadius);

        bwgame::unit_t* closestUnit = nullptr;
        int closestDist = INT_MAX;

        // Iterate through visible units
        for (bwgame::unit_t* u : bwgame::ptr(st.visible_units)) {
            if (!u->sprite) continue;

            bwgame::xy unitPos = u->sprite->position;

            // Check if unit is in search area
            if (unitPos.x >= searchArea.from.x && unitPos.x <= searchArea.to.x &&
                unitPos.y >= searchArea.from.y && unitPos.y <= searchArea.to.y) {

                int dx = unitPos.x - pos.x;
                int dy = unitPos.y - pos.y;
                int dist = dx * dx + dy * dy;

                if (dist < closestDist) {
                    closestDist = dist;
                    closestUnit = u;
                }
            }
        }

        return closestUnit;
    }

    // Find all units in a rectangle
    std::vector<bwgame::unit_t*> findUnitsInRect(float x1, float y1, float x2, float y2) {
        std::vector<bwgame::unit_t*> result;
        if (!player || !isInitialized) return result;

        auto& st = player->st();

        // Normalize rect
        float minX = std::min(x1, x2);
        float maxX = std::max(x1, x2);
        float minY = std::min(y1, y2);
        float maxY = std::max(y1, y2);

        // Iterate through visible units
        for (bwgame::unit_t* u : bwgame::ptr(st.visible_units)) {
            if (!u->sprite) continue;

            bwgame::xy unitPos = u->sprite->position;

            // Check if unit is in the rectangle
            if (unitPos.x >= minX && unitPos.x <= maxX &&
                unitPos.y >= minY && unitPos.y <= maxY) {
                result.push_back(u);
            }
        }

        return result;
    }

    // Select a single unit
    void selectUnit(bwgame::unit_t* unit) {
        selectedUnits.clear();
        if (unit) {
            selectedUnits.push_back(unit);
            NSLog(@"OpenBW: Selected unit type %d at (%d, %d)",
                  (int)unit->unit_type->id, unit->sprite->position.x, unit->sprite->position.y);
        }
    }

    // Select multiple units
    void selectUnits(const std::vector<bwgame::unit_t*>& units) {
        selectedUnits = units;
        NSLog(@"OpenBW: Selected %zu units", units.size());
    }

    // Clear selection
    void clearSelection() {
        selectedUnits.clear();
    }

    // Issue move command to selected units
    void moveSelectedTo(float worldX, float worldY) {
        if (!player || !isInitialized || selectedUnits.empty()) return;

        bwgame::xy targetPos((int)worldX, (int)worldY);
        auto& funcs = player->funcs();

        for (bwgame::unit_t* u : selectedUnits) {
            if (u && u->owner == currentPlayer) {
                try {
                    // Issue move order through state_functions
                    funcs.set_unit_order(u, funcs.get_order_type(bwgame::Orders::Move), targetPos);
                    NSLog(@"OpenBW: Move command issued to unit at (%d, %d) -> (%d, %d)",
                          u->sprite->position.x, u->sprite->position.y,
                          targetPos.x, targetPos.y);
                }
                catch (...) {
                    NSLog(@"OpenBW: Failed to issue move command");
                }
            }
        }
    }

    // Issue attack-move command to selected units
    void attackMoveTo(float worldX, float worldY) {
        if (!player || !isInitialized || selectedUnits.empty()) return;

        bwgame::xy targetPos((int)worldX, (int)worldY);
        auto& funcs = player->funcs();

        for (bwgame::unit_t* u : selectedUnits) {
            if (u && u->owner == currentPlayer) {
                try {
                    funcs.set_unit_order(u, funcs.get_order_type(bwgame::Orders::AttackMove), targetPos);
                    NSLog(@"OpenBW: Attack-move command issued to unit -> (%d, %d)",
                          targetPos.x, targetPos.y);
                }
                catch (...) {
                    NSLog(@"OpenBW: Failed to issue attack-move command");
                }
            }
        }
    }

    // Issue stop command to selected units
    void stopSelected() {
        if (!player || !isInitialized || selectedUnits.empty()) return;

        auto& funcs = player->funcs();

        for (bwgame::unit_t* u : selectedUnits) {
            if (u && u->owner == currentPlayer) {
                try {
                    funcs.set_unit_order(u, funcs.get_order_type(bwgame::Orders::Stop));
                    NSLog(@"OpenBW: Stop command issued");
                }
                catch (...) {
                    NSLog(@"OpenBW: Failed to issue stop command");
                }
            }
        }
    }

    // Issue hold position command to selected units
    void holdPosition() {
        if (!player || !isInitialized || selectedUnits.empty()) return;

        auto& funcs = player->funcs();

        for (bwgame::unit_t* u : selectedUnits) {
            if (u && u->owner == currentPlayer) {
                try {
                    funcs.set_unit_order(u, funcs.get_order_type(bwgame::Orders::HoldPosition));
                    NSLog(@"OpenBW: Hold position command issued");
                }
                catch (...) {
                    NSLog(@"OpenBW: Failed to issue hold position command");
                }
            }
        }
    }

    // Issue patrol command to selected units
    void patrolTo(float worldX, float worldY) {
        if (!player || !isInitialized || selectedUnits.empty()) return;

        bwgame::xy targetPos((int)worldX, (int)worldY);
        auto& funcs = player->funcs();

        for (bwgame::unit_t* u : selectedUnits) {
            if (u && u->owner == currentPlayer) {
                try {
                    funcs.set_unit_order(u, funcs.get_order_type(bwgame::Orders::Patrol), targetPos);
                    NSLog(@"OpenBW: Patrol command issued to unit -> (%d, %d)",
                          targetPos.x, targetPos.y);
                }
                catch (...) {
                    NSLog(@"OpenBW: Failed to issue patrol command");
                }
            }
        }
    }

    // Get info for all visible units
    std::vector<UnitInfo> getVisibleUnits() {
        std::vector<UnitInfo> result;
        if (!player || !isInitialized) return result;

        auto& st = player->st();
        auto& funcs = player->funcs();

        for (bwgame::unit_t* u : bwgame::ptr(st.visible_units)) {
            if (!u->sprite) continue;

            UnitInfo info;
            info.unitId = (int)(size_t)u;  // Use pointer as ID for now
            info.typeId = (int)u->unit_type->id;
            info.owner = u->owner;
            info.x = (float)u->sprite->position.x;
            info.y = (float)u->sprite->position.y;
            info.health = u->hp.integer_part();
            info.maxHealth = u->unit_type->hitpoints.integer_part();
            info.shields = u->shield_points.integer_part();
            // Shield max comes from shield_points max, not a separate field
            info.maxShields = u->unit_type->hitpoints.integer_part();  // Protoss units have shields = health
            info.isSelected = std::find(selectedUnits.begin(), selectedUnits.end(), u) != selectedUnits.end();
            info.isCompleted = funcs.u_completed(u);

            result.push_back(info);
        }

        return result;
    }

    // Get selected unit count
    size_t getSelectedCount() const {
        return selectedUnits.size();
    }

    // Check if any units are selected
    bool hasSelection() const {
        return !selectedUnits.empty();
    }
};

#pragma mark - Unit Type Names

// Get unit type name from ID
static NSString* getUnitTypeName(int typeId) {
    // Common unit type names
    static NSDictionary* unitNames = @{
        // Terran
        @0: @"Marine",
        @1: @"Ghost",
        @2: @"Vulture",
        @3: @"Goliath",
        @5: @"Siege Tank",
        @7: @"SCV",
        @8: @"Wraith",
        @9: @"Science Vessel",
        @11: @"Dropship",
        @12: @"Battlecruiser",
        @14: @"Nuclear Missile",
        @32: @"Firebat",
        @34: @"Medic",
        // Terran Buildings
        @106: @"Command Center",
        @107: @"Comsat Station",
        @108: @"Nuclear Silo",
        @109: @"Supply Depot",
        @110: @"Refinery",
        @111: @"Barracks",
        @112: @"Academy",
        @113: @"Factory",
        @114: @"Starport",
        @115: @"Control Tower",
        @116: @"Science Facility",
        @117: @"Covert Ops",
        @118: @"Physics Lab",
        @120: @"Machine Shop",
        @122: @"Engineering Bay",
        @123: @"Armory",
        @124: @"Missile Turret",
        @125: @"Bunker",
        // Zerg
        @35: @"Larva",
        @36: @"Egg",
        @37: @"Zergling",
        @38: @"Hydralisk",
        @39: @"Ultralisk",
        @40: @"Broodling",
        @41: @"Drone",
        @42: @"Overlord",
        @43: @"Mutalisk",
        @44: @"Guardian",
        @45: @"Queen",
        @46: @"Defiler",
        @47: @"Scourge",
        @50: @"Infested Terran",
        @62: @"Devourer",
        @103: @"Lurker",
        // Zerg Buildings
        @131: @"Hatchery",
        @132: @"Lair",
        @133: @"Hive",
        @134: @"Nydus Canal",
        @135: @"Hydralisk Den",
        @136: @"Defiler Mound",
        @137: @"Greater Spire",
        @138: @"Queens Nest",
        @139: @"Evolution Chamber",
        @140: @"Ultralisk Cavern",
        @141: @"Spire",
        @142: @"Spawning Pool",
        @143: @"Creep Colony",
        @144: @"Spore Colony",
        @146: @"Sunken Colony",
        @149: @"Extractor",
        // Protoss
        @60: @"Corsair",
        @61: @"Dark Templar",
        @63: @"Dark Archon",
        @64: @"Probe",
        @65: @"Zealot",
        @66: @"Dragoon",
        @67: @"High Templar",
        @68: @"Archon",
        @69: @"Shuttle",
        @70: @"Scout",
        @71: @"Arbiter",
        @72: @"Carrier",
        @73: @"Interceptor",
        @83: @"Reaver",
        @84: @"Observer",
        @85: @"Scarab",
        // Protoss Buildings
        @154: @"Nexus",
        @155: @"Robotics Facility",
        @156: @"Pylon",
        @157: @"Assimilator",
        @159: @"Observatory",
        @160: @"Gateway",
        @162: @"Photon Cannon",
        @163: @"Citadel of Adun",
        @164: @"Cybernetics Core",
        @165: @"Templar Archives",
        @166: @"Forge",
        @167: @"Stargate",
        @169: @"Fleet Beacon",
        @170: @"Arbiter Tribunal",
        @171: @"Robotics Support Bay",
        @172: @"Shield Battery",
        // Resources
        @176: @"Mineral Field",
        @188: @"Vespene Geyser",
    };

    NSNumber* key = @(typeId);
    NSString* name = unitNames[key];
    return name ?: [NSString stringWithFormat:@"Unit %d", typeId];
}

#pragma mark - SelectedUnitInfo Implementation

@implementation SelectedUnitInfo

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
                   canMove:(BOOL)canMove {
    self = [super init];
    if (self) {
        _unitId = unitId;
        _typeId = typeId;
        _typeName = [typeName copy];
        _owner = owner;
        _x = x;
        _y = y;
        _health = health;
        _maxHealth = maxHealth;
        _shields = shields;
        _maxShields = maxShields;
        _energy = energy;
        _maxEnergy = maxEnergy;
        _isBuilding = isBuilding;
        _isWorker = isWorker;
        _canAttack = canAttack;
        _canMove = canMove;
    }
    return self;
}

@end

#pragma mark - OpenBWGameRunner Implementation

@interface OpenBWGameRunner ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, copy) NSString* assetPath;
@end

@implementation OpenBWGameRunner {
    // OpenBW game state holder
    std::unique_ptr<OpenBWStateHolder> _stateHolder;

    // Renderer
    OpenBWRenderer* _renderer;

    // Viewport state
    float _cameraX;
    float _cameraY;
    float _zoomLevel;
    int _viewportWidth;
    int _viewportHeight;

    // Game state
    int _currentFrame;
    int _mapWidth;
    int _mapHeight;
    BOOL _gameRunning;
    BOOL _assetsLoaded;

    // Sprite rendering data
    std::vector<RenderSpriteInfo> _spriteRenderInfos;
    std::vector<RenderImageInfo> _imageRenderInfos;
    std::vector<uint8_t> _selectedMask;  // Use uint8_t instead of BOOL to avoid vector<bool> specialization
    std::vector<std::pair<uint32_t, bwgame::sprite_t*>> _sortedSprites;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _commandQueue = [device newCommandQueue];
        _paused = NO;
        _gameRunning = NO;
        _assetsLoaded = NO;

        _cameraX = 0;
        _cameraY = 0;
        _zoomLevel = 1.0f;
        _viewportWidth = 640;
        _viewportHeight = 480;
        _currentFrame = 0;
        _mapWidth = 0;
        _mapHeight = 0;

        // Initialize state holder
        _stateHolder = std::make_unique<OpenBWStateHolder>();

        // Initialize renderer
        _renderer = [[OpenBWRenderer alloc] initWithWidth:_viewportWidth height:_viewportHeight];

        // Initialize Metal renderer
        if (!MetalRenderer_Initialize(device)) {
            NSLog(@"OpenBWGameRunner: Failed to initialize Metal renderer");
            return nil;
        }

        // Set initial palette
        MetalRenderer_SetPalette(_renderer.palette);
    }
    return self;
}

- (void)dealloc {
    [self stop];
    MetalRenderer_Shutdown();
}

- (BOOL)loadAssetsFromPath:(NSString*)path error:(NSError**)error {
    _assetPath = path;

    // Use MPQLoader to validate and resolve file paths
    MPQLoader* mpqLoader = [MPQLoader shared];
    NSError* loadError = nil;

    if (![mpqLoader loadFromPath:path error:&loadError]) {
        if (error) {
            *error = loadError;
        }
        return NO;
    }

    NSLog(@"OpenBWGameRunner: MPQ files validated at %@", path);

    // Initialize OpenBW global state with the data files
    @try {
        if (!_stateHolder->initialize([path UTF8String])) {
            if (error) {
                *error = [NSError errorWithDomain:@"OpenBW"
                                             code:10
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             @"Failed to initialize OpenBW game engine"}];
            }
            return NO;
        }

        _assetsLoaded = YES;
        NSLog(@"OpenBWGameRunner: OpenBW initialized successfully");

        // Load tileset and image data into the renderer
        NSError* rendererError = nil;
        if ([_renderer loadImageDataFromPath:path error:&rendererError]) {
            NSLog(@"OpenBWGameRunner: Renderer image data loaded");
            // Update Metal renderer with the loaded palette
            MetalRenderer_SetPalette(_renderer.palette);
        } else {
            NSLog(@"OpenBWGameRunner: Could not load renderer image data: %@",
                  rendererError.localizedDescription);
            // Fall back to test palette
            [self loadTestPalette];
        }

        return YES;
    }
    @catch (NSException* exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenBW"
                                         code:11
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"OpenBW initialization exception: %@",
                                          exception.reason ?: @"Unknown"]}];
        }
        return NO;
    }
}

- (void)loadPaletteFromGameData {
    // For now, use the test palette
    // TODO: When OpenBW's UI rendering is connected, load the actual palette
    // from the tileset data that OpenBW provides
    NSLog(@"OpenBWGameRunner: Using test palette (game data palette loading to be implemented)");
    [self loadTestPalette];
}

- (BOOL)startGameWithMap:(NSString*)mapPath
              playerRace:(int)race
            aiDifficulty:(int)difficulty
                   error:(NSError**)error {

    if (!_assetPath || !_assetsLoaded) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenBW"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Assets not loaded"}];
        }
        return NO;
    }

    if (!_stateHolder || !_stateHolder->isInitialized) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenBW"
                                         code:12
                                     userInfo:@{NSLocalizedDescriptionKey: @"OpenBW not initialized"}];
        }
        return NO;
    }

    @try {
        NSString* resolvedMapPath = mapPath;
        NSFileManager* fm = [NSFileManager defaultManager];

        if (mapPath && mapPath.length > 0 && ![mapPath isAbsolutePath]) {
            if (_assetPath.length > 0) {
                NSString* candidate = [_assetPath stringByAppendingPathComponent:mapPath];
                if ([fm fileExistsAtPath:candidate]) {
                    resolvedMapPath = candidate;
                }
            }

            if (resolvedMapPath == mapPath) {
                NSString* bundlePath = [MPQLoader bundleResourcesPath];
                if (bundlePath.length > 0) {
                    NSString* candidate = [bundlePath stringByAppendingPathComponent:mapPath];
                    if ([fm fileExistsAtPath:candidate]) {
                        resolvedMapPath = candidate;
                    }
                }
            }
        }

        NSLog(@"OpenBWGameRunner: Loading map %@", resolvedMapPath);

        bool mapLoaded = false;

        // Try to load the map
        if (resolvedMapPath && resolvedMapPath.length > 0) {
            mapLoaded = _stateHolder->loadMap([resolvedMapPath UTF8String]);
        }

        if (!mapLoaded) {
            // Fall back to test mode with placeholder values
            NSLog(@"OpenBWGameRunner: Could not load map, starting in test mode");
            _mapWidth = 128 * 32;
            _mapHeight = 128 * 32;
        } else {
            // Get actual map dimensions from loaded state
            const bwgame::game_state* gameState = _stateHolder->getGameState();
            if (gameState) {
                _mapWidth = (int)gameState->map_width;
                _mapHeight = (int)gameState->map_height;

                // Configure renderer with map data and tileset
                [_renderer setTilesetIndex:(int)gameState->tileset_index];

                auto& st = _stateHolder->getState();
                [_renderer setMapTiles:st.tiles_mega_tile_index.data()
                                 count:st.tiles_mega_tile_index.size()
                             tileWidth:(int)gameState->map_tile_width
                            tileHeight:(int)gameState->map_tile_height];
                MetalRenderer_SetPalette(_renderer.palette);

                // Set up selection circle GRP pointers for sprite rendering
                [self setupSelectionCircleGRPs];

                // Set up melee game with starting units
                _stateHolder->setupMeleeGame(race, difficulty > 0 ? 2 : 1);  // Use difficulty to pick AI race

                // Find player's starting location for camera
                if (gameState->start_locations[0] != bwgame::xy()) {
                    _cameraX = (float)gameState->start_locations[0].x;
                    _cameraY = (float)gameState->start_locations[0].y;
                    NSLog(@"OpenBWGameRunner: Camera centered on player start at (%.0f, %.0f)", _cameraX, _cameraY);
                }
            } else {
                _mapWidth = 128 * 32;
                _mapHeight = 128 * 32;
            }
        }

        _gameRunning = YES;
        _currentFrame = 0;

        // Only center on map middle if we didn't find a start location
        if (_cameraX == 0 && _cameraY == 0) {
            _cameraX = _mapWidth / 2.0f;
            _cameraY = _mapHeight / 2.0f;
        }

        NSLog(@"OpenBWGameRunner: Game started - Map size: %dx%d", _mapWidth, _mapHeight);

        if (self.onGameEvent) {
            self.onGameEvent(@"game_started", @{
                @"map": resolvedMapPath ?: @"test",
                @"width": @(_mapWidth),
                @"height": @(_mapHeight)
            });
        }

        return YES;
    }
    @catch (NSException* exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenBW"
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown error"}];
        }
        return NO;
    }
}

- (BOOL)loadReplay:(NSString*)replayPath error:(NSError**)error {
    // TODO: Implement replay loading
    if (error) {
        *error = [NSError errorWithDomain:@"OpenBW"
                                     code:4
                                 userInfo:@{NSLocalizedDescriptionKey: @"Replay loading not yet implemented"}];
    }
    return NO;
}

- (void)loadTestPalette {
    // The renderer handles the palette internally
    // Just ensure Metal has the renderer's palette
    MetalRenderer_SetPalette(_renderer.palette);
}

#pragma mark - Sprite Collection

- (uint32_t)spriteDepthOrder:(bwgame::sprite_t*)sprite {
    // Depth calculation matching ui/ui.h sprite_depth_order
    // Higher values = rendered later (on top)
    uint32_t score = 0;
    score |= sprite->elevation_level;
    score <<= 13;
    // Only use Y position for elevation <= 4
    score |= sprite->elevation_level <= 4 ? sprite->position.y : 0;
    score <<= 1;
    // Turrets draw slightly above non-turrets
    score |= (sprite->flags & bwgame::sprite_t::flag_turret) ? 1 : 0;
    return score;
}

- (void)collectVisibleSprites {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    auto& st = _stateHolder->getState();
    auto& global_st = *st.global;

    // Clear previous frame data
    _sortedSprites.clear();
    _spriteRenderInfos.clear();
    _imageRenderInfos.clear();
    _selectedMask.clear();

    // Calculate visible tile range (with margin for large sprites)
    int fromTileY = std::max(0, (int)(_cameraY - _viewportHeight/2) / 32 - 4);
    int toTileY = std::min((int)st.game->map_tile_height,
                          (int)(_cameraY + _viewportHeight/2) / 32 + 5);

    // Collect sprites from tile lines
    for (int y = fromTileY; y < toTileY; ++y) {
        if (y < 0 || y >= (int)st.sprites_on_tile_line.size()) continue;

        for (bwgame::sprite_t* sprite : bwgame::ptr(st.sprites_on_tile_line.at(y))) {
            if (!sprite) continue;
            if (sprite->flags & bwgame::sprite_t::flag_hidden) continue;

            // Calculate depth order
            uint32_t depth = [self spriteDepthOrder:sprite];
            _sortedSprites.emplace_back(depth, sprite);
        }
    }

    // Sort by depth (back to front)
    std::sort(_sortedSprites.begin(), _sortedSprites.end());

    // First pass: count total images to pre-allocate
    size_t totalImages = 0;
    for (size_t i = 0; i < _sortedSprites.size(); ++i) {
        bwgame::sprite_t* sprite = _sortedSprites[i].second;
        if (!sprite) continue;
        for (bwgame::image_t* image : bwgame::ptr(sprite->images)) {
            if (!image) continue;
            if (image->flags & bwgame::image_t::flag_hidden) continue;
            if (!image->grp || image->frame_index >= image->grp->frames.size()) continue;
            totalImages++;
        }
    }

    // Pre-allocate to prevent reallocation (which would invalidate pointers)
    _imageRenderInfos.reserve(totalImages);
    _spriteRenderInfos.reserve(_sortedSprites.size());
    _selectedMask.reserve(_sortedSprites.size());

    // Build render info for each sprite
    for (size_t i = 0; i < _sortedSprites.size(); ++i) {
        bwgame::sprite_t* sprite = _sortedSprites[i].second;
        if (!sprite) continue;
        [self buildSpriteRenderInfo:sprite globalState:global_st state:st];
    }

    // Pass sprites to renderer
    if (!_spriteRenderInfos.empty()) {
        // _selectedMask is uint8_t array which can be safely cast to BOOL*
        [_renderer setSprites:_spriteRenderInfos.data()
                        count:_spriteRenderInfos.size()
                 selectedMask:(const BOOL*)_selectedMask.data()];
    }
}

- (void)buildSpriteRenderInfo:(bwgame::sprite_t*)sprite
                  globalState:(const bwgame::global_state&)global_st
                        state:(bwgame::state&)st {
    if (!sprite) return;

    RenderSpriteInfo spriteInfo = {};

    // Find the unit that owns this sprite (if any)
    bwgame::unit_t* ownerUnit = nullptr;
    for (bwgame::unit_t* u : bwgame::ptr(st.visible_units)) {
        if (!u) continue;
        if (u->sprite == sprite) {
            ownerUnit = u;
            break;
        }
    }

    // Start index for this sprite's images
    size_t imageStartIndex = _imageRenderInfos.size();

    // Collect images for this sprite (in reverse order for proper z-ordering)
    for (bwgame::image_t* image : bwgame::ptr(bwgame::reverse(sprite->images))) {
        if (!image) continue;
        if (image->flags & bwgame::image_t::flag_hidden) continue;
        if (!image->grp) continue;
        if (image->frame_index >= image->grp->frames.size()) continue;

        RenderImageInfo imgInfo = {};

        const auto& frame = image->grp->frames.at(image->frame_index);
        imgInfo.grpFrame = &frame;

        // Calculate screen position
        // Image position = sprite position + image offset - grp center + frame offset
        int mapX = sprite->position.x + image->offset.x - (int)image->grp->width/2 + (int)frame.offset.x;
        int mapY = sprite->position.y + image->offset.y - (int)image->grp->height/2 + (int)frame.offset.y;

        // Convert to screen coordinates
        imgInfo.screenX = mapX - (int)_cameraX + _viewportWidth/2;
        imgInfo.screenY = mapY - (int)_cameraY + _viewportHeight/2;
        imgInfo.frameWidth = (int)frame.size.x;
        imgInfo.frameHeight = (int)frame.size.y;
        imgInfo.flipped = (image->flags & bwgame::image_t::flag_horizontally_flipped) != 0;
        imgInfo.modifier = image->modifier;

        // Get player color index
        int colorIndex = 0;
        if (sprite->owner >= 0 && sprite->owner < (int)st.players.size()) {
            colorIndex = st.players[sprite->owner].color;
        }
        imgInfo.colorIndex = std::max(0, std::min(15, colorIndex));

        _imageRenderInfos.push_back(imgInfo);
    }

    // Set up sprite info
    spriteInfo.images = _imageRenderInfos.data() + imageStartIndex;
    spriteInfo.imageCount = (int)(_imageRenderInfos.size() - imageStartIndex);
    spriteInfo.owner = sprite->owner;

    // Screen center for selection circle
    spriteInfo.screenCenterX = sprite->position.x - (int)_cameraX + _viewportWidth/2;
    spriteInfo.screenCenterY = sprite->position.y - (int)_cameraY + _viewportHeight/2;

    // Selection circle info from sprite type
    if (sprite->sprite_type) {
        spriteInfo.selectionCircleIndex = sprite->sprite_type->selection_circle;
        spriteInfo.selectionCircleVPos = sprite->sprite_type->selection_circle_vpos;
        spriteInfo.healthBarWidth = sprite->sprite_type->health_bar_size;
    } else {
        spriteInfo.selectionCircleIndex = -1;
        spriteInfo.selectionCircleVPos = 0;
        spriteInfo.healthBarWidth = 0;
    }

    // HP/Shield/Energy from owning unit
    if (ownerUnit && ownerUnit->unit_type) {
        spriteInfo.hp = ownerUnit->hp.integer_part();
        spriteInfo.maxHp = ownerUnit->unit_type->hitpoints.integer_part();
        spriteInfo.shields = ownerUnit->shield_points.integer_part();
        // Shield max - check if unit type has shields
        spriteInfo.maxShields = 0; // Will be set properly for Protoss
        spriteInfo.energy = ownerUnit->energy.integer_part();
        spriteInfo.maxEnergy = 200; // Default
        spriteInfo.invincible = (ownerUnit->status_flags & 0x4000000) != 0; // Invincible flag
    } else {
        spriteInfo.hp = 0;
        spriteInfo.maxHp = 0;
        spriteInfo.shields = 0;
        spriteInfo.maxShields = 0;
        spriteInfo.energy = 0;
        spriteInfo.maxEnergy = 0;
        spriteInfo.invincible = false;
    }

    _spriteRenderInfos.push_back(spriteInfo);

    // Check if this sprite belongs to a selected unit
    uint8_t isSelected = 0;
    if (ownerUnit) {
        for (bwgame::unit_t* selectedUnit : _stateHolder->selectedUnits) {
            if (selectedUnit == ownerUnit) {
                isSelected = 1;
                break;
            }
        }
    }
    _selectedMask.push_back(isSelected);
}

- (void)setupSelectionCircleGRPs {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    auto& st = _stateHolder->getState();
    auto& global_st = *st.global;

    // Selection circles are ImageTypes starting from IMAGEID_Selection_Circle_22pixels (561)
    // There are typically 10 different sizes
    std::vector<const void*> grps;

    for (int i = 0; i < 10; ++i) {
        int imageId = 561 + i;  // IMAGEID_Selection_Circle_22pixels + i
        if (imageId < (int)global_st.image_grp.size()) {
            grps.push_back(global_st.image_grp[imageId]);
        } else {
            grps.push_back(nullptr);
        }
    }

    [_renderer setSelectionCircleGRPs:grps.data() count:grps.size()];
}

- (void)tick {
    if (!_gameRunning || _paused) return;

    _currentFrame++;

    // Advance OpenBW game state by one frame (if initialized)
    if (_stateHolder && _stateHolder->isInitialized) {
        try {
            _stateHolder->nextFrame();
        }
        catch (const std::exception& e) {
            NSLog(@"OpenBWGameRunner: Error in game tick: %s", e.what());
        }
        catch (...) {
            // Ignore errors during tick for now
        }

        // Collect visible sprites and pass to renderer
        [self collectVisibleSprites];
    }

    // Render the current frame using OpenBWRenderer
    [_renderer renderWithCameraX:_cameraX cameraY:_cameraY
                        mapWidth:_mapWidth mapHeight:_mapHeight];

    // Upload the rendered framebuffer to Metal
    MetalRenderer_UploadIndexedPixels(_renderer.framebuffer,
                                      _renderer.width, _renderer.height,
                                      _renderer.width);

    // Get actual resource values from game state if available
    int minerals = 50;
    int gas = 0;
    int supply = 4;
    int supplyMax = 10;

    if (_stateHolder && _stateHolder->isInitialized) {
        auto& st = _stateHolder->getState();
        int player = _stateHolder->currentPlayer;

        if (player >= 0 && player < 12) {
            minerals = st.current_minerals[player];
            gas = st.current_gas[player];

            // Get player's race to index supply correctly (0=Terran, 1=Protoss, 2=Zerg)
            int race = 0;  // Default to Terran
            if (st.players.size() > (size_t)player) {
                race = (int)st.players[player].race;
                if (race < 0 || race > 2) race = 0;
            }

            // Supply is stored as fp1 fixed-point, divide by 2 to get actual value
            supply = st.supply_used[player][race].raw_value / 2;
            supplyMax = std::min(st.supply_available[player][race].raw_value / 2, 200);
        }
    }

    // Notify callback
    if (self.onFrameUpdate) {
        self.onFrameUpdate(_currentFrame, minerals, gas, supply, supplyMax);
    }
}

- (void)renderWithEncoder:(id<MTLRenderCommandEncoder>)encoder {
    // The Metal renderer handles the actual draw calls
    // Just update camera position
    MetalRenderer_SetCamera(_cameraX / _mapWidth - 0.5f,
                            _cameraY / _mapHeight - 0.5f,
                            _zoomLevel);
}

- (void)renderToView:(MTKView*)view {
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!drawable) return;

    MTLRenderPassDescriptor* renderPass = view.currentRenderPassDescriptor;
    if (!renderPass) return;

    MetalRenderer_BeginFrame(drawable, renderPass);
    [self renderWithEncoder:nil];  // Encoder managed by renderer
    MetalRenderer_EndFrame();
}

- (void)pause {
    _paused = YES;
}

- (void)resume {
    _paused = NO;
}

- (BOOL)isPaused {
    return _paused;
}

- (void)stop {
    _gameRunning = NO;

    if (_stateHolder) {
        _stateHolder->reset();
    }

    if (self.onGameEvent) {
        self.onGameEvent(@"game_stopped", @{});
    }
}

#pragma mark - Camera Control

- (void)setCameraX:(float)x y:(float)y {
    _cameraX = fmax(0, fmin(x, _mapWidth));
    _cameraY = fmax(0, fmin(y, _mapHeight));
}

- (void)getCameraX:(float*)x y:(float*)y {
    if (x) *x = _cameraX;
    if (y) *y = _cameraY;
}

- (void)setZoom:(float)zoom {
    _zoomLevel = fmax(0.5f, fmin(zoom, 2.0f));
}

- (float)zoom {
    return _zoomLevel;
}

#pragma mark - Coordinate Conversion

- (void)screenToWorld:(CGPoint)screen worldX:(float*)x worldY:(float*)y {
    // Convert screen coordinates to world coordinates
    float wx = screen.x + _cameraX - _viewportWidth / 2.0f;
    float wy = screen.y + _cameraY - _viewportHeight / 2.0f;

    // Apply zoom
    wx = (wx - _cameraX) / _zoomLevel + _cameraX;
    wy = (wy - _cameraY) / _zoomLevel + _cameraY;

    if (x) *x = wx;
    if (y) *y = wy;
}

- (CGPoint)worldToScreen:(float)worldX worldY:(float)worldY {
    float sx = (worldX - _cameraX) * _zoomLevel + _viewportWidth / 2.0f;
    float sy = (worldY - _cameraY) * _zoomLevel + _viewportHeight / 2.0f;
    return CGPointMake(sx, sy);
}

#pragma mark - Game Commands - Selection

- (void)selectUnitAtX:(CGFloat)x y:(CGFloat)y {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    // Convert screen to world coordinates
    float worldX, worldY;
    [self screenToWorld:CGPointMake(x, y) worldX:&worldX worldY:&worldY];

    // Find and select unit at position
    bwgame::unit_t* unit = _stateHolder->findUnitAtPosition(worldX, worldY);
    _stateHolder->selectUnit(unit);

    if (unit) {
        NSLog(@"OpenBWGameRunner: Selected unit type %d owner %d at world (%.0f, %.0f)",
              (int)unit->unit_type->id, unit->owner, worldX, worldY);
    } else {
        NSLog(@"OpenBWGameRunner: No unit found at world (%.0f, %.0f)", worldX, worldY);
    }
}

- (void)selectUnitsInRect:(CGRect)screenRect {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    // Convert screen rect corners to world coordinates
    float worldX1, worldY1, worldX2, worldY2;
    [self screenToWorld:screenRect.origin worldX:&worldX1 worldY:&worldY1];
    CGPoint bottomRight = CGPointMake(CGRectGetMaxX(screenRect), CGRectGetMaxY(screenRect));
    [self screenToWorld:bottomRight worldX:&worldX2 worldY:&worldY2];

    // Find and select all units in rect
    auto units = _stateHolder->findUnitsInRect(worldX1, worldY1, worldX2, worldY2);
    _stateHolder->selectUnits(units);

    NSLog(@"OpenBWGameRunner: Box selected %zu units in world rect (%.0f, %.0f) to (%.0f, %.0f)",
          units.size(), worldX1, worldY1, worldX2, worldY2);
}

- (BOOL)hasSelectedUnits {
    if (!_stateHolder) return NO;
    return _stateHolder->hasSelection();
}

- (NSInteger)selectedUnitCount {
    if (!_stateHolder) return 0;
    return (NSInteger)_stateHolder->getSelectedCount();
}

- (NSArray<SelectedUnitInfo*>*)getSelectedUnitsInfo {
    if (!_stateHolder || !_stateHolder->isInitialized) return nil;
    if (_stateHolder->selectedUnits.empty()) return @[];

    NSMutableArray<SelectedUnitInfo*>* result = [NSMutableArray array];

    for (bwgame::unit_t* u : _stateHolder->selectedUnits) {
        if (!u || !u->sprite || !u->unit_type) continue;

        int typeId = (int)u->unit_type->id;
        NSString* typeName = getUnitTypeName(typeId);

        // Determine unit capabilities
        BOOL isBuilding = (u->unit_type->flags & 0x1) != 0;  // Building flag
        BOOL isWorker = typeId == 7 || typeId == 41 || typeId == 64;  // SCV, Drone, Probe
        BOOL canAttack = u->unit_type->ground_weapon || u->unit_type->air_weapon;
        BOOL canMove = !isBuilding;

        // Get energy (for casters)
        int energy = u->energy.integer_part();
        int maxEnergy = 200;  // Default max energy

        // Get shield info (for Protoss)
        int shields = u->shield_points.integer_part();
        int maxShields = 0;
        // Check if unit has shields (Protoss units)
        if (typeId >= 60 && typeId <= 85 || typeId >= 154 && typeId <= 172) {
            maxShields = u->unit_type->hitpoints.integer_part();  // Approximate
        }

        SelectedUnitInfo* info = [[SelectedUnitInfo alloc]
            initWithId:(int)(size_t)u
                typeId:typeId
              typeName:typeName
                 owner:u->owner
                     x:(float)u->sprite->position.x
                     y:(float)u->sprite->position.y
                health:u->hp.integer_part()
             maxHealth:u->unit_type->hitpoints.integer_part()
               shields:shields
            maxShields:maxShields
                energy:energy
             maxEnergy:maxEnergy
            isBuilding:isBuilding
              isWorker:isWorker
             canAttack:canAttack
               canMove:canMove];

        [result addObject:info];
    }

    return result;
}

#pragma mark - Game Commands - Unit Orders

- (void)moveSelectedToX:(CGFloat)x y:(CGFloat)y {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    // Convert screen to world coordinates
    float worldX, worldY;
    [self screenToWorld:CGPointMake(x, y) worldX:&worldX worldY:&worldY];

    // Issue move command to selected units
    _stateHolder->moveSelectedTo(worldX, worldY);
}

- (void)attackMoveToX:(CGFloat)x y:(CGFloat)y {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    // Convert screen to world coordinates
    float worldX, worldY;
    [self screenToWorld:CGPointMake(x, y) worldX:&worldX worldY:&worldY];

    // Issue attack-move command to selected units
    _stateHolder->attackMoveTo(worldX, worldY);
}

- (void)commandSelectedToPosition:(CGPoint)worldPos rightClick:(BOOL)rightClick {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    if (rightClick) {
        // Right-click: smart command (move or attack based on target)
        // Check if there's an enemy unit at the position
        bwgame::unit_t* targetUnit = _stateHolder->findUnitAtPosition(worldPos.x, worldPos.y);
        if (targetUnit && targetUnit->owner != _stateHolder->currentPlayer) {
            // Attack the enemy unit
            _stateHolder->attackMoveTo(worldPos.x, worldPos.y);
        } else {
            // Move to position
            _stateHolder->moveSelectedTo(worldPos.x, worldPos.y);
        }
    } else {
        // Left-click with pending command
        _stateHolder->moveSelectedTo(worldPos.x, worldPos.y);
    }
}

- (void)issueCommand:(int)commandId targetX:(float)x targetY:(float)y targetUnit:(int)unitId {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    // Convert screen to world coordinates (if needed)
    float worldX, worldY;
    [self screenToWorld:CGPointMake(x, y) worldX:&worldX worldY:&worldY];

    switch (commandId) {
        case 0: // Move
            _stateHolder->moveSelectedTo(worldX, worldY);
            break;
        case 1: // Attack-move
            _stateHolder->attackMoveTo(worldX, worldY);
            break;
        case 2: // Stop
            _stateHolder->stopSelected();
            break;
        case 3: // Hold position
            _stateHolder->holdPosition();
            break;
        case 4: // Patrol
            _stateHolder->patrolTo(worldX, worldY);
            break;
        default:
            NSLog(@"OpenBWGameRunner: Unknown command %d", commandId);
            break;
    }
}

- (void)stopSelected {
    if (_stateHolder && _stateHolder->isInitialized) {
        _stateHolder->stopSelected();
    }
}

- (void)holdPosition {
    if (_stateHolder && _stateHolder->isInitialized) {
        _stateHolder->holdPosition();
    }
}

- (void)patrolToX:(CGFloat)x y:(CGFloat)y {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    float worldX, worldY;
    [self screenToWorld:CGPointMake(x, y) worldX:&worldX worldY:&worldY];
    _stateHolder->patrolTo(worldX, worldY);
}

#pragma mark - Game Commands - Building/Training

- (void)buildStructure:(int)structureTypeId atX:(CGFloat)x y:(CGFloat)y {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    // Convert screen to world coordinates
    float worldX, worldY;
    [self screenToWorld:CGPointMake(x, y) worldX:&worldX worldY:&worldY];

    // TODO: Implement building placement via OpenBW actions
    // This requires a selected worker unit and checking build validity
    NSLog(@"OpenBWGameRunner: Build structure type %d at world (%.0f, %.0f)",
          structureTypeId, worldX, worldY);
}

- (void)trainUnit:(int)unitTypeId {
    if (!_stateHolder || !_stateHolder->isInitialized) return;

    // TODO: Implement unit training via OpenBW actions
    // This requires a selected production building
    NSLog(@"OpenBWGameRunner: Train unit type %d", unitTypeId);
}

#pragma mark - Properties

- (int)currentFrame {
    return _currentFrame;
}

- (int)mapWidth {
    return _mapWidth;
}

- (int)mapHeight {
    return _mapHeight;
}

- (BOOL)isGameRunning {
    return _gameRunning;
}

#pragma mark - Minimap Support

- (CGSize)minimapSize {
    // Calculate minimap size based on map dimensions
    // Map dimensions are in pixels (tile count * 32)
    // We want a reasonable minimap size, typically 128-256 pixels
    int mapTileWidth = _mapWidth / 32;
    int mapTileHeight = _mapHeight / 32;

    // Use 1 pixel per tile, clamped to reasonable size
    int mmWidth = MIN(256, MAX(64, mapTileWidth));
    int mmHeight = MIN(256, MAX(64, mapTileHeight));

    return CGSizeMake(mmWidth, mmHeight);
}

- (uint8_t*)getMinimapRGBA:(int*)outWidth height:(int*)outHeight {
    CGSize mmSize = [self minimapSize];
    int mmWidth = (int)mmSize.width;
    int mmHeight = (int)mmSize.height;

    if (outWidth) *outWidth = mmWidth;
    if (outHeight) *outHeight = mmHeight;

    // Allocate RGBA buffer
    uint8_t* pixels = (uint8_t*)malloc(mmWidth * mmHeight * 4);
    if (!pixels) return NULL;

    // Map tile dimensions
    int mapTileWidth = _mapWidth / 32;
    int mapTileHeight = _mapHeight / 32;

    // Get tileset index for terrain colors
    int tilesetIndex = 0;
    if (_stateHolder && _stateHolder->isInitialized) {
        const bwgame::game_state* gameState = _stateHolder->getGameState();
        if (gameState) {
            tilesetIndex = (int)gameState->tileset_index;
        }
    }

    // Base terrain colors by tileset
    // 0=Badlands, 1=Platform, 2=Installation, 3=Ashworld, 4=Jungle, 5=Desert, 6=Ice, 7=Twilight
    struct TilesetColors {
        uint8_t groundR, groundG, groundB;
        uint8_t highR, highG, highB;
        uint8_t waterR, waterG, waterB;
    };

    static const TilesetColors tilesetColors[] = {
        {139, 119, 101, 101, 67, 33, 50, 50, 120},    // Badlands (brown/tan)
        {80, 80, 100, 60, 60, 80, 40, 40, 60},         // Platform (gray/blue)
        {60, 70, 80, 80, 90, 100, 40, 50, 70},         // Installation (blue-gray)
        {100, 60, 40, 140, 80, 50, 80, 40, 30},        // Ashworld (red/orange)
        {40, 80, 40, 60, 100, 50, 30, 60, 80},         // Jungle (green)
        {160, 140, 100, 180, 160, 120, 100, 80, 60},   // Desert (tan/yellow)
        {180, 200, 220, 220, 240, 255, 100, 140, 180}, // Ice (white/blue)
        {60, 40, 80, 80, 60, 100, 40, 30, 60},         // Twilight (purple)
    };

    int colorIdx = (tilesetIndex >= 0 && tilesetIndex < 8) ? tilesetIndex : 0;
    const TilesetColors& colors = tilesetColors[colorIdx];

    // Fill terrain
    for (int y = 0; y < mmHeight; y++) {
        for (int x = 0; x < mmWidth; x++) {
            // Map minimap pixel to tile
            int tileX = (x * mapTileWidth) / mmWidth;
            int tileY = (y * mapTileHeight) / mmHeight;

            // Get terrain info from tile data if available
            uint8_t r = colors.groundR;
            uint8_t g = colors.groundG;
            uint8_t b = colors.groundB;

            if (_stateHolder && _stateHolder->isInitialized) {
                auto& st = _stateHolder->getState();
                int tileIndex = tileY * mapTileWidth + tileX;

                if (tileIndex >= 0 && tileIndex < (int)st.tiles_mega_tile_index.size()) {
                    uint16_t megatile = st.tiles_mega_tile_index[tileIndex];

                    // Use megatile index to vary color slightly
                    // Low megatiles = ground, high = elevated/special
                    if (megatile > 200) {
                        r = colors.highR;
                        g = colors.highG;
                        b = colors.highB;
                    } else if (megatile < 50) {
                        r = colors.waterR;
                        g = colors.waterG;
                        b = colors.waterB;
                    }

                    // Add some variation based on megatile
                    int variation = (megatile % 20) - 10;
                    r = (uint8_t)MAX(0, MIN(255, (int)r + variation));
                    g = (uint8_t)MAX(0, MIN(255, (int)g + variation));
                    b = (uint8_t)MAX(0, MIN(255, (int)b + variation));
                }
            }

            int idx = (y * mmWidth + x) * 4;
            pixels[idx + 0] = r;
            pixels[idx + 1] = g;
            pixels[idx + 2] = b;
            pixels[idx + 3] = 255;
        }
    }

    // Draw units as colored dots
    if (_stateHolder && _stateHolder->isInitialized) {
        auto units = _stateHolder->getVisibleUnits();

        for (const auto& unit : units) {
            // Convert world position to minimap pixel
            int mmX = (int)((unit.x / _mapWidth) * mmWidth);
            int mmY = (int)((unit.y / _mapHeight) * mmHeight);

            // Clamp to minimap bounds
            mmX = MAX(0, MIN(mmWidth - 1, mmX));
            mmY = MAX(0, MIN(mmHeight - 1, mmY));

            // Color based on owner
            uint8_t unitR, unitG, unitB;
            switch (unit.owner) {
                case 0: unitR = 255; unitG = 0; unitB = 0; break;     // Red
                case 1: unitR = 0; unitG = 0; unitB = 255; break;     // Blue
                case 2: unitR = 0; unitG = 255; unitB = 255; break;   // Teal
                case 3: unitR = 128; unitG = 0; unitB = 128; break;   // Purple
                case 4: unitR = 255; unitG = 165; unitB = 0; break;   // Orange
                case 5: unitR = 139; unitG = 69; unitB = 19; break;   // Brown
                case 6: unitR = 255; unitG = 255; unitB = 255; break; // White
                case 7: unitR = 255; unitG = 255; unitB = 0; break;   // Yellow
                default: unitR = 128; unitG = 128; unitB = 128; break; // Gray (neutral)
            }

            // Draw 2x2 dot for visibility
            for (int dy = 0; dy < 2; dy++) {
                for (int dx = 0; dx < 2; dx++) {
                    int px = mmX + dx;
                    int py = mmY + dy;
                    if (px >= 0 && px < mmWidth && py >= 0 && py < mmHeight) {
                        int idx = (py * mmWidth + px) * 4;
                        pixels[idx + 0] = unitR;
                        pixels[idx + 1] = unitG;
                        pixels[idx + 2] = unitB;
                        pixels[idx + 3] = 255;
                    }
                }
            }
        }
    }

    // Draw camera viewport rectangle (white outline)
    float viewportWorldWidth = _viewportWidth / _zoomLevel;
    float viewportWorldHeight = _viewportHeight / _zoomLevel;

    int camLeft = (int)(((_cameraX - viewportWorldWidth/2) / _mapWidth) * mmWidth);
    int camTop = (int)(((_cameraY - viewportWorldHeight/2) / _mapHeight) * mmHeight);
    int camRight = (int)(((_cameraX + viewportWorldWidth/2) / _mapWidth) * mmWidth);
    int camBottom = (int)(((_cameraY + viewportWorldHeight/2) / _mapHeight) * mmHeight);

    // Clamp to minimap bounds
    camLeft = MAX(0, MIN(mmWidth - 1, camLeft));
    camTop = MAX(0, MIN(mmHeight - 1, camTop));
    camRight = MAX(0, MIN(mmWidth - 1, camRight));
    camBottom = MAX(0, MIN(mmHeight - 1, camBottom));

    // Draw viewport rectangle outline
    for (int x = camLeft; x <= camRight; x++) {
        // Top edge
        if (camTop >= 0 && camTop < mmHeight) {
            int idx = (camTop * mmWidth + x) * 4;
            pixels[idx + 0] = 255;
            pixels[idx + 1] = 255;
            pixels[idx + 2] = 255;
            pixels[idx + 3] = 255;
        }
        // Bottom edge
        if (camBottom >= 0 && camBottom < mmHeight) {
            int idx = (camBottom * mmWidth + x) * 4;
            pixels[idx + 0] = 255;
            pixels[idx + 1] = 255;
            pixels[idx + 2] = 255;
            pixels[idx + 3] = 255;
        }
    }
    for (int y = camTop; y <= camBottom; y++) {
        // Left edge
        if (camLeft >= 0 && camLeft < mmWidth) {
            int idx = (y * mmWidth + camLeft) * 4;
            pixels[idx + 0] = 255;
            pixels[idx + 1] = 255;
            pixels[idx + 2] = 255;
            pixels[idx + 3] = 255;
        }
        // Right edge
        if (camRight >= 0 && camRight < mmWidth) {
            int idx = (y * mmWidth + camRight) * 4;
            pixels[idx + 0] = 255;
            pixels[idx + 1] = 255;
            pixels[idx + 2] = 255;
            pixels[idx + 3] = 255;
        }
    }

    return pixels;
}

@end
