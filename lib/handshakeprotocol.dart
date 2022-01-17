import 'dart:convert';

import 'dart:typed_data';

import 'textmessageformat.dart';

/// 握手请求消息模型
class HandshakeRequestMessage {
  String protocol;
  int version;
  HandshakeRequestMessage(this.protocol, this.version);

  String toJson() {
    var map = <String, dynamic>{};
    map['protocol'] = protocol;
    map['version'] = version;

    return jsonEncode(map);
  }
}

/// 握手返回消息模型
class HandshakeResponseMessage {
  String? error;
  late int minorVersion;

  HandshakeResponseMessage.fromJson(String source) {
    Map<String, dynamic> data = jsonDecode(source);
    if (data.isNotEmpty) {
      error = data['error'];
      minorVersion = data['minorVersion'];
      if (data['type'] != null) {
        throw Exception("Expected a handshake response from the server.");
      }
    }
  }
}

/// private
class ParseHandshakeResponseResult {
  // Properites
  /// Either a string (json) or a Uint8List (binary).
  final dynamic remainingData;

  /// The HandshakeResponseMessage
  final HandshakeResponseMessage handshakeResponseMessage;

  // Methods
  ParseHandshakeResponseResult(
      this.remainingData, this.handshakeResponseMessage);
}

/// 握手协议
class HandshakeProtocol {
  // Handshake request is always JSON
  String writeHandshakeRequest(HandshakeRequestMessage handshakeRequest) {
    return TextMessageFormat.write(handshakeRequest.toJson());
  }

  ParseHandshakeResponseResult parseHandshakeResponse(data) {
    String messageData;
    dynamic remainingData;

    // if (isArrayBuffer(data)) {
    if (data is Uint8List) {
      // Format is binary but still need to read JSON text from handshake response
      var binaryData = data;
      var separatorIndex =
          binaryData.indexOf(TextMessageFormat.RecordSeparatorCode);
      if (separatorIndex == -1) {
        throw Exception("Message is incomplete.");
      }

      // content before separator is handshake response
      // optional content after is additional messages
      var responseLength = separatorIndex + 1;
      // messageData = String.fromCharCode.apply(null, Array.prototype.slice.call(binaryData.slice(0, responseLength)));
      // remainingData = (binaryData.byteLength > responseLength) ? binaryData.slice(responseLength).buffer : null;
      messageData = utf8.decode(data.sublist(0, responseLength));
      remainingData = (data.length > responseLength)
          ? data.sublist(responseLength, data.length)
          : null;
    } else {
      String textData = data;
      var separatorIndex = textData.indexOf(TextMessageFormat.RecordSeparator);
      if (separatorIndex == -1) {
        throw Exception("Message is incomplete.");
      }

      // content before separator is handshake response
      // optional content after is additional messages
      var responseLength = separatorIndex + 1;
      messageData = textData.substring(0, responseLength);
      remainingData = (textData.length > responseLength)
          ? textData.substring(responseLength)
          : null;
    }

    // At this point we should have just the single handshake message
    // print(data);
    var messages = TextMessageFormat.parse(messageData);
    var response = HandshakeResponseMessage.fromJson(messages[0]);
    // if (response.type) {
    //   throw Exception("Expected a handshake response from the server.");
    // }
    HandshakeResponseMessage responseMessage = response;

    // multiple messages could have arrived with handshake
    // return additional data to be parsed as usual, or null if all parsed
    return ParseHandshakeResponseResult(
        remainingData, responseMessage); //[remainingData, responseMessage];
  }
}
