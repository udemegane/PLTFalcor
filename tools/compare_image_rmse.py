import cv2
import math

def colored_string(str):
    return f"\033[1;31;40m{str}\033[0m"
def colored_string_red(str):
    return f"\033[1;31;40m{str}\033[0m"
def colored_string_green(str):
    return f"\033[1;32;40m{str}\033[0m"
def colored_string_yellow(str):
    return f"\033[1;33;40m{str}\033[0m"
def colored_string_blue(str):
    return f"\033[1;34;40m{str}\033[0m"
def colored_string_gray(str):
    return f"\033[1;37;40m{str}\033[0m"

path_root = 'E:\\data\\PT\\submit_proto'
gt_path = f"{path_root}\\bike_pt_34000_hwss1.34.1ms.ToneMapper.dst..png"
img1_path = f"{path_root}\\bike_pt_1_hwss1.34.1ms.ToneMapper.dst..png"
img2_path = f"{path_root}\\bike_rs_20_hwss1.43.5ms.ToneMapper.dst..png"

gt_img = cv2.imread(gt_path, cv2.IMREAD_COLOR)/255
img1 = cv2.imread(img1_path, cv2.IMREAD_COLOR)/255
img2 = cv2.imread(img2_path, cv2.IMREAD_COLOR)/255

mse1, _=cv2.quality.QualityMSE_compute(gt_img, img1)
mse2, _=cv2.quality.QualityMSE_compute(gt_img, img2)
res1 = math.sqrt((mse1[0] + mse1[1] + mse1[2])/3)
res2 = math.sqrt((mse2[0] + mse2[1] + mse2[2])/3)
print(f"RMSE of {colored_string_gray(img1_path)} is: {colored_string_yellow(res1)}")
print(f" - RAW MSE: {colored_string_red(mse1[2])}, {colored_string_green(mse1[1])}, {colored_string_blue(mse1[0])}")
print(f"RMSE of {colored_string_gray(img2_path)} is: {colored_string_yellow(res2)}")
print(f" - RAW MSE: {colored_string_red(mse2[2])}, {colored_string_green(mse2[1])}, {colored_string_blue(mse2[0])}")
print(f"Ratio: {colored_string_yellow(res1/res2)}")
