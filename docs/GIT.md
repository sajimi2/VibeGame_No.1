# 本地版本管理

仓库根目录：D:\vibe coding\OutpostRPG。默认分支 main。远程：`origin` =
`https://github.com/sajimi2/VibeGame_No.1.git`，本地 main 跟踪 origin/main（Codex 于 2026-09-15 建立并
推送）。标签 `v0.2-stage1` 标记用户已试玩通过的 v0.2 阶段 1。

注意：`.git` 目录属主是 Codex 运行账户（LAPTOP-COML2AH9/CodexSandboxOffline），本机另一个账户直接跑
`git` 会报 `dubious ownership`。已在本机执行
`git config --global --add safe.directory 'D:/vibe coding/OutpostRPG'`；换机器或换账户时需要重新添加。

源码、场景、资源配置、Godot .uid 文件、测试及文档进入版本管理；.godot/、builds/、work/、临时文件及本地密钥文件忽略。正式美术和音频素材应跟随代码提交。

## 日常使用

在 VS Code 打开此文件夹，左侧“源代码管理”即可查看改动、暂存及提交。也可以在终端运行：

```powershell
git status
git diff
git log --oneline --decorate -10
```

由当前实施者在完成一块功能并验证后提交，说明改了什么。先检查已有改动，避免夹带其他人未完成的工作。用户确认的阶段版本打标签，不要求每个小改动都开分支或走审批。

需要尝试较大改动时可新建分支；要恢复旧版本，先保留当前未提交工作，再明确要恢复哪些文件，不直接执行破坏性重置。

远程已配置，可由实施者在验证通过后推送；推送前先确认没有夹带他人的未完成工作。`work/` 中的测试日志和
`builds/` 中的 exe 不进入提交，因此远程仓库不含可执行产物，发布包需要单独传递。
