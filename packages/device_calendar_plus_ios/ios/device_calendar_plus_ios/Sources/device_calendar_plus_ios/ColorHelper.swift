import Foundation
import CoreGraphics

class ColorHelper {
  /// `hex` is the canonical `#RRGGBB` Dart's `normalizeColorHex` forwards.
  static func hexToColor(hex: String) -> CGColor {
    let rgb = UInt64(hex.dropFirst(), radix: 16) ?? 0

    let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
    let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
    let b = CGFloat(rgb & 0x0000FF) / 255.0
    
    return CGColor(red: r, green: g, blue: b, alpha: 1.0)
  }
  
  static func colorToHex(cgColor: CGColor) -> String {
    guard let components = cgColor.components, components.count >= 3 else {
      return "#000000"
    }
    
    let r = Int(components[0] * 255.0)
    let g = Int(components[1] * 255.0)
    let b = Int(components[2] * 255.0)
    
    return String(format: "#%02X%02X%02X", r, g, b)
  }
}

