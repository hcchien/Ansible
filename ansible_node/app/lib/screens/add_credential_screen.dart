import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';

import '../services/atproto_client.dart';
import '../services/vc_issuer_client.dart';
import 'credential_issuance_wizard.dart';

class AddCredentialScreen extends StatelessWidget {
  const AddCredentialScreen({
    super.key,
    required this.holderDid,
    required this.onCredentialAdded,
    this.vcIssuerClient,
    this.relayClient,
    this.credentialWallet,
    this.vpBuilder,
  });

  /// The holder's DID (from registration).
  final String holderDid;

  /// Called when the Email OTP flow completes with the reputation tier
  /// returned by the Relay, e.g. "verified_human".
  final void Function(String reputationTier) onCredentialAdded;

  final VcIssuerClient? vcIssuerClient;
  final AtProtoClient? relayClient;
  final CredentialWallet? credentialWallet;
  final VpBuilder? vpBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加入憑證')),
      body: CredentialIssuanceWizard(
        holderDid: holderDid,
        vcIssuerClient: vcIssuerClient,
        relayClient: relayClient,
        credentialWallet: credentialWallet,
        vpBuilder: vpBuilder,
        onEmailCredentialAdded: onCredentialAdded,
      ),
    );
  }
}
