extends RefCounted
## 统一素材制作密度，不再把完整游戏二次降采样；标准画面和UI均为1280×720。
## 角色96²保留自己的颜色/深度源，文字独立清晰绘制；像素风不能靠整屏打码代替。
const WORLD_SIZE:=Vector2i(1280,720)
const UI_SIZE:=Vector2i(1280,720)
const ENVIRONMENT_PIXELS_PER_METER:=28.0
