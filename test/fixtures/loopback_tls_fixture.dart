import 'dart:io';

/// A fresh CA and a TLS server certificate for loopback tests only.
class LoopbackTlsFixture {
  LoopbackTlsFixture._(this._directory, this.serverContext, this.clientContext);

  final Directory _directory;
  final SecurityContext serverContext;
  final SecurityContext clientContext;

  static Future<LoopbackTlsFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'sko-loopback-tls-',
    );

    Future<void> openssl(List<String> args) async {
      final result = await Process.run(
        'openssl',
        args,
        workingDirectory: directory.path,
      );
      if (result.exitCode != 0) {
        throw StateError(
          'OpenSSL could not create a loopback TLS fixture: '
          '${result.stderr}',
        );
      }
    }

    try {
      await openssl([
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-days',
        '1',
        '-subj',
        '/CN=SKO Loopback Test CA',
        '-addext',
        'basicConstraints=critical,CA:TRUE',
        '-addext',
        'keyUsage=critical,keyCertSign,cRLSign',
        '-keyout',
        'ca.key',
        '-out',
        'ca.pem',
      ]);
      await openssl([
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-subj',
        '/CN=localhost',
        '-keyout',
        'server.key',
        '-out',
        'server.csr',
      ]);
      await File('${directory.path}/server.ext').writeAsString(
        'basicConstraints=critical,CA:FALSE\n'
        'keyUsage=critical,digitalSignature,keyEncipherment\n'
        'extendedKeyUsage=serverAuth\n'
        'subjectAltName=DNS:localhost,IP:127.0.0.1\n',
      );
      await openssl([
        'x509',
        '-req',
        '-in',
        'server.csr',
        '-CA',
        'ca.pem',
        '-CAkey',
        'ca.key',
        '-set_serial',
        '1',
        '-days',
        '1',
        '-extfile',
        'server.ext',
        '-out',
        'server.pem',
      ]);

      // Trust only the test CA. The server leaf is checked for the loopback
      // hostname and serverAuth by the platform's normal TLS verifier.
      final clientContext = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('${directory.path}/ca.pem');
      final serverContext = SecurityContext()
        ..useCertificateChain('${directory.path}/server.pem')
        ..usePrivateKey('${directory.path}/server.key');
      return LoopbackTlsFixture._(directory, serverContext, clientContext);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> dispose() => _directory.delete(recursive: true);
}
