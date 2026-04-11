#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct OrbUniforms {
    float time;
    float animation;
    float inputVolume;
    float outputVolume;
    float2 color1;  // packed as (r, g)
    float2 color1b; // packed as (b, 0)
    float2 color2;  // packed as (r, g)
    float2 color2b; // packed as (b, 0)
    float offsets[7];
};

// Simple 2D hash
float2 hash2(float2 p) {
    return fract(sin(float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)))) * 43758.5453);
}

float noise2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float n = mix(
        mix(dot(hash2(i + float2(0, 0)), f - float2(0, 0)),
            dot(hash2(i + float2(1, 0)), f - float2(1, 0)), u.x),
        mix(dot(hash2(i + float2(0, 1)), f - float2(0, 1)),
            dot(hash2(i + float2(1, 1)), f - float2(1, 1)), u.x),
        u.y
    );
    return 0.5 + 0.5 * n;
}

bool drawOval(float2 polarUv, float2 polarCenter, float a, float b, bool reverseGrad, float softness, thread float4 &color) {
    float2 p = polarUv - polarCenter;
    float oval = (p.x * p.x) / (a * a) + (p.y * p.y) / (b * b);
    float edge = smoothstep(1.0, 1.0 - softness, oval);
    if (edge > 0.0) {
        float gradient = reverseGrad ? (1.0 - (p.x / a + 1.0) / 2.0) : ((p.x / a + 1.0) / 2.0);
        gradient = mix(0.5, gradient, 0.1);
        color = float4(float3(gradient), 0.85 * edge);
        return true;
    }
    return false;
}

float3 colorRamp(float grayscale, float3 c1, float3 c2, float3 c3, float3 c4) {
    if (grayscale < 0.33) return mix(c1, c2, grayscale * 3.0);
    else if (grayscale < 0.66) return mix(c2, c3, (grayscale - 0.33) * 3.0);
    else return mix(c3, c4, (grayscale - 0.66) * 3.0);
}

fragment float4 orbFragment(
    VertexOut in [[stage_in]],
    constant OrbUniforms &u [[buffer(0)]],
    texture2d<float> perlinTex [[texture(0)]]
) {
    constexpr sampler s(address::repeat, filter::linear);
    float2 uv = in.uv * 2.0 - 1.0;

    float radius = length(uv);
    float theta = atan2(uv.y, uv.x);
    if (theta < 0.0) theta += 2.0 * M_PI_F;

    float3 decomposed = float3(
        theta / (2.0 * M_PI_F),
        fmod(theta / (2.0 * M_PI_F) + 0.5, 1.0) + 1.0,
        abs(theta / M_PI_F - 1.0)
    );

    // Flow distortion
    float n1 = perlinTex.sample(s, float2(u.animation * -0.2 + radius * 0.03, decomposed.x)).r;
    float n2 = perlinTex.sample(s, float2(u.animation * -0.2 + radius * 0.03, decomposed.y)).r;
    float noise = mix(n1, n2, decomposed.z) - 0.5;
    theta += noise * mix(0.08, 0.25, u.outputVolume);

    float4 color = float4(1.0, 1.0, 1.0, 1.0);

    float centers[7];
    for (int i = 0; i < 7; i++) {
        float orig = float(i) * 0.5 * M_PI_F;
        centers[i] = orig + 0.5 * sin(u.time / 20.0 + u.offsets[i]);
    }

    for (int i = 0; i < 7; i++) {
        float pn = perlinTex.sample(s, float2(fmod(centers[i] + u.time * 0.05, 1.0), 0.5)).r;
        float a = 0.5 + pn * 0.3;
        float b = pn * mix(3.5, 2.5, u.inputVolume);
        bool rev = (i % 2 == 1);

        float distTheta = min(abs(theta - centers[i]),
                             min(abs(theta + 2.0 * M_PI_F - centers[i]),
                                 abs(theta - 2.0 * M_PI_F - centers[i])));

        float4 ovalColor;
        if (drawOval(float2(distTheta, radius), float2(0, 0), a, b, rev, 0.6, ovalColor)) {
            color.rgb = mix(color.rgb, ovalColor.rgb, ovalColor.a);
            color.a = max(color.a, ovalColor.a);
        }
    }

    // Ring effects
    float ringRadius1 = 1.0 + (noise2D(float2(decomposed.x, u.time * 0.1) * 5.0) - 0.5) * 2.5 * 0.3 * 1.5;
    float ringRadius2 = 0.9 + (noise2D(float2(decomposed.x, u.time * 0.1) * 6.0) - 0.5) * 5.0 * 0.2;

    float inputR1 = radius + u.inputVolume * 0.2;
    float inputR2 = radius + u.inputVolume * 0.15;
    float op1 = mix(0.2, 0.6, u.inputVolume);
    float op2 = mix(0.15, 0.45, u.inputVolume);

    float ringAlpha1 = (inputR2 >= ringRadius1) ? op1 : 0.0;
    float ringAlpha2 = smoothstep(ringRadius2 - 0.05, ringRadius2 + 0.05, inputR1) * op2;
    float totalRing = max(ringAlpha1, ringAlpha2);

    color.rgb = 1.0 - (1.0 - color.rgb) * (1.0 - float3(totalRing));

    float3 col1 = float3(u.color1.x, u.color1.y, u.color1b.x);
    float3 col2 = float3(u.color2.x, u.color2.y, u.color2b.x);

    float luminance = color.r;
    color.rgb = colorRamp(luminance, float3(0), col1, col2, float3(1));

    // Circular mask with soft edge
    color.a *= smoothstep(1.0, 0.95, radius);

    return color;
}

vertex VertexOut orbVertex(
    uint vid [[vertex_id]],
    constant float4 *vertices [[buffer(1)]]
) {
    VertexOut out;
    out.position = float4(vertices[vid].xy, 0, 1);
    out.uv = vertices[vid].zw;
    return out;
}
