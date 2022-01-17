import 'itransport.dart';

/// 使用不同种类连接需实现的基本结构
abstract class IConnection {
  ConnectionFeatures? features;
  String? connectionId;

  late String baseUrl;

  Future<void> start({TransferFormat? transferFormat});
  Future<void> send(data);
  Future<void> stop({Exception? error});

  void Function(dynamic data)? onreceive;
  void Function({Exception? error})? onclose;
}

class ConnectionFeatures {
  // Properties
  bool inherentKeepAlive;

  // Methods
  ConnectionFeatures(this.inherentKeepAlive);
}
