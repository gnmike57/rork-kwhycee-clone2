#include <metal_stdlib>
using namespace metal;

struct WarpVertex {
    float2 position;
    float2 uv;
    float shade;
    float mouth;
};

struct WarpOut {
    float4 position [[position]];
    float2 uv;
    float shade;
    float mouth;
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
    return out;
}

fragment float4 stillWarpFragment(WarpOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  constant float3 &dark [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 photo = tex.sample(s, in.uv);
    float3 color = mix(photo.rgb, dark, saturate(in.mouth));
    color *= 1.0 - saturate(in.shade) * 0.78;
    return float4(color, 1.0);
}
