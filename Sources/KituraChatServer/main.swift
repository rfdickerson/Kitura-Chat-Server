/**
 * Copyright IBM Corporation 2016
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

import Foundation

import Kitura
import KituraWebSocket

import HeliumLogger

// All Web apps need a router to define routes
let router = Router()

// Using an implementation for a Logger
HeliumLogger.use(.info)

// Serve installed node modules
router.all("/node_modules", middleware: StaticFileServer(path: "./node_modules"))

// Serve the files in the public directory for the web client
router.all("/", middleware: StaticFileServer())

WebSocket.register(service: ChatService(), onPath: "/kitura-chat")

// Add HTTP Server to listen on port 8090
Kitura.addHTTPServer(onPort: 8090, with: router)

// start the framework - the servers added until now will start listening
Kitura.run()