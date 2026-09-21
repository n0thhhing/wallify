#include <metal_stdlib>
#include "gpu.h"

using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 point;
    float2 uv;
    uint instance_id [[flat]];
};

/// Instanced quad vertex shader.
/// Transforms unit quad coordinates [0, 1] into screen-space points and Normalized Device Coordinates (NDC [-1, 1]).
/// Special command kinds (shadows and rotated glow emitters) adjust their bounding geometry here.
vertex VertexOut vertex_main(uint id [[vertex_id]],
                             uint iid [[instance_id]],
                             constant DrawCommand *commands [[buffer(0)]],
                             constant float2 &viewport [[buffer(1)]]) {
    constant DrawCommand &c = commands[iid];
    float2 uv = float2(id / 2, id % 2);

    float2 origin = float2(c.dx, c.dy);
    float2 size = float2(c.dw, c.dh);

    // Expand quad boundaries to accommodate blurred drop shadow falloff
    if (c.kind == WALLIFY_SHADOW) {
        float blur = max(0.5f, c.parameter);
        float2 offset = float2(c.sx, c.sy);
        origin += offset - float2(blur * 2.0f);
        size += float2(blur * 4.0f);
    }

    float2 point = origin + uv * size;
    float2 position = point;

    // Rotate the quad for dynamic aurora/glow source emitters
    if (c.kind == WALLIFY_GLOW_SOURCE) {
        float2 center = float2(c.dx + c.dw * 0.5f, c.dy + c.dh * 0.5f);
        float2 p = point - center;
        float sine = sin(WALLIFY_GLOW_ROTATION), cosine = cos(WALLIFY_GLOW_ROTATION);
        position = center + float2(cosine * p.x - sine * p.y, sine * p.x + cosine * p.y);
    }

    float2 ndc = position / viewport * 2.0f - 1.0f;
    return {float4(ndc.x, -ndc.y, 0.0f, 1.0f), point, uv, iid};
}

/// Exact 2D Signed Distance Function (SDF) for a rounded rectangle.
/// Returns negative distance inside the shape, 0 at the boundary, and positive distance outside.
float roundedDistance(float2 p, float2 origin, float2 size, float radius) {
    float r = min(radius, min(size.x, size.y) * 0.5f);
    float2 q = abs(p - origin - size * 0.5f) - size * 0.5f + r;
    return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - r;
}

/// Fast branchless RGB <-> HSV conversions for harmonious color space calculations
inline float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0f, -1.0f / 3.0f, 2.0f / 3.0f, -1.0f);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10f;
    return float3(abs(q.z + (q.w - q.y) / (6.0f * d + e)), d / (q.x + e), q.x);
}

inline float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0f, 2.0f / 3.0f, 1.0f / 3.0f, 3.0f);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0f - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0f, 1.0f), c.y);
}

/// Multi-purpose procedural fragment shader.
/// Evaluates rounded SDFs for razor-sharp analytical anti-aliasing (coverage),
/// and renders materials: textures, gradients, physical glass, shadows, fluid auroras, and track transitions.
fragment float4 fragment_main(VertexOut in [[stage_in]],
                              constant DrawCommand *commands [[buffer(0)]],
                              array<texture2d<float>, WALLIFY_MAX_TEXTURES> textures [[texture(0)]]) {
    constant DrawCommand &c = commands[in.instance_id];
    // Most commands are plain rectangles. Avoid the vector length in the
    // rounded-box SDF for those quads; the rounded path is only needed for
    // artwork/cards and other genuinely rounded geometry.
    float distance;
    if (c.radius <= 0.001f) {
        float2 local = in.point - float2(c.dx, c.dy);
        distance = max(max(-local.x, local.x - c.dw), max(-local.y, local.y - c.dh));
    } else {
        distance = roundedDistance(in.point, float2(c.dx, c.dy), float2(c.dw, c.dh), c.radius);
    }

    // Analytical anti-aliasing via screen-space partial derivative (fwidth)
    float aa = max(fwidth(distance), 0.25f);
    float coverage = 1.0f - smoothstep(-aa * 0.5f, aa * 0.5f, distance);

    // Hollow stroke rendering: subtracts the inner perimeter
    if (c.stroke > 0.0f) {
        coverage *= smoothstep(-c.stroke - aa * 0.5f, -c.stroke + aa * 0.5f, distance);
    }

    // Secondary analytical clip rect (e.g. clipping content to the rounded card frame)
    if (c.clip_w > 0.0f) {
        float clip = roundedDistance(in.point, float2(c.clip_x, c.clip_y), float2(c.clip_w, c.clip_h), c.clip_radius);
        coverage *= 1.0f - smoothstep(-aa * 0.5f, aa * 0.5f, clip);
    }

    float4 color = float4(c.r, c.g, c.b, (c.kind == WALLIFY_GLASS) ? c.alpha : 1.0f);
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
        /*
         * Software fallback only.
         *
         * Native macOS 26 Liquid Glass is rendered by
         * NSGlassEffectView and never reaches this path.
         */
        float top_light = max(0.0f, 1.0f - in.uv.y);
        float3 base_rgb = float3(c.r, c.g, c.b);
        base_rgb *= 1.0f + 0.035f * top_light;

        /*
         * Extremely subtle edge definition.
         * This is intentionally nowhere near the native-glass path.
         */
        float edge = 1.0f - smoothstep(
            0.0f, 1.25f, abs(distance + 0.25f)
        );
        float edge_alpha = edge * 0.055f;

        color.rgb = base_rgb;
        color.rgb += float3(1.0f) * edge_alpha;

        /*
         * Very subtle artwork color diffusion.
         */
        if (c.parameter > 0.0f) {
            float2 center = float2(c.dx + c.dw * 0.5f, c.dy + c.dh * 0.5f);
            float d = length(in.point - center);
            float diffusion = exp(-d * 0.008f) * c.parameter;
            color.rgb += float3(c.sx, c.sy, c.sw) * diffusion * 0.20f;
        }
        color.a = c.alpha;
    } else if (c.kind == WALLIFY_SHADOW) {
        float shadow_dist = roundedDistance(in.point - float2(c.sx, c.sy), float2(c.dx, c.dy), float2(c.dw, c.dh), c.radius);
        float blur = max(0.5f, c.parameter);
        coverage = 1.0f - smoothstep(-blur * 0.4f, blur * 1.6f, shadow_dist);
        color = float4(0.0f, 0.0f, 0.0f, 1.0f);
    } else if (c.kind == WALLIFY_AURORA) {
        float2 uv = in.uv;
        float time = c.sh;

        // Aspect-ratio corrected isotropic coordinates centered at (0, 0)
        float aspect = c.dw / max(1.0f, c.dh);
        float2 p = float2((uv.x - 0.5f) * aspect, uv.y - 0.5f);

        // Derive harmonious analogous palette from artwork primary color
        float3 primary = float3(c.r, c.g, c.b);
        float3 hsv = rgb2hsv(primary);
        hsv.y = clamp(hsv.y * 1.15f, 0.45f, 0.95f);
        hsv.z = clamp(hsv.z * 1.10f, 0.40f, 1.00f);

        float3 col1 = hsv2rgb(hsv);
        float3 col2 = hsv2rgb(float3(fract(hsv.x + 0.10f), hsv.y * 0.92f, min(1.0f, hsv.z * 1.08f)));
        float3 col3 = hsv2rgb(float3(fract(hsv.x + 0.20f), hsv.y * 0.80f, min(1.0f, hsv.z * 1.20f)));

        // Three slow-drifting organic light orbs (Apple Music / macOS fluid aurora)
        float t = time * 0.35f;
        float2 c1 = float2(sin(t * 0.70f) * 0.38f * aspect, cos(t * 0.55f) * 0.26f);
        float2 c2 = float2(cos(-t * 0.60f + 1.6f) * 0.44f * aspect, sin(t * 0.75f + 0.6f) * 0.30f);
        float2 c3 = float2(sin(t * 0.50f + 3.14f) * 0.40f * aspect, cos(t * 0.65f + 2.1f) * 0.22f);

        // Organic low-frequency wave perturbation to soften contours
        float wave = sin(p.x * 2.2f + t * 0.8f) * cos(p.y * 2.8f + t * 0.6f) * 0.09f;
        float2 p_warped = p + float2(wave, wave * 0.75f);

        float d1 = length(p_warped - c1);
        float d2 = length(p_warped - c2);
        float d3 = length(p_warped - c3);

        // Smooth Gaussian falloffs
        float w1 = exp(-d1 * d1 * 2.4f);
        float w2 = exp(-d2 * d2 * 1.9f);
        float w3 = exp(-d3 * d3 * 1.7f);

        float total_weight = w1 + w2 + w3 + 0.001f;
        float3 fluid = (col1 * w1 + col2 * w2 + col3 * w3) / total_weight;

        // Subtle ambient radiance across the widget card
        float radiance = clamp(w1 * 0.75f + w2 * 0.70f + w3 * 0.65f + 0.25f, 0.0f, 1.25f);
        fluid *= radiance;

        // Soft radial feathering into card edges to ensure typography & control contrast
        float edge_dist = length(float2((uv.x - 0.5f) * 1.15f, (uv.y - 0.5f) * 1.25f));
        float vignette = smoothstep(1.05f, 0.35f, edge_dist);
        fluid *= vignette;

        // Micro-frosted dither grain to prevent 8-bit banding on dark OLED displays
        float grain = (fract(sin(dot(in.point, float2(12.9898f, 78.233f))) * 43758.5453f) - 0.5f) * 0.012f;
        fluid += grain;

        color = float4(fluid, 1.0f);
    } else if (c.kind == WALLIFY_CINEMATIC) {
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        uint new_idx = min((uint)max(0, c.texture_id), (uint)(WALLIFY_MAX_TEXTURES - 1));
        uint old_idx = min((uint)max(0, (int)c.parameter), (uint)(WALLIFY_MAX_TEXTURES - 1));

        float progress = clamp(c.sx, 0.0f, 1.0f);
        float time = c.sy;
        float2 uv = in.uv;

        float old_scale = 1.0f - progress * 0.06f;
        float new_scale = 1.08f - progress * 0.08f;
        float2 old_uv = clamp((uv - 0.5f) / old_scale + 0.5f, 0.001f, 0.999f);
        float2 new_uv = clamp((uv - 0.5f) / new_scale + 0.5f, 0.001f, 0.999f);

        float flare_curve = sin(progress * 3.14159265f);
        float flare = pow(flare_curve, 2.0f) * 0.35f;

        float wave = sin(uv.y * 8.0f + time * 4.0f) * 0.035f * (1.0f - flare_curve);
        float diagonal = uv.x * 0.65f + uv.y * 0.35f + wave;
        float mask = smoothstep(diagonal - 0.11f, diagonal + 0.11f, progress * 1.22f - 0.11f);

        float edge_band = smoothstep(0.0f, 0.12f, abs(mask - 0.5f));
        float aberration = (1.0f - edge_band) * 0.008f * (1.0f - flare_curve);

        float4 old_sample = textures[old_idx].sample(linearSampler, old_uv);
        float4 new_sample;
        if (aberration > 0.0005f) {
            float r = textures[new_idx].sample(linearSampler, new_uv + float2(aberration, 0.0f)).r;
            float g = textures[new_idx].sample(linearSampler, new_uv).g;
            float b = textures[new_idx].sample(linearSampler, new_uv - float2(aberration, 0.0f)).b;
            float a = textures[new_idx].sample(linearSampler, new_uv).a;
            new_sample = float4(r, g, b, a);
        } else {
            new_sample = textures[new_idx].sample(linearSampler, new_uv);
        }

        float4 blended = mix(old_sample, new_sample, mask);
        float3 bloom_color = mix(float3(c.r, c.g, c.b), float3(1.0f, 0.95f, 0.9f), 0.45f);
        blended.rgb += bloom_color * flare;
        color = blended;
    } else if (c.kind == WALLIFY_RIPPLE) {
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        uint new_idx = min((uint)max(0, c.texture_id), (uint)(WALLIFY_MAX_TEXTURES - 1));
        uint old_idx = min((uint)max(0, (int)c.parameter), (uint)(WALLIFY_MAX_TEXTURES - 1));

        float progress = clamp(c.sx, 0.0f, 1.0f);
        float2 uv = in.uv;
        float2 center_offset = uv - 0.5f;
        float dist = length(center_offset);
        float2 dir = dist > 0.001f ? center_offset / dist : float2(0.0f, 0.0f);

        // Shockwave wavefront propagates from center outward
        float wave_front = progress * 1.05f;
        float diff = dist - wave_front;

        // Concentric ripple oscillation decaying behind the wavefront
        float ripple = sin(diff * 45.0f) * exp(-abs(diff) * 16.0f) * (1.0f - progress * 0.7f);
        float2 displaced_uv = clamp(uv + dir * (ripple * 0.06f), 0.001f, 0.999f);

        // Inside the shockwave ring is the incoming track, outside is the outgoing track
        float mask = 1.0f - smoothstep(-0.06f, 0.06f, diff);

        float4 old_sample = textures[old_idx].sample(linearSampler, displaced_uv);
        float4 new_sample = textures[new_idx].sample(linearSampler, displaced_uv);

        // Specular caustic flash along the crest of the ripple
        float crest = pow(clamp(ripple * 25.0f, 0.0f, 1.0f), 2.0f);
        float3 highlight = mix(float3(1.0f, 1.0f, 1.0f), float3(c.r, c.g, c.b), 0.5f) * (crest * 0.45f);

        float4 blended = mix(old_sample, new_sample, mask);
        blended.rgb += highlight;
        color = blended;
    } else if (c.kind == WALLIFY_FLIP) {
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        uint new_idx = min((uint)max(0, c.texture_id), (uint)(WALLIFY_MAX_TEXTURES - 1));
        uint old_idx = min((uint)max(0, (int)c.parameter), (uint)(WALLIFY_MAX_TEXTURES - 1));

        float progress = clamp(c.sx, 0.0f, 1.0f);
        float2 uv = in.uv;

        float p = progress * progress * (3.0f - 2.0f * progress);
        float angle = p * 3.14159265f;
        bool is_back = angle > 1.5707963f;

        float cos_a = cos(angle);
        float sin_a = sin(angle);

        float x_norm = uv.x - 0.5f;
        float y_norm = uv.y - 0.5f;

        float D = 1.8f;
        float denom = D * cos_a - x_norm * sin_a;
        float x_src = (abs(denom) > 0.001f) ? (x_norm * D / denom) : 0.0f;
        float y_src = y_norm * (1.0f + (x_src * sin_a) / D);

        float2 mapped_uv = float2(x_src + 0.5f, y_src + 0.5f);

        if (mapped_uv.x >= 0.0f && mapped_uv.x <= 1.0f && mapped_uv.y >= 0.0f && mapped_uv.y <= 1.0f) {
            float shadow = clamp(abs(cos_a) * 0.65f + 0.35f, 0.25f, 1.0f);
            if (!is_back) {
                float4 s = textures[old_idx].sample(linearSampler, mapped_uv);
                s.rgb *= shadow;
                color = s;
            } else {
                float2 back_uv = float2(1.0f - mapped_uv.x, mapped_uv.y);
                float4 s = textures[new_idx].sample(linearSampler, back_uv);
                s.rgb *= shadow;
                color = s;
            }
        } else {
            float card_dist = max(abs(mapped_uv.x - 0.5f), abs(mapped_uv.y - 0.5f));
            float shadow_alpha = (1.0f - smoothstep(0.5f, 0.75f, card_dist)) * 0.25f * sin_a;
            color = float4(0.0f, 0.0f, 0.0f, shadow_alpha);
        }
    } else if (c.kind == WALLIFY_VINYL) {
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        uint new_idx = min((uint)max(0, c.texture_id), (uint)(WALLIFY_MAX_TEXTURES - 1));
        uint old_idx = min((uint)max(0, (int)c.parameter), (uint)(WALLIFY_MAX_TEXTURES - 1));

        float progress = clamp(c.sx, 0.0f, 1.0f);
        float2 uv = in.uv;
        float2 rel = uv - 0.5f;
        float r = length(rel);
        float angle = atan2(rel.y, rel.x);

        float spin = (progress * progress * (3.0f - 2.0f * progress)) * 3.14159265f * 2.0f;

        float rot_old = angle + spin;
        float2 uv_old = float2(cos(rot_old) * r + 0.5f, sin(rot_old) * r + 0.5f);

        float rot_new = angle - (3.14159265f * 2.0f - spin);
        float2 uv_new = float2(cos(rot_new) * r + 0.5f, sin(rot_new) * r + 0.5f);

        float mask = smoothstep(0.0f, 1.0f, (progress * 1.5f - (1.0f - r) * 0.5f));

        float4 s_old = (uv_old.x >= 0.0f && uv_old.x <= 1.0f && uv_old.y >= 0.0f && uv_old.y <= 1.0f)
            ? textures[old_idx].sample(linearSampler, uv_old)
            : float4(0.08f, 0.08f, 0.08f, 1.0f);

        float4 s_new = (uv_new.x >= 0.0f && uv_new.x <= 1.0f && uv_new.y >= 0.0f && uv_new.y <= 1.0f)
            ? textures[new_idx].sample(linearSampler, uv_new)
            : float4(0.08f, 0.08f, 0.08f, 1.0f);

        float4 blended = mix(s_old, s_new, clamp(mask, 0.0f, 1.0f));

        float vinyl_phase = angle * 2.0f + spin * 1.5f;
        float vinyl_spec = pow(abs(cos(vinyl_phase)), 18.0f) * 0.35f * sin(progress * 3.14159265f);
        float grooves = (sin(r * 180.0f) * 0.5f + 0.5f) * 0.04f * sin(progress * 3.14159265f);

        blended.rgb += float3(vinyl_spec + grooves);
        color = blended;
    } else if (c.kind == WALLIFY_GLITCH) {
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        uint new_idx = min((uint)max(0, c.texture_id), (uint)(WALLIFY_MAX_TEXTURES - 1));
        uint old_idx = min((uint)max(0, (int)c.parameter), (uint)(WALLIFY_MAX_TEXTURES - 1));

        float progress = clamp(c.sx, 0.0f, 1.0f);
        float time = c.sy;
        float2 uv = in.uv;

        float glitch_intensity = sin(progress * 3.14159265f);

        float slice_y = floor(uv.y * 36.0f);
        float noise = fract(sin(slice_y * 127.1f + floor(time * 24.0f) * 311.7f) * 43758.5453f);

        float x_jitter = 0.0f;
        if (noise > 0.62f) {
            x_jitter = (fract(noise * 23.45f) - 0.5f) * 0.22f * glitch_intensity;
        }

        float split = glitch_intensity * 0.035f * (0.5f + noise * 0.5f);
        float2 uv_r = clamp(uv + float2(x_jitter + split, 0.0f), 0.001f, 0.999f);
        float2 uv_g = clamp(uv + float2(x_jitter, 0.0f), 0.001f, 0.999f);
        float2 uv_b = clamp(uv + float2(x_jitter - split, 0.0f), 0.001f, 0.999f);

        float wipe_threshold = uv.x + (noise - 0.5f) * 0.28f * glitch_intensity;
        float mask = smoothstep(progress - 0.08f, progress + 0.08f, wipe_threshold);

        float r_old = textures[old_idx].sample(linearSampler, uv_r).r;
        float g_old = textures[old_idx].sample(linearSampler, uv_g).g;
        float b_old = textures[old_idx].sample(linearSampler, uv_b).b;

        float r_new = textures[new_idx].sample(linearSampler, uv_r).r;
        float g_new = textures[new_idx].sample(linearSampler, uv_g).g;
        float b_new = textures[new_idx].sample(linearSampler, uv_b).b;

        float3 old_rgb = float3(r_old, g_old, b_old);
        float3 new_rgb = float3(r_new, g_new, b_new);

        float3 blended_rgb = mix(new_rgb, old_rgb, mask);

        float scanline = sin(uv.y * 320.0f) * 0.07f * glitch_intensity;
        blended_rgb -= scanline;

        if (noise > 0.88f) {
            blended_rgb += float3(0.0f, 0.12f, 0.15f) * glitch_intensity;
        }

        color = float4(blended_rgb, 1.0f);
    }

    if (c.kind == WALLIFY_GLASS) {
        return color * coverage;
    }
    return color * (c.alpha * coverage);
}
