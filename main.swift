//  算盘 (SuanPan) — macOS 原生「液态玻璃」桌面计算器
//  单文件 AppKit 实现：真·NSGlassEffectView + 窗口置顶 + 空闲自动淡出
//  要求 macOS 26.0+（NSGlassEffectView API 自 macOS 26 起提供）
//

import AppKit

// MARK: - 全局配置

enum Cfg {
    static let size        = NSSize(width: 320, height: 470)
    static let winRadius: CGFloat   = 28
    static let barHeight: CGFloat   = 46
    static let pad: CGFloat         = 12
    static let gap: CGFloat         = 8
    static let rowHeight: CGFloat   = 52
    static let keyRadius: CGFloat   = 14

    static let activeAlpha: CGFloat  = 0.99
    static let idleAlpha: CGFloat    = 0.40
    static let idleDelay: TimeInterval = 1.5
    static let fadeInDuration: TimeInterval  = 0.16
    static let fadeOutDuration: TimeInterval = 0.55
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) {
        return f
    }
    return base
}

func white(_ a: CGFloat) -> NSColor { NSColor(white: 1.0, alpha: a) }

/// 橘色主色调（全部元素由它派生，改这里即可整体换色）
enum Palette {
    static let accent       = NSColor(srgbRed: 1.00, green: 0.63, blue: 0.20, alpha: 1)  // #FFA133
    static let accentBright = NSColor(srgbRed: 1.00, green: 0.78, blue: 0.52, alpha: 1)  // 亮橘
    static let accentDeep   = NSColor(srgbRed: 0.95, green: 0.51, blue: 0.07, alpha: 1)  // 深橘（= 键）
    static let displayText  = NSColor(srgbRed: 1.00, green: 0.84, blue: 0.66, alpha: 1)  // 暖橘白

    static func orange(_ a: CGFloat) -> NSColor {
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.20, alpha: a)
    }
    static func orangeLight(_ a: CGFloat) -> NSColor {
        NSColor(srgbRed: 1.00, green: 0.77, blue: 0.53, alpha: a)
    }
}

/// 给整数部分加千分位
func groupedNumber(_ s: String) -> String {
    if s == "错误" || s.isEmpty { return s }
    if s.contains("e") || s.contains("E") { return s }
    let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    var intPart = String(parts[0])
    var sign = ""
    if intPart.hasPrefix("-") { sign = "-"; intPart.removeFirst() }
    var out = ""
    let chars = Array(intPart)
    for (i, c) in chars.enumerated() {
        if i > 0 && (chars.count - i) % 3 == 0 { out.append(",") }
        out.append(c)
    }
    if parts.count > 1 { return sign + out + "." + parts[1] }
    return sign + out
}

// MARK: - 计算引擎

final class CalcEngine {

    enum Op {
        case add, sub, mul, div

        var symbol: String {
            switch self {
            case .add: return "+"
            case .sub: return "−"
            case .mul: return "×"
            case .div: return "÷"
            }
        }
    }

    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 9
        f.minimumFractionDigits = 0
        f.roundingMode = .halfUp
        return f
    }()

    /// 当前输入串（未分组）
    private var entry = "0"
    /// 当前显示的是否为「结果」（结果状态下输入数字要重新开始）
    private var entryIsResult = false
    private var acc: Double? = nil
    private var pendingOp: Op? = nil
    private var lastOp: Op? = nil
    private var lastOperand: Double = 0
    private let maxDigits = 12

    var displayText: String { groupedNumber(entry) }

    var pendingDescription: String {
        guard let op = pendingOp, let a = acc else { return "" }
        return "\(groupedNumber(format(a))) \(op.symbol)"
    }

    // MARK: 输入

    func inputDigit(_ d: String) {
        if entryIsResult {
            entry = "0"
            entryIsResult = false
        }
        let digitCount = entry.filter { $0.isNumber }.count
        if entry == "0" {
            entry = d
        } else if entry == "-0" {
            entry = "-" + d
        } else if digitCount < maxDigits {
            entry += d
        }
    }

    func inputDot() {
        if entryIsResult {
            entry = "0"
            entryIsResult = false
        }
        if !entry.contains(".") { entry += "." }
    }

    func setOp(_ op: Op) {
        let v = value(entry)
        if let p = pendingOp, !entryIsResult, let a = acc {
            // 连算
            let r = apply(p, a, v)
            acc = r
            entry = format(r)
        } else {
            acc = v
        }
        pendingOp = op
        entryIsResult = true
    }

    func equals() {
        if let p = pendingOp, let a = acc {
            let v = value(entry)
            lastOp = p
            lastOperand = v
            let r = apply(p, a, v)
            entry = format(r)
            entryIsResult = true
            pendingOp = nil
        } else if let lp = lastOp {
            // 重复上一次运算
            let a = value(entry)
            let r = apply(lp, a, lastOperand)
            entry = format(r)
            entryIsResult = true
        }
    }

    func clear() {
        entry = "0"
        entryIsResult = false
        acc = nil
        pendingOp = nil
        lastOp = nil
        lastOperand = 0
    }

    func backspace() {
        if entryIsResult { clear(); return }
        if entry.count <= 1 {
            entry = "0"
        } else {
            entry.removeLast()
            if entry == "-" { entry = "0" }
        }
    }

    // MARK: 内部

    private func value(_ s: String) -> Double { Double(s) ?? 0 }

    private func apply(_ op: Op, _ a: Double, _ b: Double) -> Double {
        switch op {
        case .add: return a + b
        case .sub: return a - b
        case .mul: return a * b
        case .div: return b == 0 ? .nan : a / b
        }
    }

    private func format(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "错误" }
        if v == 0 { return "0" }
        if abs(v) > 1e15 { return String(format: "%.6e", v) }
        // 消除浮点尾巴：先按 9 位小数四舍五入，再交给 formatter
        let cleaned = (v * 1e9).rounded() / 1e9
        return formatter.string(from: NSNumber(value: cleaned)) ?? String(cleaned)
    }
}

// MARK: - 动作定义

enum KeyKind { case digit, function, op, equals }

enum KeyAction {
    case digit(String)
    case dot
    case op(CalcEngine.Op)
    case equals
    case clear
    case backspace
}

struct KeySpec {
    let label: String
    let symbol: String?
    let kind: KeyKind
    let span: Int
    let action: KeyAction

    init(_ label: String, _ kind: KeyKind, _ span: Int, _ action: KeyAction, symbol: String? = nil) {
        self.label = label
        self.symbol = symbol
        self.kind = kind
        self.span = span
        self.action = action
    }
}

// MARK: - 按键视图

final class KeyButton: NSView {

    let spec: KeySpec
    var onTap: (() -> Void)?

    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    init(frame: NSRect, spec: KeySpec) {
        self.spec = spec
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        pressing = false
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        pressing = true
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let wasPressing = pressing
        pressing = false
        if wasPressing && inside { onTap?() }
    }

    // MARK: 绘制

    private var fillColor: NSColor {
        switch spec.kind {
        case .digit:
            return Palette.orange(pressing ? 0.26 : (hovering ? 0.17 : 0.085))
        case .function:
            return Palette.orange(pressing ? 0.34 : (hovering ? 0.23 : 0.135))
        case .op:
            return Palette.orange(pressing ? 0.34 : (hovering ? 0.22 : 0.125))
        case .equals:
            return Palette.accentDeep.withAlphaComponent(pressing ? 1.0 : (hovering ? 0.95 : 0.88))
        }
    }

    private var textColor: NSColor {
        switch spec.kind {
        case .digit:    return white(0.96)
        case .function: return Palette.orangeLight(0.90)
        case .op:       return Palette.accentBright
        case .equals:   return white(0.99)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: bounds.height - 1)
        let path = NSBezierPath(roundedRect: r, xRadius: Cfg.keyRadius, yRadius: Cfg.keyRadius)
        fillColor.setFill()
        path.fill()

        // 极淡的内描边，提供玻璃边缘质感
        Palette.orange(hovering ? 0.34 : 0.16).setStroke()
        path.lineWidth = 1
        path.stroke()

        if let sym = spec.symbol {
            drawSymbol(sym)
        } else {
            drawLabel()
        }
    }

    private func drawLabel() {
        let size: CGFloat
        switch spec.kind {
        case .digit: size = 23
        case .op:    size = 25
        case .function: size = 16
        case .equals: size = 25
        }
        let weight: NSFont.Weight = spec.kind == .function ? .semibold : .medium
        let font = roundedFont(size, weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let str = NSAttributedString(string: spec.label, attributes: attrs)
        let s = str.size()
        let rect = NSRect(x: (bounds.width - s.width) / 2,
                          y: (bounds.height - s.height) / 2,
                          width: s.width, height: s.height)
        str.draw(in: rect)
    }

    private func drawSymbol(_ name: String) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [textColor]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return }
        let s = img.size
        let rect = NSRect(x: (bounds.width - s.width) / 2,
                          y: (bounds.height - s.height) / 2,
                          width: s.width, height: s.height)
        img.draw(in: rect)
    }
}

// MARK: - 显示区

final class DisplayView: NSView {

    override var isFlipped: Bool { true }

    var mainText = "0"  { didSet { needsDisplay = true } }
    var subText  = ""   { didSet { needsDisplay = true } }

    private func fontSize(for s: String) -> CGFloat {
        switch s.count {
        case 0...8:  return 46
        case 9...11: return 38
        case 12...14: return 31
        case 15...17: return 26
        default: return 22
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 待执行的运算提示（左上，极淡）
        if !subText.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: roundedFont(13, .medium),
                .foregroundColor: Palette.orangeLight(0.55)
            ]
            NSAttributedString(string: subText, attributes: attrs)
                .draw(at: NSPoint(x: 20, y: 6))
        }

        // 主数字（右下对齐）
        let size = fontSize(for: mainText)
        let font = roundedFont(size, .light)
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        para.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Palette.displayText,
            .paragraphStyle: para
        ]
        let str = NSAttributedString(string: mainText, attributes: attrs)
        let h = ceil(font.ascender - font.descender) + 6
        let rect = NSRect(x: 20, y: bounds.height - h - 6, width: bounds.width - 40, height: h)
        str.draw(in: rect)
    }
}

// MARK: - 顶部栏

final class TopBarView: NSView {

    enum HitZone { case close, pin, none }

    var onClose: (() -> Void)?
    var onTogglePin: (() -> Void)?

    var isPinned = true { didSet { needsDisplay = true } }
    var isIdle = false { didSet { needsDisplay = true } }

    private var hoverZone: HitZone = .none { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    private var dragOffset: NSPoint?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private let closeRect = NSRect(x: 15, y: 16, width: 14, height: 14)
    private let pinRect   = NSRect(x: 320 - 15 - 26, y: 10, width: 26, height: 26)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let z: HitZone
        if closeRect.insetBy(dx: -6, dy: -6).contains(p) { z = .close }
        else if pinRect.contains(p) { z = .pin }
        else { z = .none }
        if z != hoverZone { hoverZone = z }
    }

    override func mouseExited(with event: NSEvent) {
        if hoverZone != .none { hoverZone = .none }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.insetBy(dx: -6, dy: -6).contains(p) { return }
        if pinRect.contains(p) { return }
        // 其余区域：拖动窗口
        guard let win = window else { return }
        let m = NSEvent.mouseLocation
        dragOffset = NSPoint(x: m.x - win.frame.origin.x, y: m.y - win.frame.origin.y)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragOffset = nil
        if closeRect.insetBy(dx: -6, dy: -6).contains(p) {
            onClose?()
        } else if pinRect.contains(p) {
            onTogglePin?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window, let off = dragOffset else { return }
        let m = NSEvent.mouseLocation
        win.setFrameOrigin(NSPoint(x: m.x - off.x, y: m.y - off.y))
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        let r = Cfg.winRadius

        // 顶部栏底色：空闲时反而略微加强，保证「一眼能认出这里」
        let topA: CGFloat = isIdle ? 0.30 : 0.20
        let botA: CGFloat = isIdle ? 0.12 : 0.07

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        let shape = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h + r),
                                 xRadius: r, yRadius: r)
        if let g = NSGradient(colors: [Palette.orange(topA), Palette.orange(botA)]) {
            g.draw(in: shape, angle: -90)
        }
        NSGraphicsContext.restoreGraphicsState()

        // 底部细分隔线
        Palette.orange(0.20).setFill()
        NSRect(x: 0, y: h - 0.5, width: w, height: 0.5).fill()

        drawDragHint()
        drawCloseButton()
        drawPinButton()
    }

    private func drawDragHint() {
        Palette.orange(isIdle ? 0.42 : 0.30).setFill()
        let bar = NSRect(x: bounds.midX - 11, y: bounds.height / 2 - 0.75, width: 22, height: 1.5)
        NSBezierPath(roundedRect: bar, xRadius: 0.75, yRadius: 0.75).fill()
    }

    private func drawCloseButton() {
        let hovered = hoverZone == .close
        let c = NSPoint(x: closeRect.midX, y: closeRect.midY)
        let rad = closeRect.width / 2

        let dot = NSBezierPath(ovalIn: NSRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
        if hovered {
            NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1).setFill()
        } else {
            white(isIdle ? 0.34 : 0.26).setFill()
        }
        dot.fill()

        guard hovered else { return }
        let arm = rad * 0.40
        let x = NSBezierPath()
        x.lineWidth = 1.6
        x.lineCapStyle = .round
        x.move(to: NSPoint(x: c.x - arm, y: c.y - arm))
        x.line(to: NSPoint(x: c.x + arm, y: c.y + arm))
        x.move(to: NSPoint(x: c.x - arm, y: c.y + arm))
        x.line(to: NSPoint(x: c.x + arm, y: c.y - arm))
        NSColor(white: 0.32, alpha: 1).setStroke()
        x.stroke()
    }

    private func drawPinButton() {
        let hovered = hoverZone == .pin
        if hovered {
            white(0.13).setFill()
            NSBezierPath(roundedRect: pinRect, xRadius: 7, yRadius: 7).fill()
        }

        let (name, color): (String, NSColor)
        if isPinned {
            name = "pin.fill"
            color = Palette.accentBright
        } else {
            name = "pin"
            color = white(isIdle ? 0.40 : 0.36)
        }

        let cfg = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return }
        let s = img.size
        let rect = NSRect(x: pinRect.midX - s.width / 2,
                          y: pinRect.midY - s.height / 2,
                          width: s.width, height: s.height)
        img.draw(in: rect)
    }
}

// MARK: - 根视图

/// 统一使用「顶部为 y=0」的坐标系，避免 AppKit 默认左下原点造成的布局混乱
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 沿窗口圆角内缘画一圈暖色高光，压掉玻璃材质自带的不规则暗边。不接收鼠标事件。
final class EdgeLineView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.6, dy: 0.6),
                             xRadius: Cfg.winRadius, yRadius: Cfg.winRadius)
        p.lineWidth = 1.2
        Palette.orangeLight(0.32).setStroke()
        p.stroke()
    }
}

final class RootView: NSView {

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var onHoverChange: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent)  { onHoverChange?(false) }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        super.mouseDown(with: event)
    }
}

// MARK: - 窗口

final class CalcWindow: NSWindow {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

// MARK: - 控制器

final class CalcViewController: NSViewController {

    let engine = CalcEngine()

    private var topBar: TopBarView!
    private var display: DisplayView!
    private var keypad: NSView!
    private var root: RootView!

    private var fadeTimer: Timer?
    private var mouseInsideReal = false
    private var lastKeyInteraction = Date.distantPast
    private var isActiveState = true

    override func loadView() {
        root = RootView(frame: NSRect(origin: .zero, size: Cfg.size))
        root.autoresizingMask = [.width, .height]

        // 顶部栏
        topBar = TopBarView(frame: NSRect(x: 0, y: 0, width: Cfg.size.width, height: Cfg.barHeight))
        topBar.autoresizingMask = [.width]
        topBar.onClose = { NSApp.terminate(nil) }
        topBar.onTogglePin = { [weak self] in self?.togglePin() }
        root.addSubview(topBar)

        // 显示区
        let displayY = Cfg.barHeight
        let keypadTop = Cfg.size.height - Cfg.pad - (Cfg.rowHeight * 5 + Cfg.gap * 4)
        display = DisplayView(frame: NSRect(x: 0, y: displayY,
                                            width: Cfg.size.width,
                                            height: keypadTop - displayY))
        display.autoresizingMask = [.width]
        root.addSubview(display)

        // 键盘区
        buildKeypad(top: keypadTop)

        // 边缘高光（最上层，鼠标穿透）
        let edge = EdgeLineView(frame: root.bounds)
        edge.autoresizingMask = [.width, .height]
        root.addSubview(edge)

        root.onHoverChange = { [weak self] inside in
            self?.setHover(inside)
        }

        self.view = root
        refresh()
    }

    private func buildKeypad(top: CGFloat) {
        let gridW = Cfg.size.width - Cfg.pad * 2
        let keyW = (gridW - Cfg.gap * 3) / 4

        let container = FlippedView(frame: NSRect(x: Cfg.pad, y: top, width: gridW,
                                                  height: Cfg.rowHeight * 5 + Cfg.gap * 4))
        container.autoresizingMask = [.width]

        let specs: [[KeySpec]] = [
            [KeySpec("AC", .function, 2, .clear),
             KeySpec("", .function, 1, .backspace, symbol: "delete.left"),
             KeySpec("÷", .op, 1, .op(.div))],

            [KeySpec("7", .digit, 1, .digit("7")),
             KeySpec("8", .digit, 1, .digit("8")),
             KeySpec("9", .digit, 1, .digit("9")),
             KeySpec("×", .op, 1, .op(.mul))],

            [KeySpec("4", .digit, 1, .digit("4")),
             KeySpec("5", .digit, 1, .digit("5")),
             KeySpec("6", .digit, 1, .digit("6")),
             KeySpec("−", .op, 1, .op(.sub))],

            [KeySpec("1", .digit, 1, .digit("1")),
             KeySpec("2", .digit, 1, .digit("2")),
             KeySpec("3", .digit, 1, .digit("3")),
             KeySpec("+", .op, 1, .op(.add))],

            [KeySpec("0", .digit, 2, .digit("0")),
             KeySpec(".", .digit, 1, .dot),
             KeySpec("=", .equals, 1, .equals)]
        ]

        for (r, row) in specs.enumerated() {
            var col = 0
            for spec in row {
                let w = keyW * CGFloat(spec.span) + Cfg.gap * CGFloat(spec.span - 1)
                let x = CGFloat(col) * (keyW + Cfg.gap)
                let y = CGFloat(r) * (Cfg.rowHeight + Cfg.gap)
                let btn = KeyButton(frame: NSRect(x: x, y: y, width: w, height: Cfg.rowHeight), spec: spec)
                btn.onTap = { [weak self] in self?.perform(spec.action) }
                container.addSubview(btn)
                col += spec.span
            }
        }

        root.addSubview(container)
        keypad = container
    }

    // MARK: 动作

    private func perform(_ action: KeyAction) {
        bumpInteraction()
        switch action {
        case .digit(let d): engine.inputDigit(d)
        case .dot:          engine.inputDot()
        case .op(let o):    engine.setOp(o)
        case .equals:       engine.equals()
        case .clear:        engine.clear()
        case .backspace:    engine.backspace()
        }
        refresh()
    }

    private func refresh() {
        display.mainText = engine.displayText
        display.subText  = engine.pendingDescription
    }

    /// 开发期视觉自检用：填入一组示例数据
    func prepareForSnapshot() {
        display.mainText = "1,234,567.89"
        display.subText  = "42 ×"
    }

    private func togglePin() {
        guard let win = view.window else { return }
        let pinned = topBar.isPinned
        topBar.isPinned = !pinned
        win.level = pinned ? .normal : .floating
        // 取消置顶后如果失去焦点，让它回到前台可点状态
        if pinned { win.orderFront(nil) }
        bumpInteraction()
    }

    // MARK: 键盘

    func handleKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }

        if event.keyCode == 36 || event.keyCode == 76 {   // return / enter
            bumpInteraction(); engine.equals(); refresh(); return true
        }
        if event.keyCode == 51 || event.keyCode == 117 {  // delete / forward delete
            bumpInteraction(); engine.backspace(); refresh(); return true
        }
        if event.keyCode == 53 {                          // esc
            bumpInteraction(); engine.clear(); refresh(); return true
        }

        guard let chars = event.charactersIgnoringModifiers, let c = chars.first else { return false }

        if c.isNumber {
            bumpInteraction(); engine.inputDigit(String(c)); refresh(); return true
        }
        switch c {
        case ".":                bumpInteraction(); engine.inputDot()
        case "+":                bumpInteraction(); engine.setOp(.add)
        case "-":                bumpInteraction(); engine.setOp(.sub)
        case "*", "x", "X":      bumpInteraction(); engine.setOp(.mul)
        case "/", ":":           bumpInteraction(); engine.setOp(.div)
        case "=":                bumpInteraction(); engine.equals()
        case "c", "C":           bumpInteraction(); engine.clear()
        default: return false
        }
        refresh()
        return true
    }

    // MARK: 空闲淡出

    func startFadeLoop() {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.evaluateFade()
        }
        RunLoop.main.add(fadeTimer!, forMode: .common)
        evaluateFade()
    }

    private func bumpInteraction() {
        lastKeyInteraction = Date()
        evaluateFade()
    }

    func setHover(_ inside: Bool) {
        mouseInsideReal = inside
        evaluateFade()
    }

    private func evaluateFade() {
        let recentKey = Date().timeIntervalSince(lastKeyInteraction) < Cfg.idleDelay
        setActive(mouseInsideReal || recentKey)
    }

    private func setActive(_ active: Bool) {
        guard active != isActiveState else { return }
        isActiveState = active
        topBar.isIdle = !active
        guard let win = view.window else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = active ? Cfg.fadeInDuration : Cfg.fadeOutDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            win.animator().alphaValue = active ? Cfg.activeAlpha : Cfg.idleAlpha
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    var window: CalcWindow!
    var controller: CalcViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = CalcViewController()

        let win = CalcWindow(contentRect: NSRect(origin: .zero, size: Cfg.size),
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.isOpaque = false
        win.backgroundColor = .clear
        // 关掉系统阴影：无边框透明窗在圆角边界被 WindowServer 抗锯齿时
        // 会渗出深色像素，看起来就是「不规则黑线」——直接不要系统阴影
        win.hasShadow = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isMovableByWindowBackground = false
        win.isReleasedWhenClosed = false
        win.animationBehavior = .utilityWindow

        // 液态玻璃底
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: Cfg.size))
        glass.style = .regular
        glass.cornerRadius = Cfg.winRadius
        glass.tintColor = Palette.orange(0.12)
        glass.autoresizingMask = [.width, .height]

        let rootView = controller.view
        rootView.frame = glass.bounds
        rootView.autoresizingMask = [.width, .height]
        // 把内容严格裁进圆角，避免任何像素溢出边缘造成毛糙
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = Cfg.winRadius
        rootView.layer?.masksToBounds = true
        glass.contentView = rootView

        win.contentView = glass
        win.keyHandler = { [weak self] ev in self?.controller.handleKey(ev) ?? false }

        self.window = win

        // 位置：优先沿用上次记住的位置，否则贴在主屏右下角（并保证完整落在可见区域内）
        let size = Cfg.size
        let target = NSScreen.screens.first ?? NSScreen.main
        var origin: NSPoint? = nil

        if let saved = UserDefaults.standard.string(forKey: "SuanPanFrame") {
            let r = NSRectFromString(saved)
            if r.width > 0,
               NSScreen.screens.contains(where: { $0.visibleFrame.intersects(r) }) {
                origin = r.origin
            }
        }
        if origin == nil, let vf = target?.visibleFrame {
            let rawX = vf.maxX - size.width - 36
            let rawY = vf.minY + 70
            origin = NSPoint(
                x: max(vf.minX + 12, min(rawX, vf.maxX - size.width - 12)),
                y: max(vf.minY + 12, min(rawY, vf.maxY - size.height - 12))
            )
        }
        if let o = origin {
            win.setFrameOrigin(o)
        } else {
            win.center()
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
        controller.startFadeLoop()

        // 诊断：确认玻璃是否内缩了内容视图
        if CommandLine.arguments.contains("--diag") {
            let glass = win.contentView as? NSGlassEffectView
            for (i, s) in NSScreen.screens.enumerated() {
                print("screen[\(i)] frame=\(s.frame) visibleFrame=\(s.visibleFrame)")
            }
            print("NSScreen.main = \(NSScreen.main.map { "\($0.frame)" } ?? "nil")")
            print("window.frame          = \(win.frame)")
            print("glass.bounds          = \(glass?.bounds ?? .zero)")
            print("glass.contentView.frame = \(glass?.contentView?.frame ?? .zero)")
            print("rootView.frame        = \(rootView.frame)")
            exit(0)
        }

        // 桌面常驻：最小化/隐藏不适用，关闭即退出
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(appActivated),
                                              name: NSApplication.didBecomeActiveNotification,
                                              object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 记住窗口位置，下次还在原地
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "SuanPanFrame")
    }

    @objc private func appActivated() {
        if window.level == .floating && !window.isVisible {
            window.orderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - 启动

// 离屏渲染自检：--snapshot <输出路径> <light|dark>
func renderSnapshot(to path: String, backdrop: String = "light") {
    _ = NSApplication.shared

    let controller = CalcViewController()
    let root = controller.view          // 触发 loadView，先建好视图树
    controller.prepareForSnapshot()
    root.layoutSubtreeIfNeeded()

    let size = Cfg.size
    guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
    root.cacheDisplay(in: root.bounds, to: rep)
    let uiImage = NSImage(size: root.bounds.size)
    uiImage.addRepresentation(rep)

    let image = NSImage(size: size)
    image.lockFocus()

    // —— 模拟窗口背后的内容 ——
    if backdrop == "light" {
        // 模拟 Excel / 文档白底
        NSColor(white: 0.955, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(white: 0.87, alpha: 1).setStroke()
        var y: CGFloat = 0
        while y < size.height {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 0, y: y))
            p.line(to: NSPoint(x: size.width, y: y))
            p.lineWidth = 0.5
            p.stroke()
            y += 27
        }
        var x: CGFloat = 0
        while x < size.width {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: 0))
            p.line(to: NSPoint(x: x, y: size.height))
            p.lineWidth = 0.5
            p.stroke()
            x += 78
        }
    } else {
        // 模拟深色壁纸
        if let g = NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.12, blue: 0.18, alpha: 1),
                                       NSColor(srgbRed: 0.22, green: 0.16, blue: 0.28, alpha: 1)]) {
            g.draw(in: NSRect(origin: .zero, size: size), angle: -60)
        }
    }

    // —— 玻璃近似层（真实折射由系统 NSGlassEffectView 完成，此处仅用于评估对比度）——
    let glassRect = NSRect(origin: .zero, size: size)
    let glassPath = NSBezierPath(roundedRect: glassRect, xRadius: Cfg.winRadius, yRadius: Cfg.winRadius)
    NSColor(srgbRed: 0.33, green: 0.25, blue: 0.19,
            alpha: backdrop == "light" ? 0.60 : 0.66).setFill()
    glassPath.fill()
    Palette.orangeLight(0.32).setStroke()
    glassPath.lineWidth = 1.2
    glassPath.stroke()

    uiImage.draw(in: glassRect, from: .zero, operation: .sourceOver, fraction: 1)

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("snapshot failed")
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("snapshot -> \(path)")
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let mode = (i + 2 < CommandLine.arguments.count) ? CommandLine.arguments[i + 2] : "light"
    renderSnapshot(to: CommandLine.arguments[i + 1], backdrop: mode)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

// 最小主菜单（支持 ⌘Q）
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "隐藏 算盘", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(withTitle: "退出 算盘", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu

app.run()
