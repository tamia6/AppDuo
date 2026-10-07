import CryptoKit
import Foundation

// Validate the signature with the public key embedded into both release builds,
// so mismatched CI signing configuration cannot publish unusable appcasts.
do {
    guard CommandLine.arguments.count == 4,
          let key = Data(base64Encoded: CommandLine.arguments[1]),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw NSError(domain: "AppDuoUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid verification arguments"])
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: .mappedIfSafe)
    guard publicKey.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "AppDuoUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Update signature does not match embedded public key"])
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
