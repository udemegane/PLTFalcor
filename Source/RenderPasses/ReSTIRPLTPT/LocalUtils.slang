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
// HWSS_SAMPLES == 1 : 64B
// HWSS_SAMPLES == 2 : 80B
// HWSS_SAMPLES == 3 : 80B
// HWSS_SAMPLES == 4 : 96B
#if HWSS_SAMPLES == 2
    // Size: 80B
    uint2 _padding;
#endif
#if HWSS_SAMPLES == 4
    // Size: 96B
    uint2 _padding;
#endif
    // Size: 64B ~ 96B
    hwss_t p_hat; // 4B ~ 16B

    float M;                        // 4B
    float w_sum;                    // 4B
    PackedPathReconstructionData s; // 52~64B

    __init(Reservoir r)
    {
        M = r.M;
        w_sum = r.w_sum;
        p_hat = r.p_hat;
        s = PackedPathReconstructionData(r.s);
        // rmisWeight = r.s.RMISWeight;
    }
    Reservoir unpack()
    {
        Reservoir r;
        r.M = M;
        r.w_sum = w_sum;
        r.p_hat = p_hat;
        r.s = s.unpack();
        r.s.RMISWeight = 1.0f; // Currently, only NEE resampling is supported, so RMISWeight is always 1.0f
        return r;
    }
};
