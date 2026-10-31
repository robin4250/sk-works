// Compile-only Flutter surface. Not a runtime or Keychain test.
public protocol FlutterBinaryMessenger {}
public typealias FlutterResult = (Any?) -> Void
public struct FlutterMethodCall {
  public let method: String
  public let arguments: Any?
}
public class FlutterMethodChannel {
  public init(name: String, binaryMessenger: FlutterBinaryMessenger) {}
  public func setMethodCallHandler(_ handler: ((FlutterMethodCall, @escaping FlutterResult) -> Void)?) {}
}
public class FlutterError {
  public init(code: String, message: String?, details: Any?) {}
}
public let FlutterMethodNotImplemented = "compile-only-method-not-implemented"
