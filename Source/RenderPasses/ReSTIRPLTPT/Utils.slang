import Reservoir;
uint encodeMortonCode(const uint2 pixel)
{
    uint result = 0u;
    for (int i = 0; i < 16; i++)
    {
        result |= ((pixel.x & (1 << i)) << i) | ((pixel.y & (1 << i)) << (i + 1));
    }
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
struct PackedReservoir
{
    // Size: 80B
    float M;                        // 4B
    float w_sum;                    // 4B
    float p_hat;                    // 4B
    float _padding;                 // 4B
    PackedPathReconstructionData s; // 64B

    __init(Reservoir r)
    {
        M = r.M;
        w_sum = r.w_sum;
        p_hat = r.p_hat;
        s = PackedPathReconstructionData(r.s);
    }
    Reservoir unpack()
    {
        Reservoir r;
        r.M = M;
        r.w_sum = w_sum;
        r.p_hat = p_hat;
        r.s = s.unpack();
        return r;
    }
};
