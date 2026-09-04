# 无缝拼图工具

绿色、免安装的 Windows 拼图工具。图片编辑与导出均在本机浏览器完成。

## 一条命令安装

在 Windows PowerShell 中粘贴并回车：

```powershell
iex ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(((irm 'https://api.github.com/repos/qq541253643-art/seamless-collage-tool/contents/install.ps1?ref=main').content -replace '\s',''))))
```

程序会安装到当前用户的“文档\无缝拼图工具”，并在桌面创建“无缝拼图工具”快捷方式。以后从桌面快捷方式打开即可。

## 更新

从桌面快捷方式打开时，程序会读取仓库的 `manifest.json`，只下载内容发生变化的文件。网络不可用时会继续打开已经安装的版本，检查结果保存在安装目录的 `update-status.txt`。

## 手动使用

下载仓库后双击“打开拼图工具.cmd”，或直接打开 `app.html`。

支持 Windows 10/11，建议使用新版 Edge 或 Chrome。
