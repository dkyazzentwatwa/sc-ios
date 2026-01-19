// MetalRenderer.h
// Metal-based renderer for OpenBW on iOS

#ifndef MetalRenderer_h
#define MetalRenderer_h

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Vertex structure for sprite rendering
typedef struct {
    vector_float2 position;
    vector_float2 texCoord;
    vector_float4 color;
} MetalVertex;

/// Uniform data passed to shaders
typedef struct {
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    float time;
    float padding[3];
} MetalUniforms;

/// Initialize the Metal renderer with a device
/// @param device The Metal device to use
/// @return YES if initialization succeeded
BOOL MetalRenderer_Initialize(id<MTLDevice> device);

/// Shut down the renderer and release resources
void MetalRenderer_Shutdown(void);

/// Begin a new frame
/// @param drawable The drawable to render to
/// @param renderPassDescriptor The render pass descriptor
void MetalRenderer_BeginFrame(id<CAMetalDrawable> drawable, MTLRenderPassDescriptor* renderPassDescriptor);

/// End the current frame and present
void MetalRenderer_EndFrame(void);

/// Update the palette (256 RGBA colors)
/// @param colors Array of 256 * 4 bytes (RGBA)
void MetalRenderer_SetPalette(const uint8_t* colors);

/// Upload indexed pixel data to the framebuffer texture
/// @param data 8-bit indexed pixel data
/// @param width Width of the image
/// @param height Height of the image
/// @param pitch Bytes per row
void MetalRenderer_UploadIndexedPixels(const uint8_t* data, int width, int height, int pitch);

/// Set the viewport/camera position
/// @param x Camera X position
/// @param y Camera Y position
/// @param zoom Zoom level (1.0 = normal)
void MetalRenderer_SetCamera(float x, float y, float zoom);

/// Get the current framebuffer texture for SwiftUI integration
id<MTLTexture> MetalRenderer_GetFramebufferTexture(void);

#ifdef __cplusplus
}
#endif

#endif /* MetalRenderer_h */
