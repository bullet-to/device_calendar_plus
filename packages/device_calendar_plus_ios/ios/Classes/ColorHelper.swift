import Foundation
import CoreGraphics

class ColorHelper {
  static func hexToColor(hex: String) -> CGColor {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
    
    var rgb: UInt64 = 0
    Scanner(string: hexSanitized).scanHexInt64(&rgb)
    
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

