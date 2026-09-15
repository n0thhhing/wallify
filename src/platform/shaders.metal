#include <metal_stdlib>
#include "gpu.h"
using namespace metal;
struct VertexOut {
    float4 position [[position]];
    float2 point;
    float2 uv;
};
vertex VertexOut vertex_main(uint id [[vertex_id]], constant DrawCommand &c [[buffer(0)]], constant float2 &viewport [[buffer(1)]]) {
    float2 uv = float2(id / 2, id % 2);
    float2 point = float2(c.dx, c.dy) + uv * float2(c.dw, c.dh);
    float2 position = point;
    if (c.kind == WALLIFY_GLOW_SOURCE) {
        float2 center = float2(c.dx + c.dw * .5, c.dy + c.dh * .5);
        float2 p = point - center;
        float sine = sin(WALLIFY_GLOW_ROTATION), cosine = cos(WALLIFY_GLOW_ROTATION);
        position = center + float2(cosine * p.x - sine * p.y, sine * p.x + cosine * p.y);
    }
    float2 ndc = position / viewport * 2 - 1;
    return {float4(ndc.x, -ndc.y, 0, 1), point, uv};
}
float roundedDistance(float2 p, float2 origin, float2 size, float radius) {
    float r = min(radius, min(size.x, size.y) * .5);
    float2 q = abs(p - origin - size * .5) - size * .5 + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
fragment float4 fragment_main(VertexOut in [[stage_in]], constant DrawCommand &c [[buffer(0)]], texture2d<float> tex [[texture(0)]]) {
    float distance = roundedDistance(in.point, float2(c.dx, c.dy), float2(c.dw, c.dh), c.radius);
    float aa = max(fwidth(distance), .25);
    float coverage = 1 - smoothstep(-aa * .5, aa * .5, distance);
    if (c.stroke > 0) coverage *= smoothstep(-c.stroke - aa * .5, -c.stroke + aa * .5, distance);
    if (c.clip_w > 0) {
        float clip = roundedDistance(in.point, float2(c.clip_x, c.clip_y), float2(c.clip_w, c.clip_h), c.clip_radius);
        coverage *= 1 - smoothstep(-aa * .5, aa * .5, clip);
    }
    float4 color = float4(c.r, c.g, c.b, 1);
    if (c.kind == WALLIFY_TEXTURE || c.kind == WALLIFY_GLOW || c.kind == WALLIFY_NEAREST || c.kind == WALLIFY_GLOW_SOURCE) {
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        constexpr sampler pixelSampler(filter::nearest, address::clamp_to_edge);
        float2 uv = float2(c.sx, c.sy) + in.uv * float2(c.sw, c.sh);
        float4 sample = c.kind == WALLIFY_NEAREST ? tex.sample(pixelSampler, uv) : tex.sample(linearSampler, uv);
        // All cached textures use premultiplied RGBA.
        color *= sample;

    } else if (c.kind == WALLIFY_GRADIENT) {
        coverage *= mix(c.parameter, 1.0, smoothstep(0.0, 1.0, in.uv.y));
    }
    return color * (c.alpha * coverage);
}
