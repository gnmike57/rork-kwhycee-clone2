#include <metal_stdlib>
using namespace metal;

struct WarpVertex {
    float2 position;
    float2 uv;
    float shade;
    float mouth;
    float skin;
};

struct WarpOut {
    float4 position [[position]];
    float2 uv;
    float shade;
    float mouth;
    float skin;
};

/// Mirrors WarpUniforms in StillRenderer.swift — keep both in step.
struct WarpUniforms {
    float smile;
    float squint;
    float pulse;
    float scale;
    float2 mouthLeft;
    float2 mouthRight;
    float2 upperLip;
    float2 leftEyeOuter;
    float2 rightEyeOuter;
};

vertex WarpOut stillWarpVertex(uint id [[vertex_id]],
                               constant WarpVertex *verts [[buffer(0)]],
                               constant float2 &size [[buffer(1)]]) {
    WarpVertex v = verts[id];
    float2 clip = float2(v.position.x / size.x * 2.0 - 1.0, 1.0 - v.position.y / size.y * 2.0);
    WarpOut out;
    out.position = float4(clip, 0.0, 1.0);
    out.uv = v.uv;
    out.shade = v.shade;
    out.mouth = v.mouth;
    out.skin = v.skin;
    return out;
}

/// A soft, slightly broken crease band along a segment; fades at both ends.
static float foldBand(float2 p, float2 a, float2 b, float scale, float amount) {
    float2 ab = b - a;
    float denom = max(dot(ab, ab), 1e-9);
    float t = saturate(dot(p - a, ab) / denom);
    float d = length(p - (a + ab * t));
    float w = 0.016 * scale * (0.6 + 0.5 * sin(t * 3.14159));
    float band = exp(-d * d / (w * w + 1e-9) * 1.8);
    float crease = 0.7 + 0.3 * sin(t * 47.0 + d * 90.0);
    float ends = smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.82, 1.0, t));
    return band * crease * ends * amount;
}

/// Radiating creases outside an eye corner, fading with distance.
static float crowFeet(float2 p, float2 outer, float scale) {
    float2 d = p - outer;
    float r2 = dot(d, d);
    float reach = 0.14 * scale;
    if (r2 > reach * reach) return 0.0;
    float ang = atan2(d.y, d.x);
    float creases = pow(saturate(sin(ang * 4.5 + 0.6)), 2.0);
    float w = 0.075 * scale;
    float falloff = exp(-r2 / (w * w) * 1.4);
    return creases * falloff;
}

/// A soft round patch on the skin.
static float cheekPatch(float2 p, float2 cheek, float scale, float tightness) {
    float2 d = p - cheek;
    return exp(-dot(d, d) / (scale * scale * tightness + 1e-9));
}

fragment float4 stillWarpFragment(WarpOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  constant float3 &dark [[buffer(0)]],
                                  constant WarpUniforms &u [[buffer(1)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 photo = tex.sample(s, in.uv);
    float3 color = mix(photo.rgb, dark, saturate(in.mouth));
    color *= 1.0 - saturate(in.shade) * 0.78;

    float skin = saturate(in.skin);

    // Smile shading: nasolabial folds, crow's feet, lifted cheek apples.
    if (u.smile > 0.02 && skin > 0.002) {
        float2 wingL = float2(mix(u.upperLip.x, u.mouthLeft.x, 0.5), u.upperLip.y - 0.05 * u.scale);
        float2 endL = u.mouthLeft + float2(-0.03 * u.scale, 0.02 * u.scale);
        float2 wingR = float2(mix(u.upperLip.x, u.mouthRight.x, 0.5), u.upperLip.y - 0.05 * u.scale);
        float2 endR = u.mouthRight + float2(0.03 * u.scale, 0.02 * u.scale);
        float fold = foldBand(in.uv, wingL, endL, u.scale, u.smile * 0.26)
                   + foldBand(in.uv, wingR, endR, u.scale, u.smile * 0.26);
        float feet = (crowFeet(in.uv, u.leftEyeOuter, u.scale)
                    + crowFeet(in.uv, u.rightEyeOuter, u.scale))
                   * saturate(u.squint + 0.45 * u.smile) * 0.20;
        color *= 1.0 - saturate(fold + feet) * skin;

        float2 cheekL = (u.mouthLeft + u.leftEyeOuter) * 0.5;
        float2 cheekR = (u.mouthRight + u.rightEyeOuter) * 0.5;
        float apple = cheekPatch(in.uv, cheekL, u.scale, 0.012)
                    + cheekPatch(in.uv, cheekR, u.scale, 0.012);
        color *= 1.0 + saturate(apple) * u.smile * 0.05 * skin;
    }

    // rPPG: the heartbeat and breath ride the skin, red-biased like real
    // blood perfusion, and a smile flushes the cheeks a little more.
    if (skin > 0.002) {
        float flush = u.smile * 0.05 * (cheekPatch(in.uv, (u.mouthLeft + u.leftEyeOuter) * 0.5, u.scale, 0.02)
                                      + cheekPatch(in.uv, (u.mouthRight + u.rightEyeOuter) * 0.5, u.scale, 0.02));
        float blood = u.pulse * 0.011 + saturate(flush);
        color *= float3(1.0 + blood * 0.85, 1.0 - blood * 0.25, 1.0 - blood * 0.45);
    }

    return float4(color, 1.0);
}
