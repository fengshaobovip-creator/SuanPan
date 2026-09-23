// 生成「算盘」App 图标：橙色计算器
// 遵循 macOS 图标规范：1024 画布，内容区 824×824 居中（四周各留 100），圆角 185
//
// 用法: icongen <输出 png 路径>

import AppKit

let W = 1024
let S = CGFloat(W)

func cg(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: W,
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("无法创建绘图上下文\n".data(using: .utf8)!)
    exit(1)
}

ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

// MARK: 1. 主体圆角矩形

let inset = S * 0.0977
let bodyRect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius = S * 0.1807
let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// 投影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.014),
              blur: S * 0.035,
              color: cg(0.55, 0.24, 0.0, 0.38))
ctx.addPath(bodyPath)
ctx.setFillColor(cg(1, 0.62, 0.18))
ctx.fillPath()
ctx.restoreGState()

// 橙色渐变
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()

let bodyGrad = CGGradient(colorsSpace: cs, colors: [
    cg(1.00, 0.78, 0.40),
    cg(1.00, 0.64, 0.20),
    cg(0.92, 0.47, 0.06)
] as CFArray, locations: [0, 0.48, 1])!
ctx.drawLinearGradient(bodyGrad,
                       start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
                       end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
                       options: [])

// 顶部高光，营造玻璃质感
let gloss = CGGradient(colorsSpace: cs, colors: [
    cg(1, 1, 1, 0.30),
    cg(1, 1, 1, 0.0)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gloss,
                       start: CGPoint(x: 0, y: bodyRect.maxY),
                       end: CGPoint(x: 0, y: bodyRect.maxY - bodyRect.height * 0.45),
                       options: [])
ctx.restoreGState()

// MARK: 2. 显示屏

let scr = CGRect(x: S * 0.185, y: S * 0.690, width: S * 0.630, height: S * 0.145)
let scrR = S * 0.032
ctx.addPath(CGPath(roundedRect: scr, cornerWidth: scrR, cornerHeight: scrR, transform: nil))
ctx.setFillColor(cg(1, 1, 1, 0.95))
ctx.fillPath()

// 屏内数字示意（右下角一段橘色数字条）
let barH = S * 0.032
let bar = CGRect(x: scr.maxX - S * 0.245, y: scr.midY - barH / 2,
                 width: S * 0.185, height: barH)
ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
ctx.setFillColor(cg(0.94, 0.52, 0.07, 1))
ctx.fillPath()

// MARK: 3. 按键点阵 3 列 × 4 行

let cols: [CGFloat] = [0.272, 0.500, 0.728]
let rows: [CGFloat] = [0.585, 0.462, 0.339, 0.216]
let dotR = S * 0.049

for ry in rows {
    for cx in cols {
        let center = CGPoint(x: S * cx, y: S * ry)
        ctx.setFillColor(cg(1, 1, 1, 0.80))
        ctx.fillEllipse(in: CGRect(x: center.x - dotR, y: center.y - dotR,
                                   width: dotR * 2, height: dotR * 2))
    }
}

// MARK: 输出

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write("生成图像失败\n".data(using: .utf8)!)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: W, height: W)

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("编码 PNG 失败\n".data(using: .utf8)!)
    exit(1)
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon.png"
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("icon -> \(outPath)")
} catch {
    FileHandle.standardError.write("写入失败: \(error)\n".data(using: .utf8)!)
    exit(1)
}
