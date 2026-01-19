// MetalRenderer.mm
// Metal-based renderer for OpenBW on iOS

#import "MetalRenderer.h"
#import <Foundation/Foundation.h>

// Metal state
static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_commandQueue = nil;
static id<MTLRenderPipelineState> g_pipelineState = nil;
static id<MTLBuffer> g_vertexBuffer = nil;
static id<MTLBuffer> g_uniformBuffer = nil;

// Textures
static id<MTLTexture> g_paletteTexture = nil;      // 256x1 RGBA palette
static id<MTLTexture> g_indexedTexture = nil;      // Indexed pixel data (8-bit)
static id<MTLTexture> g_framebufferTexture = nil;  // Final RGBA output

// Current frame state
static id<MTLCommandBuffer> g_currentCommandBuffer = nil;
static id<MTLRenderCommandEncoder> g_currentEncoder = nil;
static id<CAMetalDrawable> g_currentDrawable = nil;

// Camera/viewport state
static float g_cameraX = 0.0f;
static float g_cameraY = 0.0f;
static float g_zoomLevel = 1.0f;

// Framebuffer dimensions
static int g_fbWidth = 640;
static int g_fbHeight = 480;

// Metal shader source
static NSString* const kShaderSource = @R"(
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float4 color [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

struct Uniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float time;
    float padding[3];
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 pos = float4(in.position, 0.0, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * pos;
    out.texCoord = in.texCoord;
    out.color = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> indexedTex [[texture(0)]],
                              texture2d<float> paletteTex [[texture(1)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);

    // Sample the indexed texture to get palette index
    float index = indexedTex.sample(s, in.texCoord).r;

    // Look up the color in the palette (256 colors, 1D lookup)
    float2 paletteCoord = float2(index, 0.5);
    float4 color = paletteTex.sample(s, paletteCoord);

    // Apply vertex color (for tinting)
    return color * in.color;
}

// Simple pass-through for direct RGBA rendering
fragment float4 fragment_rgba(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return tex.sample(s, in.texCoord) * in.color;
}
)";

// Helper function to create orthographic projection matrix
static matrix_float4x4 createOrthographicMatrix(float left, float right, float bottom, float top, float near, float far) {
    float ral = right + left;
    float rsl = right - left;
    float tab = top + bottom;
    float tsb = top - bottom;
    float fan = far + near;
    float fsn = far - near;

    return (matrix_float4x4){{
        {2.0f / rsl, 0.0f, 0.0f, 0.0f},
        {0.0f, 2.0f / tsb, 0.0f, 0.0f},
        {0.0f, 0.0f, -2.0f / fsn, 0.0f},
        {-ral / rsl, -tab / tsb, -fan / fsn, 1.0f}
    }};
}

BOOL MetalRenderer_Initialize(id<MTLDevice> device) {
    if (!device) {
        NSLog(@"MetalRenderer: No Metal device provided");
        return NO;
    }

    g_device = device;
    g_commandQueue = [device newCommandQueue];

    // Compile shaders
    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:kShaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"MetalRenderer: Failed to compile shaders: %@", error);
        return NO;
    }

    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];

    // Create vertex descriptor
    MTLVertexDescriptor* vertexDescriptor = [[MTLVertexDescriptor alloc] init];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[0].offset = offsetof(MetalVertex, position);
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
    vertexDescriptor.attributes[1].offset = offsetof(MetalVertex, texCoord);
    vertexDescriptor.attributes[1].bufferIndex = 0;
    vertexDescriptor.attributes[2].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[2].offset = offsetof(MetalVertex, color);
    vertexDescriptor.attributes[2].bufferIndex = 0;
    vertexDescriptor.layouts[0].stride = sizeof(MetalVertex);

    // Create pipeline state
    MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = vertexFunction;
    pipelineDesc.fragmentFunction = fragmentFunction;
    pipelineDesc.vertexDescriptor = vertexDescriptor;
    pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    pipelineDesc.colorAttachments[0].blendingEnabled = YES;
    pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    g_pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    if (!g_pipelineState) {
        NSLog(@"MetalRenderer: Failed to create pipeline state: %@", error);
        return NO;
    }

    // Create buffers
    g_vertexBuffer = [device newBufferWithLength:sizeof(MetalVertex) * 6 options:MTLResourceStorageModeShared];
    g_uniformBuffer = [device newBufferWithLength:sizeof(MetalUniforms) options:MTLResourceStorageModeShared];

    // Create palette texture (256x1 RGBA)
    MTLTextureDescriptor* paletteDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                           width:256
                                                                                          height:1
                                                                                       mipmapped:NO];
    paletteDesc.usage = MTLTextureUsageShaderRead;
    g_paletteTexture = [device newTextureWithDescriptor:paletteDesc];

    // Create indexed texture (will be resized as needed)
    MTLTextureDescriptor* indexedDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                                                            width:g_fbWidth
                                                                                           height:g_fbHeight
                                                                                        mipmapped:NO];
    indexedDesc.usage = MTLTextureUsageShaderRead;
    g_indexedTexture = [device newTextureWithDescriptor:indexedDesc];

    // Create framebuffer texture (final RGBA output)
    MTLTextureDescriptor* fbDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                       width:g_fbWidth
                                                                                      height:g_fbHeight
                                                                                   mipmapped:NO];
    fbDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    g_framebufferTexture = [device newTextureWithDescriptor:fbDesc];

    // Initialize default palette (grayscale)
    uint8_t defaultPalette[256 * 4];
    for (int i = 0; i < 256; i++) {
        defaultPalette[i * 4 + 0] = i;  // R
        defaultPalette[i * 4 + 1] = i;  // G
        defaultPalette[i * 4 + 2] = i;  // B
        defaultPalette[i * 4 + 3] = 255; // A
    }
    MetalRenderer_SetPalette(defaultPalette);

    // Initialize quad vertices (fullscreen)
    MetalVertex* vertices = (MetalVertex*)[g_vertexBuffer contents];
    vertices[0] = {{-1, -1}, {0, 1}, {1, 1, 1, 1}};
    vertices[1] = {{ 1, -1}, {1, 1}, {1, 1, 1, 1}};
    vertices[2] = {{-1,  1}, {0, 0}, {1, 1, 1, 1}};
    vertices[3] = {{ 1, -1}, {1, 1}, {1, 1, 1, 1}};
    vertices[4] = {{ 1,  1}, {1, 0}, {1, 1, 1, 1}};
    vertices[5] = {{-1,  1}, {0, 0}, {1, 1, 1, 1}};

    NSLog(@"MetalRenderer: Initialized successfully");
    return YES;
}

void MetalRenderer_Shutdown(void) {
    g_framebufferTexture = nil;
    g_indexedTexture = nil;
    g_paletteTexture = nil;
    g_uniformBuffer = nil;
    g_vertexBuffer = nil;
    g_pipelineState = nil;
    g_commandQueue = nil;
    g_device = nil;

    NSLog(@"MetalRenderer: Shut down");
}

void MetalRenderer_BeginFrame(id<CAMetalDrawable> drawable, MTLRenderPassDescriptor* renderPassDescriptor) {
    g_currentDrawable = drawable;
    g_currentCommandBuffer = [g_commandQueue commandBuffer];

    // Update uniforms
    MetalUniforms* uniforms = (MetalUniforms*)[g_uniformBuffer contents];
    uniforms->projectionMatrix = createOrthographicMatrix(-1, 1, -1, 1, -1, 1);
    uniforms->viewMatrix = matrix_identity_float4x4;
    uniforms->time = 0.0f;

    // Begin encoding
    g_currentEncoder = [g_currentCommandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [g_currentEncoder setRenderPipelineState:g_pipelineState];
    [g_currentEncoder setVertexBuffer:g_vertexBuffer offset:0 atIndex:0];
    [g_currentEncoder setVertexBuffer:g_uniformBuffer offset:0 atIndex:1];
    [g_currentEncoder setFragmentTexture:g_indexedTexture atIndex:0];
    [g_currentEncoder setFragmentTexture:g_paletteTexture atIndex:1];
}

void MetalRenderer_EndFrame(void) {
    if (g_currentEncoder) {
        // Draw the fullscreen quad
        [g_currentEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        [g_currentEncoder endEncoding];
        g_currentEncoder = nil;
    }

    if (g_currentCommandBuffer && g_currentDrawable) {
        [g_currentCommandBuffer presentDrawable:g_currentDrawable];
        [g_currentCommandBuffer commit];
        g_currentCommandBuffer = nil;
        g_currentDrawable = nil;
    }
}

void MetalRenderer_SetPalette(const uint8_t* colors) {
    if (!g_paletteTexture || !colors) return;

    MTLRegion region = MTLRegionMake2D(0, 0, 256, 1);
    [g_paletteTexture replaceRegion:region mipmapLevel:0 withBytes:colors bytesPerRow:256 * 4];
}

void MetalRenderer_UploadIndexedPixels(const uint8_t* data, int width, int height, int pitch) {
    if (!g_indexedTexture || !data) return;

    // Recreate texture if size changed
    if (width != g_fbWidth || height != g_fbHeight) {
        g_fbWidth = width;
        g_fbHeight = height;

        MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                                                         width:width
                                                                                        height:height
                                                                                     mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead;
        g_indexedTexture = [g_device newTextureWithDescriptor:desc];
    }

    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [g_indexedTexture replaceRegion:region mipmapLevel:0 withBytes:data bytesPerRow:pitch];
}

void MetalRenderer_SetCamera(float x, float y, float zoom) {
    g_cameraX = x;
    g_cameraY = y;
    g_zoomLevel = zoom;

    // Update view matrix in uniforms
    if (g_uniformBuffer) {
        MetalUniforms* uniforms = (MetalUniforms*)[g_uniformBuffer contents];

        // Create view matrix with camera offset and zoom
        // Scale is applied independently of translation to avoid double-zoom effect
        matrix_float4x4 view = matrix_identity_float4x4;
        view.columns[0][0] = zoom;        // Scale X
        view.columns[1][1] = zoom;        // Scale Y
        view.columns[3][0] = -x;          // Translate X (no zoom multiplier)
        view.columns[3][1] = -y;          // Translate Y (no zoom multiplier)

        uniforms->viewMatrix = view;
    }
}

id<MTLTexture> MetalRenderer_GetFramebufferTexture(void) {
    return g_framebufferTexture;
}
