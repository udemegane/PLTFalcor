import cv2
scale_factor = 10.0
def calculate_absolute_difference(image1, image2):
    # 画像を読み込む
    img1 = cv2.imread(image1)
    img2 = cv2.imread(image2)

    # 画像の差を計算
    diff = cv2.absdiff(img1, img2)
    scaled_diff = diff * scale_factor

    # 差の絶対値を新しい画像として保存
    cv2.imwrite("absolute_difference_image.png", scaled_diff)

if __name__ == "__main__":
    # 2つの画像のファイルパスを指定してください
    path_root = 'E:\\data\\PT\\submit_proto'
    image_path1 = f"{path_root}\\cbox_pt_hwss4_wrong.ToneMapper.dst..png"
    image_path2 = f"{path_root}\\cbox_rs_hwss4_wrong.ToneMapper.dst..png"

    # 画像の差の絶対値を計算して保存
    calculate_absolute_difference(image_path1, image_path2)
