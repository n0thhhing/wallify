#include <metal_stdlib>
#include "gpu.h"

using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 point;
    float2 uv;
    uint instance_id [[flat]];
};

vertex VertexOut vertex_main(uint id [[vertex_id]],
                             uint iid [[instance_id]],
                             constant DrawCommand *commands [[buffer(0)]],
                             constant float2 &viewport [[buffer(1)]]) {
    constant DrawCommand &c = commands[iid];
    float2 uv = float2(id / 2, id % 2);

    float2 origin = float2(c.dx, c.dy);
    float2 size = float2(c.dw, c.dh);

    if (c.kind == WALLIFY_SHADOW) {
        float blur = max(0.5f, c.parameter);
        float2 offset = float2(c.sx, c.sy);
        origin += offset - float2(blur * 2.0f);
        size += float2(blur * 4.0f);
    }

    float2 point = origin + uv * size;
    float2 position = point;

    if (c.kind == WALLIFY_GLOW_SOURCE) {
        float2 center = float2(c.dx + c.dw * 0.5f, c.dy + c.dh * 0.5f);
        float2 p = point - center;
        float sine = sin(WALLIFY_GLOW_ROTATION), cosine = cos(WALLIFY_GLOW_ROTATION);
        position = center + float2(cosine * p.x - sine * p.y, sine * p.x + cosine * p.y);
    }

    float2 ndc = position / viewport * 2.0f - 1.0f;
    return {float4(ndc.x, -ndc.y, 0.0f, 1.0f), point, uv, iid};
}

float roundedDistance(float2 p, float2 origin, float2 size, float radius) {
    float r = min(radius, min(size.x, size.y) * 0.5f);
    float2 q = abs(p - origin - size * 0.5f) - size * 0.5f + r;
    return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - r;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant DrawCommand *commands [[buffer(0)]],
                              array<texture2d<float>, WALLIFY_MAX_TEXTURES> textures [[texture(0)]]) {
    constant DrawCommand &c = commands[in.instance_id];
    float distance = roundedDistance(in.point, float2(c.dx, c.dy), float2(c.dw, c.dh), c.radius);
    float aa = max(fwidth(distance), 0.25f);
    float coverage = 1.0f - smoothstep(-aa * 0.5f, aa * 0.5f, distance);

    if (c.stroke > 0.0f) {
        coverage *= smoothstep(-c.stroke - aa * 0.5f, -c.stroke + aa * 0.5f, distance);
    }

    if (c.clip_w > 0.0f) {
        float clip = roundedDistance(in.point, float2(c.clip_x, c.clip_y), float2(c.clip_w, c.clip_h), c.clip_radius);
        coverage *= 1.0f - smoothstep(-aa * 0.5f, aa * 0.5f, clip);
    }

    float4 color = float4(c.r, c.g, c.b, 1.0f);

    if (c.kind == WALLIFY_TEXTURE || c.kind == WALLIFY_GLOW || c.kind == WALLIFY_NEAREST || c.kind == WALLIFY_GLOW_SOURCE) {
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        constexpr sampler pixelSampler(filter::nearest, address::clamp_to_edge);
        float2 uv = float2(c.sx, c.sy) + in.uv * float2(c.sw, c.sh);
        uint tex_idx = min((uint)max(0, c.texture_id), (uint)(WALLIFY_MAX_TEXTURES - 1));
        float4 sample = (c.kind == WALLIFY_NEAREST) ? textures[tex_idx].sample(pixelSampler, uv) : textures[tex_idx].sample(linearSampler, uv);
        color *= sample;

    } else if (c.kind == WALLIFY_GRADIENT) {
        coverage *= mix(c.parameter, 1.0f, smoothstep(0.0f, 1.0f, in.uv.y));

    } else if (c.kind == WALLIFY_GLASS) {
        // Vertical light gradient for depth
        float top_light = max(0.0f, 1.0f - in.uv.y * 1.4f);
        color.rgb *= (1.0f + 0.08f * top_light);

        // Specular inner rim bevel
        float rim = smoothstep(-2.5f, -0.5f, distance) * (1.0f - smoothstep(-0.5f, 0.5f, distance));
        color.rgb += float3(1.0f, 1.0f, 1.0f) * (rim * (0.08f + 0.14f * top_light));

        // Top-edge light reflection
        float top_edge = smoothstep(-1.8f, -0.6f, distance) * smoothstep(0.0f, 1.2f, in.point.y - c.dy);
        color.rgb += float3(1.0f, 1.0f, 1.0f) * (top_edge * 0.15f * top_light);

        // Micro-frosted grain
        float grain = (fract(sin(dot(in.point, float2(12.9898f, 78.233f))) * 43758.5453f) - 0.5f) * 0.012f;
        color.rgb += grain;

        // Ambient artwork color diffusion if parameter > 0
        if (c.parameter > 0.0f) {
            float dist_from_art = length(in.point - float2(c.dx + 82.0f, c.dy + 82.0f));
            float diffusion = exp(-dist_from_art * 0.006f) * c.parameter;
            color.rgb += float3(c.sx, c.sy, c.sw) * diffusion;
        }

    } else if (c.kind == WALLIFY_SHADOW) {
        float shadow_dist = roundedDistance(in.point - float2(c.sx, c.sy), float2(c.dx, c.dy), float2(c.dw, c.dh), c.radius);
        float blur = max(0.5f, c.parameter);
        coverage = 1.0f - smoothstep(-blur * 0.4f, blur * 1.6f, shadow_dist);
        color = float4(0.0f, 0.0f, 0.0f, 1.0f);

    } else if (c.kind == WALLIFY_AURORA) {
        float2 uv = in.uv;
        float time = c.sh;

        // Multi-layered domain-warped undulating waves
        float2 p = uv * 2.6f - 1.3f;
        float wave1 = sin(p.x * 2.2f + time * 0.7f) * cos(p.y * 1.8f + time * 0.5f);
        float wave2 = cos(p.x * 1.5f - time * 0.4f + wave1 * 0.8f) * sin(p.y * 2.4f + time * 0.6f);
        float wave3 = sin((p.x + p.y) * 1.7f + time * 0.8f + wave2 * 1.2f);

        float f1 = smoothstep(-0.8f, 0.9f, wave1);
        float f2 = smoothstep(-0.7f, 0.8f, wave2);
        float f3 = smoothstep(-0.6f, 1.0f, wave3);

        float3 primary = float3(c.r, c.g, c.b);
        float3 secondary = float3(c.sx, c.sy, c.sw);
        float3 accent = float3(primary.g, primary.b, primary.r) * 0.85f;

        float3 fluid = mix(primary, secondary, f1 * 0.65f);
        fluid = mix(fluid, accent, f2 * 0.45f);
        fluid += primary * (f3 * 0.3f);

        // Soft radial falloff towards corners/edges so text and controls remain crisp
        float vignette = 1.0f - length((uv - 0.5f) * 1.1f) * 0.45f;
        fluid *= clamp(vignette, 0.45f, 1.1f);

        // Subtle frosted micro-grain
        float grain = (fract(sin(dot(in.point, float2(12.9898f, 78.233f))) * 43758.5453f) - 0.5f) * 0.015f;
        fluid += grain;

        color = float4(fluid, 1.0f);
    }

    return color * (c.alpha * coverage);
}
