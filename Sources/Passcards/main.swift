import Commander
import Foundation
import HeliumLogger
import Kitura
import MongoKitten
import PasscardsServer
import Shove

let databaseOption = Option("database", "mongodb://localhost:27017/passcards", flag: "d", description: "The MongoDB server and database (in valid connection string format)")
let keyPath = Option("key", "", flag: "k", description: "Path to the APNS token private key in .p8 format")
let passphrase = Option("passphrase", "", flag: "p", description: "Passphrase to decrypt the key file")
let keyID = Option("key-id", "", flag: "i", description: "The APNS token key ID as prescribed by Apple")
let teamID = Option("team-id", "", flag: "t", description: "The team ID for which the APNS token key was generated")
let updateToken = Option("updateToken", "", flag: "u", description: "The authentication token to require for uploading or updating passes")
let port = Option("port", 8080, flag: "p", description: "The port on which to run the server")

enum PasscardsError: Error {
    case invalidDatabaseURI
    case badDatabaseCredentials
    case missingKey
    case invalidKeyCredentials
    case invalidAPNSCredentials
}

let main = command(databaseOption, keyPath, passphrase, keyID, teamID, updateToken, port) { databaseURI, keyPath, passphrase, keyID, teamID, updateToken, port in
    guard let databaseURL = URL(string: databaseURI) else {
        throw PasscardsError.invalidDatabaseURI
    }

    let serverURL = databaseURL.deletingLastPathComponent()
    let database = databaseURL.lastPathComponent

    let server = try Server(serverURL as NSURL, automatically: false)

    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    guard let keyURL = URL(string: keyPath, relativeTo: cwd) else {
        throw PasscardsError.missingKey
    }

    guard let key = SigningKey(url: keyURL, passphrase: (!passphrase.isEmpty ? passphrase : nil)) else {
        throw PasscardsError.invalidKeyCredentials
    }

    let jwtGenerator = JSONWebTokenGenerator(key: key, keyID: keyID, teamID: teamID)
    let shoveClient = ShoveClient(tokenGenerator: jwtGenerator)

    do {
        try server.connect()
    } catch {
        throw PasscardsError.badDatabaseCredentials
    }

    let passcardsServer = PasscardsServer(database: server[database], shoveClient: shoveClient, updateToken: updateToken)

    HeliumLogger.use()
    Kitura.addHTTPServer(onPort: port, with: passcardsServer)
    Kitura.run()
}

main.run()
