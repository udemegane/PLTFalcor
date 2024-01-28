import Reservoir;
import PathHelper;
import Utils.HWSS;
uint encodeMortonCode(const uint2 pixel)
{
    uint result = 0u;
    for (int i = 0; i < 16; i++)
    {
        result |= ((pixel.x & (1 << i)) << i) | ((pixel.y & (1 << i)) << (i + 1));
    }
    return result;
}

void decodeMortonCode(const uint code, out uint2 pixel)
{
    pixel.x = 0u;
    pixel.y = 0u;
    for (int i = 0; i < 16; i++)
    {
        pixel.x |= (code & (1 << (2 * i))) >> i;
        pixel.y |= (code & (1 << (2 * i + 1))) >> (i + 1);
    }
}

// https://developer.nvidia.com/content/understanding-structured-buffer-performance
// For efficiency, it is recommended that the size of a structured buffer be a multiple of 16 bytes.
#ifndef HWSS_SAMPLES
#define HWSS_SAMPLES 1
#endif

// typealias reserver_padding = vector<float, pad_size>;
struct PackedReservoir
{
    // 64,68,72,76B
#if HWSS_SAMPLES == 1
    // 4B
    float L;
    float W;
#endif
#if HWSS_SAMPLES == 2
    float2 L;
    float2 W;
    // TODO: padding
#endif
#if HWSS_SAMPLES == 3
    float3 L;
    float3 W;
    uint _padding;
#endif
#if HWSS_SAMPLES == 4
    float4 L;
    float4 W;
    uint2 _padding;
#endif
    // 60 ~ 72B
    // float M;                        // 4B
    float w_sum;                    // 4B
    PackedPathReconstructionData s; // 52,56,60,64B

    __init(Reservoir r)
    {
        w_sum = r.w_sum;

#if HWSS_SAMPLES == 1
        L = r.p_hat[0];
        W = r.W[0];
#endif
#if HWSS_SAMPLES == 2
        L[0] = r.p_hat[0];
        L[1] = r.p_hat[1];
        W[0] = r.W[0];
        W[1] = r.W[1];
#endif
#if HWSS_SAMPLES == 3
        L[0] = r.p_hat[0];
        L[1] = r.p_hat[1];
        L[2] = r.p_hat[2];
        W[0] = r.W[0];
        W[1] = r.W[1];
        W[2] = r.W[2];
#endif
#if HWSS_SAMPLES == 4
        L[0] = r.p_hat[0];
        L[1] = r.p_hat[1];
        L[2] = r.p_hat[2];
        L[3] = r.p_hat[3];
        W[0] = r.W[0];
        W[1] = r.W[1];
        W[2] = r.W[2];
        W[3] = r.W[3];
#endif
        s = PackedPathReconstructionData(r.s);
        s.packedComponents.y |= (max(r.M, 0b00000000000000000000000011111111) << 24) & (uint)PackedComponentsMask::M;
        // rmisWeight = r.s.RMISWeight;
    }
    Reservoir unpack()
    {
        Reservoir r;
        r.w_sum = w_sum;
        r.W = W; // TODO:
        r.p_hat = hwss_t(0.0f);
#if HWSS_SAMPLES == 1
        r.p_hat[0] = L;
        r.W[0] = W;
#endif
#if HWSS_SAMPLES == 2
        r.p_hat[0] = L[0];
        r.p_hat[1] = L[1];
        r.W[0] = W[0];
        r.W[1] = W[1];
#endif
#if HWSS_SAMPLES == 3
        r.p_hat[0] = L[0];
        r.p_hat[1] = L[1];
        r.p_hat[2] = L[2];
        r.W[0] = W[0];
        r.W[1] = W[1];
        r.W[2] = W[2];
#endif
#if HWSS_SAMPLES == 4
        r.p_hat[0] = L[0];
        r.p_hat[1] = L[1];
        r.p_hat[2] = L[2];
        r.p_hat[3] = L[3];
        r.W[0] = W[0];
        r.W[1] = W[1];
        r.W[2] = W[2];
        r.W[3] = W[3];
#endif
        r.s = s.unpack();
        r.M = (s.packedComponents.y & (uint)PackedComponentsMask::M) >> 24;
        r.s.RMISWeight = 1.0f; // Currently, only NEE resampling is supported, so RMISWeight is always 1.0f
        return r;
    }
};
