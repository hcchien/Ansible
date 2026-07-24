package oid4vci

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/trisaura/ansible_issuer/internal/hostedissuer"
	"github.com/trisaura/ansible_issuer/internal/vc"
)

type Issuer struct {
	state   *StateService
	store   hostedissuer.Store
	keys    *hostedissuer.KeyManager
	baseURL string
	now     func() time.Time
}

func NewIssuer(state *StateService, store hostedissuer.Store, keys *hostedissuer.KeyManager, baseURL string, now func() time.Time) *Issuer {
	if now == nil {
		now = time.Now
	}
	return &Issuer{state: state, store: store, keys: keys, baseURL: baseURL, now: now}
}

func (i *Issuer) CredentialIssuerURL(tenantID string) string {
	return i.baseURL + "/tenants/" + tenantID
}

func (i *Issuer) Metadata(tenantID string) (map[string]any, error) {
	tenant, err := i.store.Tenant(tenantID)
	if err != nil {
		return nil, err
	}
	issuerURL := i.CredentialIssuerURL(tenantID)
	return map[string]any{
		"credential_issuer":     issuerURL,
		"authorization_servers": []string{issuerURL},
		"credential_endpoint":   issuerURL + "/credential",
		"nonce_endpoint":        issuerURL + "/nonce",
		"credential_configurations_supported": map[string]any{
			"PoliticalPartyMembershipCredential-v1": map[string]any{
				"format": "jwt_vc_json", "scope": "membership",
				"cryptographic_binding_methods_supported": []string{"jwk"},
				"credential_signing_alg_values_supported": []string{"EdDSA"},
				"credential_definition":                   map[string]any{"type": []string{"VerifiableCredential", vc.MembershipCredentialType}},
				"proof_types_supported":                   map[string]any{"jwt": map[string]any{"proof_signing_alg_values_supported": []string{"ES256"}}},
				"display":                                 []map[string]any{{"name": "Membership credential", "locale": "en"}, {"name": "會員憑證", "locale": "zh-Hant"}},
			},
		},
		"display": []map[string]any{{"name": tenant.ServiceSlug, "locale": "en"}},
	}, nil
}

// createOffer is intentionally private. Every externally reachable issuance
// path must consume an approved issuance request before minting a grant.
func (i *Issuer) createOffer(tenantID, holderPairwiseDID, membershipClass string) (map[string]any, error) {
	return i.createBoardOffer(tenantID, holderPairwiseDID, membershipClass, "", "")
}

func (i *Issuer) createBoardOffer(tenantID, holderPairwiseDID, membershipClass, forumHostID, boardID string) (map[string]any, error) {
	code, _, err := i.state.CreateBoardPreAuthorizedGrant(tenantID, "PoliticalPartyMembershipCredential-v1", holderPairwiseDID, membershipClass, forumHostID, boardID)
	if err != nil {
		return nil, err
	}
	return map[string]any{
		"credential_issuer":            i.CredentialIssuerURL(tenantID),
		"forum_host_id":                forumHostID,
		"board_id":                     boardID,
		"credential_configuration_ids": []string{"PoliticalPartyMembershipCredential-v1"},
		"grants": map[string]any{
			"urn:ietf:params:oauth:grant-type:pre-authorized_code": map[string]any{"pre-authorized_code": code},
		},
	}, nil
}

func (i *Issuer) PutMembershipTemplate(tenantID string, version int64, maxTTLDays int, active bool) (hostedissuer.CredentialTemplate, error) {
	tenant, err := i.store.Tenant(tenantID)
	if err != nil || version < 1 || tenant.Threshold < 1 || maxTTLDays < 1 || maxTTLDays > 365 {
		return hostedissuer.CredentialTemplate{}, hostedissuer.ErrDelegationInvalid
	}
	template := hostedissuer.CredentialTemplate{
		ID: "membership", TenantID: tenantID, Version: version,
		CredentialType:    vc.MembershipCredentialType,
		ClaimAllowlist:    []string{"organization_id", "membership", "membership_class"},
		ApprovalThreshold: tenant.Threshold, MaxTTLDays: maxTTLDays, Active: active,
	}
	if err := i.store.PutCredentialTemplate(tenantID, template); err != nil {
		return hostedissuer.CredentialTemplate{}, err
	}
	if err := i.audit(tenantID, "credential_template_updated", "", template.ID, template.Version); err != nil {
		return hostedissuer.CredentialTemplate{}, err
	}
	return template, nil
}

func (i *Issuer) CreateIssuanceRequest(tenantID, holderPairwiseDID, membershipClass string) (hostedissuer.IssuanceRequest, error) {
	return i.CreateBoardIssuanceRequest(tenantID, holderPairwiseDID, membershipClass, "", "")
}

func (i *Issuer) CreateBoardIssuanceRequest(tenantID, holderPairwiseDID, membershipClass, forumHostID, boardID string) (hostedissuer.IssuanceRequest, error) {
	template, err := i.store.ActiveCredentialTemplate(tenantID, "membership")
	if err != nil || !strings.HasPrefix(holderPairwiseDID, "did:jwk:") ||
		(membershipClass != "member" && membershipClass != "moderator") || strings.TrimSpace(forumHostID) == "" || strings.TrimSpace(boardID) == "" {
		return hostedissuer.IssuanceRequest{}, hostedissuer.ErrDelegationInvalid
	}
	id, err := hostedissuer.RandomControlPlaneIDForAPI("issuance")
	if err != nil {
		return hostedissuer.IssuanceRequest{}, err
	}
	payload := map[string]any{
		"template_id": template.ID, "template_version": template.Version,
		"holder_pairwise_did": holderPairwiseDID, "membership_class": membershipClass, "forum_host_id": forumHostID, "board_id": boardID,
	}
	encoded, _ := json.Marshal(payload)
	payloadDigest := sha256.Sum256(encoded)
	applicantDigest := sha256.Sum256([]byte(holderPairwiseDID))
	request := hostedissuer.IssuanceRequest{
		ID: id, TenantID: tenantID, TemplateID: template.ID, TemplateVersion: template.Version,
		ApplicantPairwiseDID: holderPairwiseDID, ApplicantHash: hex.EncodeToString(applicantDigest[:]),
		PayloadHash: hex.EncodeToString(payloadDigest[:]), MembershipClass: membershipClass, ForumHostID: forumHostID, BoardID: boardID,
		PolicySnapshot: map[string]any{
			"template_id": template.ID, "template_version": template.Version,
			"credential_type": template.CredentialType, "membership_class": membershipClass, "forum_host_id": forumHostID, "board_id": boardID,
			"approval_threshold": template.ApprovalThreshold,
		},
		ExpiresAt: i.now().Add(7 * 24 * time.Hour), CreatedAt: i.now().UTC(),
	}
	if err := i.store.PutIssuanceRequest(tenantID, request); err != nil {
		return hostedissuer.IssuanceRequest{}, err
	}
	if err := i.audit(tenantID, "issuance_requested", "", request.PayloadHash, template.Version); err != nil {
		return hostedissuer.IssuanceRequest{}, err
	}
	request.State = "pending"
	return request, nil
}

func (i *Issuer) DecideIssuanceRequest(tenantID, requestID, approverDID, decision, signedIntentHash string) (hostedissuer.IssuanceRequest, error) {
	request, err := i.store.IssuanceRequest(tenantID, requestID)
	if err != nil {
		return hostedissuer.IssuanceRequest{}, err
	}
	template, err := i.store.ActiveCredentialTemplate(tenantID, request.TemplateID)
	if err != nil || template.Version != request.TemplateVersion {
		return hostedissuer.IssuanceRequest{}, hostedissuer.ErrDelegationInvalid
	}
	updated, err := i.store.DecideIssuanceRequest(tenantID, hostedissuer.IssuanceApproval{
		TenantID: tenantID, RequestID: requestID, ApproverDID: approverDID,
		Decision: decision, SignedIntentHash: signedIntentHash, CreatedAt: i.now().UTC(),
	}, template.ApprovalThreshold)
	if err != nil {
		return hostedissuer.IssuanceRequest{}, err
	}
	if err := i.audit(tenantID, "issuance_"+decision, approverDID, signedIntentHash, template.Version); err != nil {
		return hostedissuer.IssuanceRequest{}, err
	}
	return updated, nil
}

func (i *Issuer) IssuanceRequests(tenantID, state string) ([]hostedissuer.IssuanceRequest, error) {
	if state != "" && state != "pending" && state != "approved" && state != "denied" && state != "offered" {
		return nil, hostedissuer.ErrDelegationInvalid
	}
	return i.store.IssuanceRequests(tenantID, state)
}

func (i *Issuer) SetCredentialStatus(tenantID, credentialID, status string) error {
	return i.SetCredentialStatusBy(tenantID, credentialID, status, "")
}

func (i *Issuer) SetCredentialStatusBy(tenantID, credentialID, status, actorDID string) error {
	if status != "active" && status != "suspended" && status != "revoked" {
		return hostedissuer.ErrDelegationInvalid
	}
	if err := i.store.SetCredentialStatus(tenantID, credentialID, status); err != nil {
		return err
	}
	return i.audit(tenantID, "credential_status_"+status, actorDID, credentialID, 1)
}

func (i *Issuer) CreateOfferForApprovedRequest(tenantID, requestID string) (map[string]any, error) {
	request, err := i.store.ConsumeApprovedIssuanceRequest(tenantID, requestID, i.now())
	if err != nil {
		return nil, err
	}
	offer, err := i.createBoardOffer(tenantID, request.ApplicantPairwiseDID, request.MembershipClass, request.ForumHostID, request.BoardID)
	if err != nil {
		return nil, err
	}
	if err := i.audit(tenantID, "credential_offer_created", "", request.PayloadHash, request.TemplateVersion); err != nil {
		return nil, err
	}
	return offer, nil
}

func (i *Issuer) ExchangeCode(tenantID, code string) (string, Access, error) {
	token, access, err := i.state.ExchangePreAuthorizedCode(code, tenantID)
	if err != nil {
		return "", Access{}, err
	}
	return token, access, nil
}

func (i *Issuer) Nonce() (string, error) { return i.state.IssueNonce() }

func (i *Issuer) Issue(ctx context.Context, tenantID, accessToken, proofJWT string) (vc.IssuedJWTCredential, error) {
	nonce, err := ProofNonce(proofJWT)
	if err != nil {
		return vc.IssuedJWTCredential{}, err
	}
	access, err := i.state.Access(accessToken)
	if err != nil || access.TenantID != tenantID || access.CredentialConfigurationID != "PoliticalPartyMembershipCredential-v1" {
		return vc.IssuedJWTCredential{}, ErrInvalidToken
	}
	holderJWK, err := VerifyJWTProof(proofJWT, i.CredentialIssuerURL(tenantID), nonce, i.now())
	if err != nil {
		return vc.IssuedJWTCredential{}, err
	}
	if pairwiseDID(holderJWK) != access.SubjectPairwiseDID || access.ForumHostID == "" || access.BoardID == "" {
		return vc.IssuedJWTCredential{}, errors.New("credential holder or board binding mismatch")
	}
	if err := i.state.ConsumeNonce(nonce); err != nil {
		return vc.IssuedJWTCredential{}, err
	}
	tenant, err := i.store.Tenant(tenantID)
	if err != nil {
		return vc.IssuedJWTCredential{}, err
	}
	signer, delegation, err := i.keys.ActiveSigner(ctx, tenantID)
	if err != nil || !contains(delegation.CredentialTypes, vc.MembershipCredentialType) {
		return vc.IssuedJWTCredential{}, errors.New("issuer delegation does not allow membership credentials")
	}
	if access.StatusIndex == nil {
		index, reserveErr := i.store.ReserveStatusIndex(tenantID)
		if reserveErr != nil {
			return vc.IssuedJWTCredential{}, reserveErr
		}
		access, err = i.state.PrepareCredential(accessToken, index, i.now())
		if err != nil {
			return vc.IssuedJWTCredential{}, err
		}
	}
	if access.StatusIndex == nil || access.IssuedAt == nil {
		return vc.IssuedJWTCredential{}, errors.New("credential issuance state is incomplete")
	}
	issued, err := vc.IssueMembershipJWT(signer, vc.MembershipIssueRequest{
		IssuerDID: tenant.OrganizationDID, IssuerURL: i.CredentialIssuerURL(tenantID),
		HolderPairwiseDID: access.SubjectPairwiseDID,
		HolderJWK:         map[string]string{"kty": holderJWK.KTY, "crv": holderJWK.CRV, "x": holderJWK.X, "y": holderJWK.Y},
		MembershipClass:   access.MembershipClass, StatusListIndex: *access.StatusIndex,
		ForumHostID:       access.ForumHostID,
		BoardID:           access.BoardID,
		StatusListBaseURL: i.CredentialIssuerURL(tenantID) + "/status", Now: *access.IssuedAt,
	})
	if err != nil {
		return vc.IssuedJWTCredential{}, err
	}
	policyHash := sha256.Sum256(delegation.CanonicalJSON)
	if err := i.store.PutCredentialRecord(tenantID, hostedissuer.CredentialRecord{
		CredentialID: issued.ID, CredentialHash: issued.Hash, CredentialType: vc.MembershipCredentialType,
		SubjectPairwiseHash: access.SubjectPairwiseHash, IssuedAt: issued.IssuedAt, ExpiresAt: issued.ExpiresAt,
		StatusIndex: *access.StatusIndex, Status: "active", PolicySnapshotHash: hex.EncodeToString(policyHash[:]),
	}); err != nil {
		return vc.IssuedJWTCredential{}, err
	}
	if err := i.state.MarkCredentialIssued(accessToken); err != nil {
		return vc.IssuedJWTCredential{}, err
	}
	if err := i.audit(tenantID, "credential_issued", "", issued.Hash, 1); err != nil {
		return vc.IssuedJWTCredential{}, err
	}
	return issued, nil
}

func (i *Issuer) audit(tenantID, eventType, actorDID, material string, policyVersion int64) error {
	id, err := hostedissuer.RandomControlPlaneIDForAPI("audit")
	if err != nil {
		return err
	}
	digest := sha256.Sum256([]byte(material))
	return i.store.AppendAudit(tenantID, hostedissuer.AuditEvent{
		ID: id, TenantID: tenantID, EventType: eventType, ActorDID: actorDID,
		RequestHash: hex.EncodeToString(digest[:]), PolicyVersion: policyVersion,
		CreatedAt: i.now().UTC(),
	})
}

func (i *Issuer) StatusList(ctx context.Context, tenantID, purpose string) (vc.IssuedStatusList, error) {
	tenant, err := i.store.Tenant(tenantID)
	if err != nil {
		return vc.IssuedStatusList{}, err
	}
	signer, _, err := i.keys.ActiveSigner(ctx, tenantID)
	if err != nil {
		return vc.IssuedStatusList{}, err
	}
	records, err := i.store.CredentialRecords(tenantID)
	if err != nil {
		return vc.IssuedStatusList{}, err
	}
	entries := make([]vc.CredentialStatusEntry, len(records))
	for index, record := range records {
		entries[index] = vc.CredentialStatusEntry{Index: record.StatusIndex, Status: record.Status}
	}
	url := i.CredentialIssuerURL(tenantID) + "/status/" + purpose + "/1"
	return vc.IssueBitstringStatusList(signer, tenant.OrganizationDID, url, purpose, entries, i.now())
}

func contains(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}
