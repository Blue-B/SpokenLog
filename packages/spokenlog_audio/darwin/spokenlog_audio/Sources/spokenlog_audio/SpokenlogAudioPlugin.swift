import AVFoundation

#if os(iOS)
  import Flutter
  import UIKit
#else
  import FlutterMacOS
#endif

public class SpokenlogAudioPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  /// Files shared into the app that Dart has not taken yet.
  private var openedFiles: [String] = []

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "spokenlog_audio", binaryMessenger: messenger)
    let instance = SpokenlogAudioPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    #if os(iOS)
      registrar.addApplicationDelegate(instance)
      registrar.addSceneDelegate(instance)
    #endif
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "convertToWav":
      guard let args = call.arguments as? [String: Any],
        let source = args["source"] as? String,
        let target = args["target"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "source and target required", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try SpokenlogAudioPlugin.decodeToWav(
            source: URL(fileURLWithPath: source), target: URL(fileURLWithPath: target))
          DispatchQueue.main.async { result(nil) }
        } catch {
          try? FileManager.default.removeItem(atPath: target)
          DispatchQueue.main.async {
            result(FlutterError(code: "convert_failed", message: "\(error)", details: nil))
          }
        }
      }
    case "takeOpenedFiles":
      result(openedFiles)
      openedFiles.removeAll()
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Decodes the first audio track of [source] to 16 kHz mono PCM16 WAV, the format local engines read.
  static func decodeToWav(source: URL, target: URL) throws {
    let asset = AVURLAsset(url: source)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw NSError(
        domain: "spokenlog_audio", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "No audio track"])
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ])
    reader.add(output)
    guard reader.startReading() else {
      throw reader.error ?? NSError(domain: "spokenlog_audio", code: 2)
    }

    FileManager.default.createFile(atPath: target.path, contents: Data(count: 44))
    let handle = try FileHandle(forWritingTo: target)
    defer { handle.closeFile() }
    handle.seekToEndOfFile()
    var dataBytes = 0
    while let buffer = output.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
      let length = CMBlockBufferGetDataLength(block)
      if length == 0 { continue }
      var data = Data(count: length)
      data.withUnsafeMutableBytes { raw in
        _ = CMBlockBufferCopyDataBytes(
          block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
      }
      handle.write(data)
      dataBytes += length
    }
    if reader.status == .failed {
      throw reader.error ?? NSError(domain: "spokenlog_audio", code: 3)
    }
    if dataBytes == 0 {
      throw NSError(
        domain: "spokenlog_audio", code: 4,
        userInfo: [NSLocalizedDescriptionKey: "No audio decoded"])
    }
    handle.seek(toFileOffset: 0)
    handle.write(wavHeader(dataBytes: dataBytes))
  }

  static func wavHeader(dataBytes: Int) -> Data {
    var header = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
      withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
    }
    header.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36 + dataBytes))
    header.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))  // PCM
    append(UInt16(1))  // mono
    append(UInt32(16000))
    append(UInt32(32000))  // byte rate
    append(UInt16(2))  // block align
    append(UInt16(16))  // bits per sample
    header.append(contentsOf: Array("data".utf8))
    append(UInt32(dataBytes))
    return header
  }

  #if os(iOS)
    /// Copies a file shared into the app (e.g. Voice Memos > Share > SpokenLog) to a temp
    /// path Dart can import, then tells Dart to collect it.
    @discardableResult
    func receive(_ url: URL) -> Bool {
      guard url.isFileURL else { return false }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("shared_audio", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      let target = dir.appendingPathComponent(url.lastPathComponent)
      do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: target)
      } catch {
        return false
      }
      // iOS drops "Copy to" files into Documents/Inbox; don't let them pile up.
      if url.path.contains("/Documents/Inbox/") {
        try? FileManager.default.removeItem(at: url)
      }
      openedFiles.append(target.path)
      channel.invokeMethod("filesOpened", arguments: nil)
      return true
    }
  #endif
}

#if os(iOS)
  extension SpokenlogAudioPlugin: FlutterSceneLifeCycleDelegate {
    @objc(application:didFinishLaunchingWithOptions:)
    public func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]
    ) -> Bool {
      if let url = launchOptions[UIApplication.LaunchOptionsKey.url] as? URL {
        receive(url)
      }
      return true
    }

    @objc(application:openURL:options:)
    public func application(
      _ app: UIApplication, open url: URL,
      options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
      receive(url)
    }

    @objc(scene:willConnectToSession:options:)
    public func scene(
      _ scene: UIScene, willConnectTo session: UISceneSession,
      options connectionOptions: UIScene.ConnectionOptions?
    ) -> Bool {
      connectionOptions?.urlContexts.forEach { receive($0.url) }
      // Not claiming the connection keeps Flutter's normal scene setup.
      return false
    }

    @objc(scene:openURLContexts:)
    public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
      URLContexts.map { receive($0.url) }.contains(true)
    }
  }
#endif
