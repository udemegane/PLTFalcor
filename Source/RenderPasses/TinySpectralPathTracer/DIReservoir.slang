#include "Utils/Math/MathConstants.slangh"
import Rendering.Utils.LightsSamplingUtils;
struct DIReservoir
{
    float wSum;    // Sum of resampling weight
    float p_hat;   // value evaluated for p_hat(current_sample)
    LightSample s; // Current Sample choosed by WRS
    uint M;
    __init()
    {
        wSum = 0.F;
        M = 0;
        s = {};
    }

    [mutating]
    bool update(const LightSample s_i, const float w_i, const float p_hat_i, const float rand)
    {
        wSum += w_i;
        bool accept = rand <= w_i / wSum;
        if (accept || M == 0)
        {
            this.s = s_i;
            p_hat = p_hat_i;
        }
        M++;
        return accept;
    }

    float evalUCW() { return wSum / (p_hat + FLT_EPSILON); }
}

