package hostedapi

import (
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/trisaura/ansible_issuer/internal/hostedissuer"
)

type Handler struct {
	store      hostedissuer.Store
	control    *hostedissuer.ControlPlane
	governance *hostedissuer.Governance
	webauthn   *hostedissuer.AdminWebAuthnService
	capability *hostedissuer.AdminCapabilityService
	keys       *hostedissuer.KeyManager
	now        func() time.Time
}

type administratorEnrollmentRequest struct {
	Type                string    `json:"type"`
	Version             int       `json:"version"`
	TenantID            string    `json:"tenant_id"`
	AdministratorDID    string    `json:"administrator_did"`
	Role                string    `json:"role"`
	SigningAlgorithm    string    `json:"signing_algorithm"`
	PublicKeyHex        string    `json:"public_key_hex"`
	Custody             string    `json:"custody"`
	IssuedAt            time.Time `json:"issued_at"`
	ApplicantSignature  string    `json:"applicant_signature_hex,omitempty"`
	InviterSignatureHex string    `json:"inviter_signature_hex,omitempty"`
}

func NewHandler(store hostedissuer.Store, control *hostedissuer.ControlPlane, governance *hostedissuer.Governance, webauthn *hostedissuer.AdminWebAuthnService, capability *hostedissuer.AdminCapabilityService, keys *hostedissuer.KeyManager, now func() time.Time) *Handler {
	if now == nil {
		now = time.Now
	}
	return &Handler{store: store, control: control, governance: governance, webauthn: webauthn, capability: capability, keys: keys, now: now}
}

func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/hosted-issuers", h.bootstrap)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/admin/webauthn/register/options", h.registrationOptions)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/admin/webauthn/register/verify", h.registrationVerify)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/admin/webauthn/authenticate/options", h.authenticationOptions)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/admin/webauthn/authenticate/verify", h.authenticationVerify)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/administrators", h.addAdministrator)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/delegations", h.proposeDelegation)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/keys", h.registerKey)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/delegations/{delegation}/approve", h.approveDelegation)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/delegations/{delegation}/activate", h.activateDelegation)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/delegations/{delegation}/revoke", h.revokeDelegation)
	mux.HandleFunc("GET /api/v1/hosted-issuers/{tenant}/manifest", h.manifest)
	mux.HandleFunc("GET /api/v1/hosted-issuers/{tenant}/audit/export", h.auditExport)
}

func (h *Handler) registerKey(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	capability, authErr := h.authorize(r, tenantID, "issuer_admin:keys")
	if authErr != nil || h.keys == nil {
		writeError(w, http.StatusForbidden, "issuer_admin_capability_invalid")
		return
	}
	var request struct {
		KMSKeyVersion string `json:"kms_key_version"`
		Version       int64  `json:"version"`
	}
	if !decode(w, r, &request) {
		return
	}
	key, err := h.keys.RegisterHSMKey(r.Context(), tenantID, request.KMSKeyVersion, request.Version)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, "kms_key_not_accepted")
		return
	}
	if err := h.audit(tenantID, "signing_key_registered", capability.AdminDID, key.ID); err != nil {
		writeError(w, http.StatusInternalServerError, "audit_append_failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"key": key})
}

func (h *Handler) bootstrap(w http.ResponseWriter, r *http.Request) {
	var request hostedissuer.BootstrapRequest
	if !decode(w, r, &request) {
		return
	}
	tenant, err := h.control.Bootstrap(request)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, "invalid_bootstrap")
		return
	}
	if err := h.audit(tenant.ID, "tenant_bootstrapped", request.OwnerDID, tenant.ID); err != nil {
		writeError(w, http.StatusInternalServerError, "audit_append_failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"tenant": tenant})
}

func (h *Handler) registrationOptions(w http.ResponseWriter, r *http.Request) {
	var intent hostedissuer.EnrollmentIntent
	if !decode(w, r, &intent) {
		return
	}
	if intent.TenantID != r.PathValue("tenant") || h.control.VerifyEnrollmentIntent(intent) != nil {
		writeError(w, http.StatusUnauthorized, "invalid_enrollment_intent")
		return
	}
	id, options, err := h.webauthn.BeginRegistration(intent.TenantID, intent.AdminDID)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, "webauthn_registration_failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ceremony_id": id, "publicKey": options.Response})
}

func (h *Handler) registrationVerify(w http.ResponseWriter, r *http.Request) {
	tenantID, adminDID, ceremonyID := r.PathValue("tenant"), r.URL.Query().Get("admin_did"), r.URL.Query().Get("ceremony_id")
	if tenantID == "" || adminDID == "" || ceremonyID == "" || h.webauthn.FinishRegistration(tenantID, adminDID, ceremonyID, r) != nil {
		writeError(w, http.StatusUnauthorized, "webauthn_registration_failed")
		return
	}
	if err := h.audit(tenantID, "admin_passkey_registered", adminDID, ceremonyID); err != nil {
		writeError(w, http.StatusInternalServerError, "audit_append_failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"registered": true})
}

func (h *Handler) authenticationOptions(w http.ResponseWriter, r *http.Request) {
	var request struct {
		AdminDID string   `json:"admin_did"`
		Scopes   []string `json:"scopes"`
	}
	if !decode(w, r, &request) {
		return
	}
	if !h.activeAdministrator(r.PathValue("tenant"), request.AdminDID) {
		writeError(w, http.StatusUnauthorized, "webauthn_authentication_failed")
		return
	}
	id, options, err := h.webauthn.BeginAuthentication(r.PathValue("tenant"), request.AdminDID, request.Scopes)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "webauthn_authentication_failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ceremony_id": id, "publicKey": options.Response})
}

func (h *Handler) authenticationVerify(w http.ResponseWriter, r *http.Request) {
	tenantID, adminDID, ceremonyID := r.PathValue("tenant"), r.URL.Query().Get("admin_did"), r.URL.Query().Get("ceremony_id")
	token, capability, err := h.webauthn.FinishAuthentication(tenantID, adminDID, ceremonyID, r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "webauthn_authentication_failed")
		return
	}
	if !h.activeAdministrator(tenantID, adminDID) {
		_ = h.capability.RevokeAdministrator(tenantID, adminDID)
		writeError(w, http.StatusUnauthorized, "webauthn_authentication_failed")
		return
	}
	if err := h.audit(tenantID, "admin_authenticated", capability.AdminDID, ceremonyID); err != nil {
		writeError(w, http.StatusInternalServerError, "audit_append_failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"access_token": token, "token_type": "Bearer", "expires_at": capability.ExpiresAt,
		"scope": strings.Join(capability.Scopes, " "), "audience": capability.Audience,
	})
}

func (h *Handler) addAdministrator(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	capability, err := h.authorize(r, tenantID, "issuer_admin:admins")
	if err != nil {
		writeError(w, http.StatusForbidden, "issuer_admin_capability_invalid")
		return
	}
	var request administratorEnrollmentRequest
	if !decode(w, r, &request) {
		return
	}
	if request.Type != "IssuerAdministratorEnrollment" || request.Version != 1 ||
		request.TenantID != tenantID || request.AdministratorDID == "" || request.Role != "administrator" ||
		request.SigningAlgorithm != "p256-sha256" || request.Custody != "hardware" ||
		request.IssuedAt.IsZero() || h.now().Sub(request.IssuedAt) < -30*time.Second ||
		h.now().Sub(request.IssuedAt) > 5*time.Minute {
		writeError(w, http.StatusUnprocessableEntity, "administrator_enrollment_invalid")
		return
	}
	applicantSignature, applicantErr := hex.DecodeString(request.ApplicantSignature)
	inviterSignature, inviterErr := hex.DecodeString(request.InviterSignatureHex)
	unsigned := request
	unsigned.ApplicantSignature = ""
	unsigned.InviterSignatureHex = ""
	canonical, marshalErr := json.Marshal(unsigned)
	applicant := hostedissuer.Administrator{
		DID: request.AdministratorDID, Role: request.Role, State: "active",
		SigningAlgorithm: request.SigningAlgorithm, PublicKeyHex: request.PublicKeyHex, Custody: request.Custody,
	}
	if applicantErr != nil || inviterErr != nil || marshalErr != nil ||
		hostedissuer.VerifyAdministratorSignature(applicant, canonical, applicantSignature) != nil ||
		h.governance.VerifyAdministratorIntent(tenantID, capability.AdminDID, canonical, inviterSignature) != nil {
		writeError(w, http.StatusUnprocessableEntity, "administrator_enrollment_invalid")
		return
	}
	if err := h.store.PutAdministrator(tenantID, applicant); err != nil {
		writeError(w, http.StatusConflict, "administrator_not_added")
		return
	}
	if err := h.audit(tenantID, "administrator_added", capability.AdminDID, request.AdministratorDID); err != nil {
		writeError(w, http.StatusInternalServerError, "audit_append_failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"administrator": applicant})
}

func (h *Handler) proposeDelegation(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	capability, err := h.authorize(r, tenantID, "issuer_admin:delegations")
	if err != nil {
		writeError(w, http.StatusForbidden, "issuer_admin_capability_invalid")
		return
	}
	var request struct {
		ID               string          `json:"id"`
		SigningKeyID     string          `json:"signing_key_id"`
		CanonicalPayload json.RawMessage `json:"canonical_payload"`
	}
	if !decode(w, r, &request) {
		return
	}
	tenant, err := h.store.Tenant(tenantID)
	if err != nil {
		writeError(w, http.StatusNotFound, "tenant_not_found")
		return
	}
	delegation, err := h.governance.ValidateDelegation(tenant, request.CanonicalPayload)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, "invalid_delegation")
		return
	}
	if request.ID == "" {
		request.ID, err = randomID()
	}
	delegation.ID, delegation.SigningKeyID = request.ID, request.SigningKeyID
	if err != nil || delegation.SigningKeyID == "" || h.store.ProposeDelegation(tenantID, delegation) != nil {
		writeError(w, http.StatusConflict, "delegation_not_accepted")
		return
	}
	if err := h.audit(tenantID, "delegation_proposed", capability.AdminDID, delegation.PayloadHash); err != nil {
		writeError(w, http.StatusInternalServerError, "audit_append_failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"id": delegation.ID, "payload_hash": delegation.PayloadHash, "state": "proposed"})
}

func (h *Handler) approveDelegation(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	capability, err := h.authorize(r, tenantID, "issuer_admin:delegations")
	if err != nil {
		writeError(w, http.StatusForbidden, "issuer_admin_capability_invalid")
		return
	}
	var request struct {
		CanonicalPayload json.RawMessage `json:"canonical_payload"`
		SignatureHex     string          `json:"signature_hex"`
	}
	if !decode(w, r, &request) {
		return
	}
	signature, err := hex.DecodeString(request.SignatureHex)
	if err != nil || h.governance.ApproveDelegation(tenantID, r.PathValue("delegation"), capability.AdminDID, request.CanonicalPayload, signature) != nil {
		writeError(w, http.StatusUnprocessableEntity, "delegation_approval_invalid")
		return
	}
	if err := h.audit(tenantID, "delegation_approved", capability.AdminDID, r.PathValue("delegation")); err != nil {
		writeError(w, http.StatusInternalServerError, "audit_append_failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"approved": true})
}

func (h *Handler) activateDelegation(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	capability, err := h.authorize(r, tenantID, "issuer_admin:delegations")
	if err != nil {
		writeError(w, http.StatusForbidden, "issuer_admin_capability_invalid")
		return
	}
	if err := h.store.ActivateDelegation(tenantID, r.PathValue("delegation"), h.now()); err != nil {
		writeError(w, http.StatusConflict, "delegation_not_activatable")
		return
	}
	if err := h.audit(tenantID, "delegation_activated", capability.AdminDID, r.PathValue("delegation")); err != nil {
		writeError(w, http.StatusInternalServerError, "audit_append_failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"active": true})
}

func (h *Handler) revokeDelegation(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	capability, err := h.authorize(r, tenantID, "issuer_admin:delegations")
	if err != nil {
		writeError(w, http.StatusForbidden, "issuer_admin_capability_invalid")
		return
	}
	if err := h.store.RevokeDelegation(tenantID, r.PathValue("delegation"), h.now()); err != nil {
		writeError(w, http.StatusConflict, "delegation_not_revocable")
		return
	}
	if err := h.audit(tenantID, "delegation_revoked", capability.AdminDID, r.PathValue("delegation")); err != nil {
		writeError(w, http.StatusInternalServerError, "audit_append_failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"revoked": true})
}

func (h *Handler) manifest(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	tenant, err := h.store.Tenant(tenantID)
	if err != nil {
		writeError(w, http.StatusNotFound, "tenant_not_found")
		return
	}
	delegation, err := h.store.ActiveDelegation(tenantID, h.now())
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"tenant": tenant, "delegation": nil})
		return
	}
	key, err := h.store.SigningKey(tenantID, delegation.SigningKeyID)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "active_signing_key_unavailable")
		return
	}
	publicKey, err := ed25519PublicKeyFromPEM(key.PublicKeyPEM)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "active_signing_key_invalid")
		return
	}
	templates, err := h.store.ActiveCredentialTemplates(tenantID)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "credential_templates_unavailable")
		return
	}
	configurations := make([]map[string]any, 0, len(templates))
	for _, template := range templates {
		claims := make([]map[string]any, 0, len(template.ClaimAllowlist))
		for _, claim := range template.ClaimAllowlist {
			claims = append(claims, map[string]any{
				"path":              claim,
				"allowed_operators": []string{"equals"},
				"disclosable":       true,
			})
		}
		configurations = append(configurations, map[string]any{
			"id":              template.ID,
			"version":         template.Version,
			"credential_type": template.CredentialType,
			"claims":          claims,
			"max_ttl_days":    template.MaxTTLDays,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"tenant":     tenant,
		"delegation": delegation,
		"active_signing_key": map[string]any{
			"id":                   key.ID,
			"algorithm":            "EdDSA",
			"public_key_multibase": "u" + base64.RawURLEncoding.EncodeToString(publicKey),
			"protection_level":     key.ProtectionLevel,
			"version":              key.Version,
		},
		"credential_configurations": configurations,
	})
}

func ed25519PublicKeyFromPEM(raw string) (ed25519.PublicKey, error) {
	block, _ := pem.Decode([]byte(raw))
	if block == nil {
		return nil, errors.New("invalid public key PEM")
	}
	parsed, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	key, ok := parsed.(ed25519.PublicKey)
	if !ok || len(key) != ed25519.PublicKeySize {
		return nil, errors.New("active key is not Ed25519")
	}
	return key, nil
}

func (h *Handler) auditExport(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	if _, err := h.authorize(r, tenantID, "issuer_admin:audit"); err != nil {
		writeError(w, http.StatusForbidden, "issuer_admin_capability_invalid")
		return
	}
	events, err := h.store.Audit(tenantID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "audit_export_failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"events": events})
}

func (h *Handler) authorize(r *http.Request, tenantID, scope string) (hostedissuer.AdminCapability, error) {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		return hostedissuer.AdminCapability{}, hostedissuer.ErrCapabilityInvalid
	}
	return h.capability.Authorize(strings.TrimPrefix(header, "Bearer "), tenantID, scope)
}

func (h *Handler) activeAdministrator(tenantID, adminDID string) bool {
	admins, err := h.store.Administrators(tenantID)
	if err != nil {
		return false
	}
	for i := range admins {
		if admins[i].DID == adminDID && admins[i].State == "active" {
			return true
		}
	}
	return false
}

func (h *Handler) audit(tenantID, eventType, actorDID, requestMaterial string) error {
	tenant, err := h.store.Tenant(tenantID)
	if err != nil {
		return err
	}
	id, err := hostedissuer.RandomControlPlaneIDForAPI("audit")
	if err != nil {
		return err
	}
	digest := sha256.Sum256([]byte(requestMaterial))
	return h.store.AppendAudit(tenantID, hostedissuer.AuditEvent{
		ID:            id,
		TenantID:      tenantID,
		EventType:     eventType,
		ActorDID:      actorDID,
		RequestHash:   hex.EncodeToString(digest[:]),
		PolicyVersion: tenant.PolicyVersion,
		CreatedAt:     h.now().UTC(),
	})
}

func decode(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return false
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return false
	}
	return true
}

func writeError(w http.ResponseWriter, status int, code string) {
	writeJSON(w, status, map[string]any{"error": code})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func randomID() (string, error) {
	return hostedissuer.RandomControlPlaneIDForAPI("delegation")
}
