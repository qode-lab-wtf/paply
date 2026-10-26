import Carbon
import Foundation

// Read key labels only. No event monitoring or Accessibility permission needed.
let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { exit(1) }
let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
let keys: [UInt16: String] = [
  0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
  11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2",
  20:"3", 21:"4", 22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8",
  29:"0", 30:"]", 31:"O", 32:"U", 33:"[", 34:"I", 35:"P", 37:"L", 38:"J",
  39:"'", 40:"K", 41:";", 42:"\\", 43:",", 44:"/", 45:"N", 46:"M", 47:".", 50:"`"
]
var labels: [String: String] = [:]
for (code, key) in keys {
  var dead: UInt32 = 0
  var length = 0
  var chars = [UniChar](repeating: 0, count: 8)
  let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, chars.count, &length, &chars)
  if status == noErr && length > 0 {
    let label = String(utf16CodeUnits: chars, count: length)
    let upper = label.uppercased()
    labels[key] = upper.count == 1 ? upper : label
  }
}
let result = try JSONSerialization.data(withJSONObject: labels, options: [.sortedKeys])
FileHandle.standardOutput.write(result)
