#version 450

layout(location = 0) in vec2 in_uv;
layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform sampler2D hdr;
layout(set = 0, binding = 1) uniform sampler2D bloom;  // all levels: 0 sharp, 1 holds the upsampled 1..4
layout(push_constant) uniform Push {
    float exposure;  // 2^EV
    float bloom_mix;
    float bloom_scale;  // 1 / summed bloom levels
    uint fxaa;  // 1: FXAA in this pass on the tonemapped neighbours
} pc;

// AgX inset, log2 encoding over [-12.47393, 4.026069] EV and outset (Sobotka; minimal form by Wrensch).
const mat3 kInset = mat3(0.842479062253094, 0.0423282422610123, 0.0423756549057051,
                         0.0784335999999992, 0.878468636469772, 0.0784336,
                         0.0792237451477643, 0.0791661274605434, 0.879142973793104);
const mat3 kOutset = mat3(1.19687900512017, -0.0528968517574562, -0.0529716355144438,
                          -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
                          -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
const float kMinEv = -12.47393;
const float kMaxEv = 4.026069;

// Sigmoid fitted to Blender 5.2 "AgX" + "AgX - Medium High Contrast" on a grey ramp (sRGB-encoded out).
vec3 contrast(vec3 x) {
    return (((((45.7297 * x - 128.345) * x + 125.225) * x - 49.7831) * x + 8.77823) * x - 0.591192) * x + 0.00868597;
}

vec3 agx(vec3 linear) {
    vec3 v = clamp(log2(max(kInset * linear, 1e-10)), kMinEv, kMaxEv);
    v = contrast((v - kMinEv) / (kMaxEv - kMinEv));
    return clamp(kOutset * v, 0.0, 1.0);
}

vec3 glow_at(vec2 uv) { return (textureLod(bloom, uv, 0.0).rgb + textureLod(bloom, uv, 1.0).rgb) * pc.bloom_scale; }

vec3 tonemap(vec3 color, vec3 glow) { return agx(mix(color, glow, pc.bloom_mix) * pc.exposure); }

vec3 tonemap(vec2 uv) { return tonemap(texture(hdr, uv).rgb, glow_at(uv)); }

// FXAA 3.11 (Lottes) quality preset 12 (subpix 0.75, edge threshold 0.166, min 0.0833) in the tonemap pass.
// Neighbour luma takes the HDR texel with the centre's glow (bloom is smooth over the 20 px walk);
// walk samples tonemap the bilinear HDR, so lumaNN is sampled the same way at the edge midpoint.
// The final bilinear fetch, (1 - o) * M + o * neighbour, mixes the neighbour's full tonemap at o.
const float kSteps[5] = float[](1.0, 1.5, 2.0, 4.0, 12.0);

// Edge luma: the AgX curve on the pre-tonemap luminance (one log2 + polynomial, not three channels).
float luma_of(vec3 color, vec3 glow) {
    const float l = dot(mix(color, glow, pc.bloom_mix) * pc.exposure, vec3(0.2126, 0.7152, 0.0722));
    const float x = (clamp(log2(max(l, 1e-10)), kMinEv, kMaxEv) - kMinEv) / (kMaxEv - kMinEv);
    return clamp((((((45.7297 * x - 128.345) * x + 125.225) * x - 49.7831) * x + 8.77823) * x - 0.591192) * x + 0.00868597,
                 0.0, 1.0);
}

float luma_at(vec2 uv, vec3 glow) { return luma_of(textureLod(hdr, uv, 0.0).rgb, glow); }

vec3 fxaa(vec2 pos, vec3 colorM, vec3 glow) {
    const vec2 rcp = 1.0 / vec2(textureSize(hdr, 0));
    // 3.11's GATHER4 footprints per channel: SE quad (S, SE, E, M), NW quad (W, M, N, NW).
    const vec4 rSE = textureGather(hdr, pos, 0), gSE = textureGather(hdr, pos, 1), bSE = textureGather(hdr, pos, 2);
    const vec4 rNW = textureGatherOffset(hdr, pos, ivec2(-1), 0), gNW = textureGatherOffset(hdr, pos, ivec2(-1), 1),
               bNW = textureGatherOffset(hdr, pos, ivec2(-1), 2);
    const float lumaM = luma_of(textureLod(hdr, pos, 0.0).rgb, glow);
    float lumaS = luma_of(vec3(rSE.x, gSE.x, bSE.x), glow), lumaE = luma_of(vec3(rSE.z, gSE.z, bSE.z), glow);
    float lumaN = luma_of(vec3(rNW.z, gNW.z, bNW.z), glow), lumaW = luma_of(vec3(rNW.x, gNW.x, bNW.x), glow);
    const float rangeMax = max(max(lumaN, lumaW), max(lumaE, max(lumaS, lumaM)));
    const float range = rangeMax - min(min(lumaN, lumaW), min(lumaE, min(lumaS, lumaM)));
    if (range < max(0.0833, rangeMax * 0.166)) return colorM;

    const float lumaNW = luma_of(vec3(rNW.w, gNW.w, bNW.w), glow), lumaSE = luma_of(vec3(rSE.y, gSE.y, bSE.y), glow);
    const float lumaNE = luma_at(pos + vec2(rcp.x, -rcp.y), glow), lumaSW = luma_at(pos + vec2(-rcp.x, rcp.y), glow);
    const float edgeHorz = abs(lumaNW + lumaSW - 2.0 * lumaW) + 2.0 * abs(lumaN + lumaS - 2.0 * lumaM) +
                           abs(lumaNE + lumaSE - 2.0 * lumaE);
    const float edgeVert = abs(lumaSW + lumaSE - 2.0 * lumaS) + 2.0 * abs(lumaW + lumaE - 2.0 * lumaM) +
                           abs(lumaNW + lumaNE - 2.0 * lumaN);
    const bool horzSpan = edgeHorz >= edgeVert;
    const float subpixB = (2.0 * (lumaN + lumaS + lumaW + lumaE) + lumaNW + lumaSW + lumaNE + lumaSE) / 12.0 - lumaM;
    const float subpixC = clamp(abs(subpixB) / range, 0.0, 1.0);
    if (!horzSpan) {
        lumaN = lumaW;
        lumaS = lumaE;
    }
    const float gradientN = lumaN - lumaM, gradientS = lumaS - lumaM;
    const bool pairN = abs(gradientN) >= abs(gradientS);
    const float gradientScaled = max(abs(gradientN), abs(gradientS)) * 0.25;
    const float side = pairN ? -1.0 : 1.0;

    // Walk both ends of the edge until the luma leaves the local pair's average; the last step is a blind 12 px.
    const vec2 offNP = horzSpan ? vec2(rcp.x, 0.0) : vec2(0.0, rcp.y);
    const vec2 across = (horzSpan ? vec2(0.0, rcp.y) : vec2(rcp.x, 0.0)) * side;
    const vec2 posB = pos + across * 0.5;
    const float lumaNN = luma_at(posB, glow);
    vec2 posN = posB - offNP, posP = posB + offNP;
    float lumaEndN = luma_at(posN, glow) - lumaNN, lumaEndP = luma_at(posP, glow) - lumaNN;
    bool doneN = abs(lumaEndN) >= gradientScaled, doneP = abs(lumaEndP) >= gradientScaled;
    for (int i = 1; i < 5; i++) {
        if (!doneN) posN -= offNP * kSteps[i];
        if (!doneP) posP += offNP * kSteps[i];
        if (i == 4 || (doneN && doneP)) break;
        if (!doneN) lumaEndN = luma_at(posN, glow) - lumaNN;
        if (!doneP) lumaEndP = luma_at(posP, glow) - lumaNN;
        doneN = doneN || abs(lumaEndN) >= gradientScaled;
        doneP = doneP || abs(lumaEndP) >= gradientScaled;
    }

    const float dstN = horzSpan ? pos.x - posN.x : pos.y - posN.y;
    const float dstP = horzSpan ? posP.x - pos.x : posP.y - pos.y;
    const bool lumaMLTZero = lumaM - lumaNN < 0.0;
    const bool goodSpan = dstN < dstP ? (lumaEndN < 0.0) != lumaMLTZero : (lumaEndP < 0.0) != lumaMLTZero;
    const float pixelOffset = goodSpan ? 0.5 - min(dstN, dstP) / (dstN + dstP) : 0.0;
    const float subpixF = (3.0 - 2.0 * subpixC) * subpixC * subpixC;
    const float offset = max(pixelOffset, subpixF * subpixF * 0.75);
    if (offset < 1.0 / 512.0) return colorM;
    return mix(colorM, tonemap(pos + across), offset);
}

void main() {
    const vec3 glow = glow_at(in_uv);
    const vec3 color = tonemap(texture(hdr, in_uv).rgb, glow);
    out_color = vec4(pc.fxaa != 0u ? fxaa(in_uv, color, glow) : color, 1.0);
}
