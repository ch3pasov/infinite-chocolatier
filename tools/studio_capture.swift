// Захват одного временного окна Studio без активации и запросов разрешений.
// Ошибка возвращает ненулевой код: старый PNG нельзя принять за новый кадр.
import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit
import Darwin

@main struct StudioCapture {
 static func emit(_ value: [String: Any], code: Int32) -> Never {
  let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  print(String(data: data, encoding: .utf8)!)
  exit(code)
 }
 static func main() async {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let args = CommandLine.arguments
  guard args.count == 3, args[1].hasSuffix(".rbxlx"), !args[1].contains("/"), args[2].hasPrefix("/") else {
   emit(["ok": false, "error": "Expected QA place filename and absolute PNG path"], code: 2)
  }
  guard CGPreflightScreenCaptureAccess() else {
   emit(["ok": false, "error": "Screen recording permission is unavailable; no permission request made"], code: 1)
  }
  do {
   let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
   let matches = content.windows.filter {
    $0.owningApplication?.bundleIdentifier == "com.Roblox.RobloxStudio" &&
    ($0.title ?? "").contains(args[1]) && $0.frame.width > 300
   }
   guard matches.count == 1, let window = matches.first else {
    emit(["ok": false, "error": "Expected exactly one matching Studio window", "matches": matches.count], code: 1)
   }
   let config = SCStreamConfiguration()
   config.width = Int(window.frame.width); config.height = Int(window.frame.height)
   config.showsCursor = false
   let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
   let image = try await SCScreenshotManager.captureImage(
    contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
   let bitmap = NSBitmapImageRep(cgImage: image)
   guard let png = bitmap.representation(using: .png, properties: [:]) else {
    emit(["ok": false, "error": "PNG encoding failed"], code: 1)
   }
   try png.write(to: URL(fileURLWithPath: args[2]), options: .withoutOverwriting)
   let after = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
   emit(["ok": true, "path": args[2], "width": image.width, "height": image.height,
         "windowId": window.windowID, "title": window.title ?? "", "onScreen": window.isOnScreen,
         "foregroundBefore": before, "foregroundAfter": after], code: 0)
  } catch {
   emit(["ok": false, "error": String(describing: error)], code: 1)
  }
 }
}
