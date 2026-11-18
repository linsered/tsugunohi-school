字体目录说明

本目录不包含字体文件。

游戏运行时会依次尝试：
1. res://assets/fonts/*.ttc
2. C:/Windows/Fonts/msyh.ttc（微软雅黑）、simsun.ttc（宋体）

微软雅黑与宋体为 Windows 系统授权字体，不可随仓库分发。
如需在其他平台运行，请自行放置一份可商用的中文字体到本目录，
并在 scripts/game.gd 的 _ready() 中把路径指向它。
