#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position;
    float2 texCoord;
    float4 color;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                             constant VertexIn *v [[buffer(0)]],
                             constant float2 *vp [[buffer(1)]]) {
    VertexOut out;
    float2 ndc = (v[vertexID].position / *vp) * 2.0 - 1.0;
    out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    out.texCoord = v[vertexID].texCoord;
    out.color = v[vertexID].color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
