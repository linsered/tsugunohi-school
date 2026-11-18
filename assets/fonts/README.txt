字体目录说明

ui.ttf / serif.ttf 是从 Noto Sans SC / Noto Serif SC 抽取游戏所需字形生成的
子集字体（约 0.4MB / 0.5MB），随项目分发，保证 Web 导出与无中文字体系统
都能正确显示中文。两者均为 SIL Open Font License 1.1 授权，见 OFL-NOTO.txt。

如需重新生成（源码或文案改动后）：
    pip install fonttools
    python tools/build_fonts.py

游戏加载顺序（scripts/game.gd 的 _ready()）：
1. res://assets/fonts/ui.ttf、serif.ttf（内嵌，跨平台的正式方案）
2. Windows 系统字体 msyh.ttc（微软雅黑）作为最后的本地回退
