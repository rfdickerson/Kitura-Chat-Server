/**
 * Copyright IBM Corporation 2016, 2017
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

// KituraChatServer is a very simple chat server

import Dispatch
import Foundation

import KituraWebSocket

import ConversationV1

let username = "f4a41bb7-55de-4cf0-8f62-241fcc9437e9"
let password = "4KVOiGQKmpLa"
let version = "2017-03-06" // use today's date for the most recent version
let conversation = Conversation(username: username, password: password, version: version)
let workspaceID = "6371a8bb-c167-4ff7-9ec1-c61e4d1be863"

let failure = { (error: Error) in print("Error with \(error)") }

class ChatService: WebSocketService {

    private let connectionsLock = DispatchSemaphore(value: 1)
    
    private var connections = [String: (String, WebSocketConnection)]()
    
    private enum MessageType: Character {
        case clientInChat = "c"
        case connected = "C"
        case disconnected = "D"
        case sentMessage = "M"
        case stoppedTyping = "S"
        case startedTyping = "T"
    }
    
    var context: Context? // save context to continue conversation

    public init() {

         conversation.message(withWorkspace: workspaceID, failure: failure) { response in
                print(response.output.text)
                self.context = response.context
            }

    }

    /// Called when a WebSocket client connects to the server and is connected to a specific
    /// `WebSocketService`.
    ///
    /// - Parameter connection: The `WebSocketConnection` object that represents the client's
    ///                    connection to this `WebSocketService`
    public func connected(connection: WebSocketConnection) {
        // Ignored

        print("New user just connected")
        self.lockConnectionsLock()
                
        connection.send(message: "\(MessageType.connected.rawValue):Watson")
    
        self.unlockConnectionsLock()

    }
    
    /// Called when a WebSocket client disconnects from the server.
    ///
    /// - Parameter connection: The `WebSocketConnection` object that represents the connection that
    ///                    was disconnected from this `WebSocketService`.
    /// - Paramater reason: The `WebSocketCloseReasonCode` that describes why the client disconnected.
    public func disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode) {
        lockConnectionsLock()
        if let disconnectedConnectionData = connections.removeValue(forKey: connection.id) {
            for (_, (_, from)) in connections {
                from.send(message: "\(MessageType.disconnected.rawValue):" + disconnectedConnectionData.0)
            }
        }
        unlockConnectionsLock()
    }
    
    /// Called when a WebSocket client sent a binary message to the server to this `WebSocketService`.
    ///
    /// - Parameter message: A Data struct containing the bytes of the binary message sent by the client.
    /// - Parameter client: The `WebSocketConnection` object that represents the connection over which
    ///                    the client sent the message to this `WebSocketService`
    public func received(message: Data, from: WebSocketConnection) {
        invalidData(from: from, description: "Kitura-Chat-Server only accepts text messages")
    }
    
    /// Called when a WebSocket client sent a text message to the server to this `WebSocketService`.
    ///
    /// - Parameter message: A String containing the text message sent by the client.
    /// - Parameter client: The `WebSocketConnection` object that represents the connection over which
    ///                    the client sent the message to this `WebSocketService`
    public func received(message: String, from: WebSocketConnection) {
        guard message.characters.count > 1 else { return }
        
        guard let messageType = message.characters.first else { return }
        
        let displayName = String(message.characters.dropFirst(2))
        
        if messageType == MessageType.sentMessage.rawValue || messageType == MessageType.startedTyping.rawValue ||
                       messageType == MessageType.stoppedTyping.rawValue {
            lockConnectionsLock()
            let connectionInfo = connections[from.id]
            unlockConnectionsLock()
            
            if  connectionInfo != nil {
                echo(message: message)
            }
        }
        else if messageType == MessageType.connected.rawValue {
            guard displayName.characters.count > 0 else {
                from.close(reason: .invalidDataContents, description: "Connect message must have client's name")
                return
            }
            
            lockConnectionsLock()
            for (_, (clientName, _)) in connections {
                from.send(message: "\(MessageType.clientInChat.rawValue):" + clientName)
            }
            
            connections[from.id] = (displayName, from)
            unlockConnectionsLock()
            
            echo(message: message)
        }
        else {
            invalidData(from: from, description: "First character of the message must be a C, M, S, or T")
        }
    }
    

    private func tellWatson(message: String) {
        
        let components = message.components(separatedBy: ":")
        
        guard components.count == 3 else {
            return
        }
        
        let question = components[2]
        
        print("Asking Watson: \(question)")

        let request = MessageRequest(text: question, context: context)
        conversation.message(withWorkspace: workspaceID, request: request, failure: failure) {
            response in
            
            print(response.output.text)
            
            print("Entities are: \(response.entities)")
                
            if response.output.text.count > 0 {

                let text = response.output.text[0]

                print("Sending client " + text)
                
                self.lockConnectionsLock()
                
                for (_, (_, connection)) in self.connections {
                    connection.send(message: "\(MessageType.sentMessage.rawValue):Watson:" + text)
                }

                self.unlockConnectionsLock()

            }
                    
            
            self.context = response.context
            
        }

    }

    private func echo(message: String) {

        tellWatson(message: message)

        lockConnectionsLock()
        for (_, (_, connection)) in connections {
            connection.send(message: message)
        }
        unlockConnectionsLock()
    }
    
    private func invalidData(from: WebSocketConnection, description: String) {
        from.close(reason: .invalidDataContents, description: description)
        lockConnectionsLock()
        let connectionInfo = connections.removeValue(forKey: from.id)
        unlockConnectionsLock()
        
        if let (clientName, _) = connectionInfo {
            echo(message: "\(MessageType.disconnected.rawValue):\(clientName)")
        }
    }
    
    private func lockConnectionsLock() {
        _ = connectionsLock.wait(timeout: DispatchTime.distantFuture)
    }
    
    private func unlockConnectionsLock() {
        connectionsLock.signal()
    }
}
