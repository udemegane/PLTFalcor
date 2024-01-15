#pragma once


import PathHelper;

struct Reservoir
{
    float M = 0.0f;
    float w_sum = 0.0f;
    float p_hat = 0.0f;
    int bounceIdx = 0;
    LightSampleSeed s;
    // float cachedJacobian=0.0f;

    __init() {
        M = 0.0f;
        w_sum = 0.0f;
        p_hat = 0.0f;
        bounceIdx = 0;
        s = {};
    }

    [mutating]
    bool update(const float wi, LightSampleSeed si, const int bounceIdx_i, const float p_hat_i, const float rnd)
    {
        w_sum += wi;
        M+=1.0f;
        if (rnd < wi / w_sum)
        {
            p_hat = p_hat_i;
            s = si;
            bounceIdx = bounceIdx_i;
            return true;
        }
        return false;
    }

    float evalUCW() {
        return w_sum / p_hat;
    }
};


