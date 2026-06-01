import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
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
    this.walletRepository,
    this.onCredentialStored,
  });

  /// The holder's DID (from registration).
  final String holderDid;

  /// Called when the Email OTP flow completes with the reputation tier
  /// returned by the Relay, e.g. "basic".
  final void Function(String reputationTier) onCredentialAdded;

  final VcIssuerClient? vcIssuerClient;
  final AtProtoClient? relayClient;
  final CredentialWallet? credentialWallet;
  final VpBuilder? vpBuilder;
  final WalletRepository? walletRepository;
  final VoidCallback? onCredentialStored;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.uiCopy(zh: '加入憑證', en: 'Add Credential')),
      ),
      body: CredentialIssuanceWizard(
        holderDid: holderDid,
        vcIssuerClient: vcIssuerClient,
        relayClient: relayClient,
        credentialWallet: credentialWallet,
        vpBuilder: vpBuilder,
        walletRepository: walletRepository,
        onCredentialStored: onCredentialStored,
        onEmailCredentialAdded: onCredentialAdded,
      ),
    );
  }
}
