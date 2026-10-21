# Stock iOS 16.7.16 Metal provider boundary

This is a static selector and discovery map from the locally staged iOS
16.7.16 dyld shared cache. It contains no Apple binary, shader, or IPSW data.
The presence of a selector reference does not establish its boot-time call
order. No custom Metal provider has been loaded on the phone.

## Discovery and registration

`_MTLRegisterDevices` calls `IOServiceMatching("IOAcceleratorES")`.
`_getMetalPluginClassForService` reads the matched service's CFString
`MetalPluginName` and optional `MetalPluginClassName`, loads
`/System/Library/Extensions/<MetalPluginName>.bundle`, and requires a class
derived from private `_MTLDevice`. Metal invokes
`initWithAcceleratorPort:(io_service_t)` on that class. `_MTLAddDevice`
checks `MTLDevice` and `MTLDeviceSPI` conformance, then sends `initLimits`
and `initFeatureQueries` before adding it to the device array.

The private `A5XELTEGPU` class is not an `IOAcceleratorES` subclass. The
restricted `_MTLDevice` subclass in this directory connects to an exact
`A5XELTEGPU` service only and deliberately declares neither Metal protocol.
No bundle manifest or IOAcceleratorES registration is built. This keeps
stock clients on the existing software path until a working render provider
can satisfy their commands. A future integration must provide a true
IOAcceleratorES provider class and set both plugin properties only after the
userland and kernel drawing path is complete and tested.

The local `A5MaliMetalAPI` exercises the public queue/buffer/blit selectors
for a bounded IOSurface BGRA8 copy. It does not claim protocol conformance;
its private candidate render encoder covers only one fixed `read_surf` draw.
Its host test cannot verify
the private `_MTLAddDevice` gate, shader compilation, or on-device submission.
The descriptor inspector recognizes only the candidate `read_surf_vert` and
`read_surf_frag` labels with a single BGRA8Unorm target, no blend/depth,
one sample, and no vertex attributes. Both candidate and rejected descriptors
return an unsupported pipeline error: function labels are not shader binary
identity, and no GPU render job has run through this adapter. The validated
`read_surf` AIR metadata has no Metal vertex-buffer inputs; the Mali position
and point-size buffers are backend tiler outputs, not API bindings.

The 0154 `ReadSurfBGRA` operation reuses selector 6 and 7 request
layouts with operation 4. The current host fixture accepts only 1080×1920
BGRA8 surfaces at stride 4320, one source and one destination, full-surface
rectangles, and kernel-owned UBO fields for level count, dimensions, and
`ColorWriteRule=0x2222`. A distinct Query bit 4 gates the encoder. The private
candidate can record this request against a mock transport; stock
`newRenderPipelineStateWithDescriptor:error:` still returns unsupported.

## QuartzCore selector references and current capability

The staged QuartzCore Objective-C selector references include the following
paths. Signatures are the selectors' ABI names, not inferred argument layouts.

| Surface | Referenced selectors | Current Mali private path |
| --- | --- | --- |
| Device resource creation | `newTextureWithDescriptor:`, `newTextureWithDescriptor:iosurface:plane:`, `newBufferWithLength:options:`, `newBufferWithBytesNoCopy:length:options:deallocator:`, `newHeapWithDescriptor:`, `newSamplerStateWithDescriptor:`, `newDepthStencilStateWithDescriptor:` | Only externally supplied BGRA8 IOSurface import; no general buffer, texture, heap, or sampler allocation |
| Shader/pipeline creation | `newRenderPipelineStateWithDescriptor:error:`, `newRenderPipelineStateWithName:options:reflection:error:`, `newRenderPipelineStateWithTileDescriptor:options:reflection:error:`, `newComputePipelineStateWithFunction:error:`, `newLibraryWithURL:error:` | No stock shader, library, pipeline, or render-state implementation |
| Command encoding | `newCommandQueue`, `commandBuffer`, `renderCommandEncoderWithDescriptor:`, `blitCommandEncoder`, `setRenderPipelineState:`, `setVertexBuffer:offset:atIndex:`, `setFragmentTexture:atIndex:`, `drawPrimitives:vertexStart:vertexCount:`, `copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:`, `commit`, `waitUntilCompleted` | Local public-selector queue/buffer/blit adapter and private bounded read_surf render candidate; no protocol conformance, general vertex buffers, stock pipeline, or general draw |
| Feature queries | `supportsFeatureSet:`, `supportsFamily:`, `supportsMemorylessRenderTargets`, `supportsNativeHardwareFP16`, `supportsSIMDGroup` | No truthful advertised Metal feature profile |

The staged `MTLDeviceSPI` declares 407 instance selectors. The private
`_MTLDevice` base implements many common methods, but static method-list
comparison leaves 42 SPI selectors and 27 public `MTLDevice` selectors
absent from that base. Key missing methods include texture/IOSurface and
buffer creation, sampler and depth-stencil creation, memory limits, and heap
sizing. Declaring protocol conformance without semantics for these would
allow discovery yet fail ordinary QuartzCore work.

The staged QuartzCore `read_surf_vert`/`read_surf_frag` AIR pair has a
fragment Texture0 read and BGRA color attachment in locally generated
translation metadata. That profile also has an out-of-bounds alpha
specialization and sRGB variants. The private 0152 scaled quad cannot be
treated as a general replacement until those semantics and pipeline state
are implemented and pixel-tested.

## Release gate

Do not create the extension bundle manifest, `MetalPluginName` property, or
IOAcceleratorES class while the provider cannot compile the iOS shaders,
allocate their resources, encode their render state and commands, and
retire/fail command buffers correctly. The local restricted class is a link
and client-ABI checkpoint, not a discoverable iOS Metal device.
