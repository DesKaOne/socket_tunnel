class Address {
  final String host;
  final int port;

  Address({required this.host, required this.port});

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      host: (json['host'] as String).toLowerCase(),
      port: json['port'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'host': host, 'port': port};

  @override
  String toString() => '$host:$port';
}
