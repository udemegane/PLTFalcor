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
    float M;                        // 4B
    float w_sum;                    // 4B
    float W;                        // 4B
    PackedPathReconstructionData s; // 52,56,60,64B

#if HWSS_SAMPLES == 1
    // 80B
    float L1;
    uint3 _padding;
#endif
#if HWSS_SAMPLES == 2
    // 80B
    float L1;
    float L2;
    uint _padding;
#endif
#if HWSS_SAMPLES == 3
    // 96B
    float L1;
    float L2;
    float L3;
    uint3 _padding;
#endif
#if HWSS_SAMPLES == 4
    // 96B
    float L1;
    float L2;
    float L3;
    float L4;
    uint _padding;
#endif

    __init(Reservoir r)
    {
        M = r.M;
        w_sum = r.w_sum;
        W = r.W;
#if HWSS_SAMPLES == 1
        L1 = r.p_hat[0];
#endif
#if HWSS_SAMPLES == 2
        L1 = r.p_hat[0];
        L2 = r.p_hat[1];
#endif
#if HWSS_SAMPLES == 3
        L1 = r.p_hat[0];
        L2 = r.p_hat[1];
        L3 = r.p_hat[2];
#endif
#if HWSS_SAMPLES == 4
        L1 = r.p_hat[0];
        L2 = r.p_hat[1];
        L3 = r.p_hat[2];
        L4 = r.p_hat[3];
#endif
        s = PackedPathReconstructionData(r.s);
        // rmisWeight = r.s.RMISWeight;
    }
    Reservoir unpack()
    {
        Reservoir r;
        r.M = M;
        r.w_sum = w_sum;
        r.W = W; // TODO:
        r.p_hat = hwss_t(0.0f);
#if HWSS_SAMPLES == 1
        r.p_hat[0] = L1;
#endif
#if HWSS_SAMPLES == 2
        r.p_hat[0] = L1;
        r.p_hat[1] = L2;
#endif
#if HWSS_SAMPLES == 3
        r.p_hat[0] = L1;
        r.p_hat[1] = L2;
        r.p_hat[2] = L3;
#endif
#if HWSS_SAMPLES == 4
        r.p_hat[0] = L1;
        r.p_hat[1] = L2;
        r.p_hat[2] = L3;
        r.p_hat[3] = L4;
#endif
        r.s = s.unpack();
        r.s.RMISWeight = 1.0f; // Currently, only NEE resampling is supported, so RMISWeight is always 1.0f
        return r;
    }
};
