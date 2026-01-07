
import 'package:shelf/shelf.dart';

Middleware verifyHttpSignature() {
  return (Handler innerHandler) {
    return (Request request) async {
      // AP requests usually come with 'Signature' header
      final signature = request.headers['signature'];
      
      // TODO: Verify signature against Actor's public key
      // 1. Parse keyId from signature header
      // 2. Fetch Actor object from keyId URL
      // 3. Extract publicKeyPem
      // 4. Verify signature using RSA-SHA256
      
      if (signature != null) {
        print('Received Signature: $signature');
      }

      return innerHandler(request);
    };
  };
}
