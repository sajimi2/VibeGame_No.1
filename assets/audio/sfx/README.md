# 林路音效来源与处理

替换原合成提示音；映射入口 `scripts/presentation/sound_library.gd`。以下来源均标注 CC0，来源文件随本目录保留。

| 文件 | 作者与来源 | 本地许可 |
| --- | --- | --- |
| footstep_*、impact* | [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds) | LICENSE-Kenney-Impact.txt |
| knifeSlice*、cloth*、dropLeather、beltHandle1、creak1、doorClose_1、handleSmallLeather、book*、handleCoins | [Kenney RPG Audio](https://kenney.nl/assets/rpg-audio) | LICENSE-Kenney-RPG.txt |
| boots-leather-jump-* | Vehicle / Jan Schupke，[Fantasy Weapons and Apparel SFX Library](https://opengameart.org/content/fantasy-weapons-and-apparel-sfx-library) | LICENSE-Vehicle.txt |
| bow_draw / bow_release | Ben Jaszczak、Brian Nelson，[Medieval Sound Effects — Weapon Textures](https://opengameart.org/content/medieval-sound-effects-weapon-textures) | 本说明、下方CC0链接 |

[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。Kenney与Vehicle文件按原文件复制；弓声原始WAV保留在 `source/`，由 FFmpeg 去除开头低于 -40dB 的静音，取释放0.65秒/拉弓0.14秒并淡出，Vorbis q=5编码。处理命令模式：

```text
ffmpeg -i "source/English Longbow Shoot.wav" -af "silenceremove=start_periods=1:start_duration=0.01:start_threshold=-40dB,atrim=duration=0.65,afade=t=out:st=0.52:d=0.13" -c:a libvorbis -q:a 5 bow_release.ogg
ffmpeg -i "source/English Longbow Draw.wav" -af "silenceremove=start_periods=1:start_duration=0.01:start_threshold=-40dB,atrim=duration=0.14,afade=t=out:st=0.10:d=0.04" -c:a libvorbis -q:a 5 bow_draw.ogg
```

素材整包和下载中间件仅在忽略目录 `work/woodpath_v2/`。原始长WAV只用于制作，不在运行时播放。

SFX 总线可在背包独立调节。表现层按事件限频、控制并发、避免同一变体连续重复、轻微变化音高，并按与玩家距离衰减音量；当前不是左右声道空间定位。草地/小院木地板分别选脚步声，后者依据房屋范围判断，未来多房间应改为地表查询。18种事件的文件加载和长度已自动检查；最终听感仍需实际试听。
