// Verify with the public key embedded in the packaged app, never the signer's key.
import Foundation
import CryptoKit

do {
    guard CommandLine.arguments.count == 4,
          let keyData = Data(base64Encoded: CommandLine.arguments[2]),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw NSError(domain: "Invalid verification arguments", code: 1)
    }
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: .mappedIfSafe)
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "Signature mismatch", code: 2)
    }
} catch {
    fputs("Sparkle signature does not verify against the packaged app's public key. Release stopped.\n", stderr)
    exit(1)
}
