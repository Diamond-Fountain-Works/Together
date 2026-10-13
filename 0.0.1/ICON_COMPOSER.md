# Icon Composer

环境检查：Icon Composer 位于 `/Applications/Xcode.app/Contents/Applications/Icon Composer.app`。未发现可信的 Icon Composer MCP，`xcrun --find icontool` 不可用。

当前已提供原始 SVG、独立心形前景与背景、1024×1024 浅色/深色 PNG，以及可编译的 AppIcon.appiconset。没有虚构生成 AppIcon.icon；当前 Xcode Target 只使用这一套 asset catalog 图标配置。

手动制作 Liquid Glass 图标：

1. Xcode → Open Developer Tool → Icon Composer，创建 macOS 图标。
2. 导入 `Resources/IconSource/heart-foreground.svg`，背景使用 `background.svg` 或暖白底色。
3. 保持心形居中，适度启用反射、折射与柔和阴影；检查小尺寸、Light / Dark 外观。
4. 保存为 `AppIcon.icon`，添加到 Together Target，将 App Icon 名称设为 AppIcon。
5. 切换时移除或更名旧 `AppIcon.appiconset`，避免两个同名配置。重新执行实际 Xcode 构建验证。

参考：[Apple Icon Composer 文档](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)。
