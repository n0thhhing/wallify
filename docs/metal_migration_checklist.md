# Metal Transition Checklist

This checklist breaks down the massive transition from Wallify's CPU-based `PixelEngine` into a purely hardware-accelerated Metal pipeline, allowing us to port features incrementally without breaking the application in the middle.

## Phase 1: Metal Scaffolding
- [x] **Create `shaders.metal`**: Start a new Metal Shader Language file for vertex and fragment shaders.
- [x] **Build System Integration**: Update `build.zig` to use `xcrun metal` and `xcrun metallib` to compile the shaders and bundle `default.metallib` into the `.app`.
- [x] **Render Pipeline Setup**: In `native.m`, initialize a `MTLRenderPipelineState` alongside the existing Command Queue.
- [x] **Data Structures**: Define shared C-structs (in Zig and Objective-C) representing vertices, UV coordinates, and colors to pass geometry buffers across the boundary.

## Phase 2: Hybrid Rendering (CPU + GPU)
- [x] **Quad Rendering**: Implement a basic textured quad shader in Metal. Update `native.m` to accept an array of vertices from Zig instead of a flat pixel buffer.
- [x] **Texture Uploading**: Upload static assets (like Spotify icons and the animated pixel cats) to `MTLTexture` objects during initialization. 
- [ ] **CPU Text Fallback**: Update `CoreText` rendering to draw just the text into small transparent CPU buffers, upload those to Metal textures per-frame, and composite them as quads using the GPU.
- [ ] **Artwork Migration**: Load the `art.bmp` file directly into a `MTLTexture` and let the GPU handle the crossfade blending instead of stepping through bytes on the CPU.

## Phase 3: Porting UI Primitives
- [ ] **Rounded Rectangles**: Port the solid cards and progress bars to a Metal fragment shader using mathematical distances (SDFs) to draw perfect rounded corners without CPU aliasing.
- [ ] **Widget Masking**: Replace `engine.clipOutsideRoundedRect(...)` by utilizing the Metal Stencil Buffer or fragment-discard logic, saving massive amounts of computation.
- [ ] **Glow & Gradients**: Move the ambient lighting bleed from `glow.zig` and the bottom scrim gradient to Metal shader passes.

## Phase 4: Full GPU Migration
- [ ] **Marquee Text**: Implement the scrolling text clip using Metal scissor rects or UV coordinate offsets so the entire view can scroll without recalculating CoreText positions.
- [ ] **Remove CPU Engine**: Safely delete `pixel_engine.zig` as the frontend UI layer will now solely emit vertex buffers to `native.m`.
- [ ] **Refactoring**: Clean up `render.zig` so it acts as a lightweight Scene Graph or Command Builder.
