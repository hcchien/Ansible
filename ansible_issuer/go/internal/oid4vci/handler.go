package oid4vci

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/trisaura/ansible_issuer/internal/hostedissuer"
)

const preAuthorizedGrantType = "urn:ietf:params:oauth:grant-type:pre-authorized_code"

type Handler struct {
	issuer       *Issuer
	capabilities *hostedissuer.AdminCapabilityService
	governance   *hostedissuer.Governance
}

func NewHandler(issuer *Issuer, capabilities *hostedissuer.AdminCapabilityService, governance *hostedissuer.Governance) *Handler {
	return &Handler{issuer: issuer, capabilities: capabilities, governance: governance}
}

func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /.well-known/openid-credential-issuer/tenants/{tenant}", h.metadata)
	mux.HandleFunc("GET /.well-known/oauth-authorization-server/tenants/{tenant}", h.authorizationMetadata)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/credential-offers", h.offer)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/credential-templates/membership", h.putTemplate)
	mux.HandleFunc("POST /tenants/{tenant}/issuance-requests", h.apply)
	mux.HandleFunc("GET /api/v1/hosted-issuers/{tenant}/issuance-requests", h.listIssuanceRequests)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/issuance-requests/{request}/decisions", h.decide)
	mux.HandleFunc("POST /api/v1/hosted-issuers/{tenant}/credentials/{credential}/status", h.setCredentialStatus)
	mux.HandleFunc("POST /tenants/{tenant}/token", h.token)
	mux.HandleFunc("POST /tenants/{tenant}/nonce", h.nonce)
	mux.HandleFunc("POST /tenants/{tenant}/credential", h.credential)
	mux.HandleFunc("GET /tenants/{tenant}/status/{purpose}/1", h.statusList)
}

func (h *Handler) listIssuanceRequests(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	if !h.authorizeAdmin(r, tenantID, "issuer_admin:issuance") {
		writeOIDError(w, http.StatusForbidden, "access_denied")
		return
	}
	requests, err := h.issuer.IssuanceRequests(tenantID, r.URL.Query().Get("state"))
	if err != nil {
		writeOIDError(w, http.StatusBadRequest, "invalid_request_state")
		return
	}
	writeOIDJSON(w, http.StatusOK, map[string]any{"requests": requests})
}

func (h *Handler) metadata(w http.ResponseWriter, r *http.Request) {
	metadata, err := h.issuer.Metadata(r.PathValue("tenant"))
	if err != nil {
		writeOIDError(w, http.StatusNotFound, "invalid_credential_issuer")
		return
	}
	writeOIDJSON(w, http.StatusOK, metadata)
}

func (h *Handler) authorizationMetadata(w http.ResponseWriter, r *http.Request) {
	issuer := h.issuer.CredentialIssuerURL(r.PathValue("tenant"))
	writeOIDJSON(w, http.StatusOK, map[string]any{
		"issuer": issuer, "token_endpoint": issuer + "/token",
		"grant_types_supported":                           []string{preAuthorizedGrantType},
		"pre-authorized_grant_anonymous_access_supported": true,
	})
}

func (h *Handler) offer(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	if !h.authorizeAdmin(r, tenantID, "issuer_admin:issuance") {
		writeOIDError(w, http.StatusForbidden, "access_denied")
		return
	}
	var request struct {
		RequestID string `json:"request_id"`
	}
	if !decodeOIDJSON(w, r, &request) {
		return
	}
	offer, err := h.issuer.CreateOfferForApprovedRequest(tenantID, request.RequestID)
	if err != nil {
		writeOIDError(w, http.StatusUnprocessableEntity, "invalid_request")
		return
	}
	writeOIDJSON(w, http.StatusCreated, offer)
}

func (h *Handler) putTemplate(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	if !h.authorizeAdmin(r, tenantID, "issuer_admin:templates") {
		writeOIDError(w, http.StatusForbidden, "access_denied")
		return
	}
	var request struct {
		Version    int64 `json:"version"`
		MaxTTLDays int   `json:"max_ttl_days"`
		Active     bool  `json:"active"`
	}
	if !decodeOIDJSON(w, r, &request) {
		return
	}
	template, err := h.issuer.PutMembershipTemplate(tenantID, request.Version, request.MaxTTLDays, request.Active)
	if err != nil {
		writeOIDError(w, http.StatusUnprocessableEntity, "invalid_credential_template")
		return
	}
	writeOIDJSON(w, http.StatusCreated, map[string]any{"template": template})
}

func (h *Handler) apply(w http.ResponseWriter, r *http.Request) {
	var request struct {
		HolderPairwiseDID string `json:"holder_pairwise_did"`
		MembershipClass   string `json:"membership_class"`
		BoardID           string `json:"board_id"`
		ProofJWT          string `json:"proof_jwt"`
	}
	if !decodeOIDJSON(w, r, &request) {
		return
	}
	nonce, err := ProofNonce(request.ProofJWT)
	if err != nil {
		writeOIDError(w, http.StatusBadRequest, "invalid_proof")
		return
	}
	jwk, err := VerifyJWTProof(request.ProofJWT, h.issuer.CredentialIssuerURL(r.PathValue("tenant")), nonce, h.issuer.now())
	if err != nil || pairwiseDID(jwk) != request.HolderPairwiseDID || h.issuer.state.ConsumeNonce(nonce) != nil {
		writeOIDError(w, http.StatusBadRequest, "invalid_proof")
		return
	}
	created, err := h.issuer.CreateBoardIssuanceRequest(r.PathValue("tenant"), request.HolderPairwiseDID, request.MembershipClass, request.BoardID)
	if err != nil {
		writeOIDError(w, http.StatusUnprocessableEntity, "issuance_request_not_accepted")
		return
	}
	writeOIDJSON(w, http.StatusCreated, map[string]any{"request": created})
}

type issuanceDecision struct {
	Type         string    `json:"type"`
	Version      int       `json:"version"`
	TenantID     string    `json:"tenant_id"`
	RequestID    string    `json:"request_id"`
	Decision     string    `json:"decision"`
	IssuedAt     time.Time `json:"issued_at"`
	SignatureHex string    `json:"signature_hex,omitempty"`
}

type credentialStatusDecision struct {
	Type         string    `json:"type"`
	Version      int       `json:"version"`
	TenantID     string    `json:"tenant_id"`
	CredentialID string    `json:"credential_id"`
	Status       string    `json:"status"`
	IssuedAt     time.Time `json:"issued_at"`
	SignatureHex string    `json:"signature_hex,omitempty"`
}

func (h *Handler) decide(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	capability, err := h.capabilities.Authorize(bearer(r), tenantID, "issuer_admin:issuance")
	if err != nil || h.governance == nil {
		writeOIDError(w, http.StatusForbidden, "access_denied")
		return
	}
	var decision issuanceDecision
	if !decodeOIDJSON(w, r, &decision) {
		return
	}
	if decision.Type != "CredentialIssuanceDecision" || decision.Version != 1 ||
		decision.TenantID != tenantID || decision.RequestID != r.PathValue("request") ||
		(decision.Decision != "approve" && decision.Decision != "deny") ||
		decision.IssuedAt.IsZero() || h.issuer.now().Sub(decision.IssuedAt) < -30*time.Second ||
		h.issuer.now().Sub(decision.IssuedAt) > 5*time.Minute {
		writeOIDError(w, http.StatusUnprocessableEntity, "invalid_decision")
		return
	}
	signature, err := hex.DecodeString(decision.SignatureHex)
	unsigned := decision
	unsigned.SignatureHex = ""
	canonical, marshalErr := json.Marshal(unsigned)
	if err != nil || marshalErr != nil ||
		h.governance.VerifyAdministratorIntent(tenantID, capability.AdminDID, canonical, signature) != nil {
		writeOIDError(w, http.StatusUnprocessableEntity, "invalid_decision")
		return
	}
	digest := sha256.Sum256(canonical)
	updated, err := h.issuer.DecideIssuanceRequest(
		tenantID, decision.RequestID, capability.AdminDID, decision.Decision, hex.EncodeToString(digest[:]),
	)
	if err != nil {
		writeOIDError(w, http.StatusConflict, "decision_not_accepted")
		return
	}
	writeOIDJSON(w, http.StatusOK, map[string]any{"request": updated})
}

func (h *Handler) setCredentialStatus(w http.ResponseWriter, r *http.Request) {
	tenantID := r.PathValue("tenant")
	capability, err := h.capabilities.Authorize(bearer(r), tenantID, "issuer_admin:status")
	if err != nil || h.governance == nil {
		writeOIDError(w, http.StatusForbidden, "access_denied")
		return
	}
	var decision credentialStatusDecision
	if !decodeOIDJSON(w, r, &decision) {
		return
	}
	if decision.Type != "CredentialStatusDecision" || decision.Version != 1 ||
		decision.TenantID != tenantID || decision.CredentialID != r.PathValue("credential") ||
		(decision.Status != "active" && decision.Status != "suspended" && decision.Status != "revoked") ||
		decision.IssuedAt.IsZero() || h.issuer.now().Sub(decision.IssuedAt) < -30*time.Second ||
		h.issuer.now().Sub(decision.IssuedAt) > 5*time.Minute {
		writeOIDError(w, http.StatusUnprocessableEntity, "invalid_status_decision")
		return
	}
	signature, decodeErr := hex.DecodeString(decision.SignatureHex)
	unsigned := decision
	unsigned.SignatureHex = ""
	canonical, marshalErr := json.Marshal(unsigned)
	if decodeErr != nil || marshalErr != nil ||
		h.governance.VerifyAdministratorIntent(tenantID, capability.AdminDID, canonical, signature) != nil {
		writeOIDError(w, http.StatusUnprocessableEntity, "invalid_status_decision")
		return
	}
	if err := h.issuer.SetCredentialStatusBy(tenantID, decision.CredentialID, decision.Status, capability.AdminDID); err != nil {
		writeOIDError(w, http.StatusConflict, "status_decision_not_accepted")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func pairwiseDID(jwk HolderJWK) string {
	canonical, _ := json.Marshal(map[string]string{"crv": jwk.CRV, "kty": jwk.KTY, "x": jwk.X, "y": jwk.Y})
	return "did:jwk:" + base64.RawURLEncoding.EncodeToString(canonical)
}

func (h *Handler) token(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		writeOIDError(w, http.StatusBadRequest, "invalid_request")
		return
	}
	if r.Form.Get("grant_type") != preAuthorizedGrantType {
		writeOIDError(w, http.StatusBadRequest, "unsupported_grant_type")
		return
	}
	code := r.Form.Get("pre-authorized_code")
	if code == "" {
		// Some form decoders retain the spec parameter's historical underscore.
		code = r.Form.Get("pre_authorized_code")
	}
	token, access, err := h.issuer.ExchangeCode(r.PathValue("tenant"), code)
	if err != nil {
		writeOIDError(w, http.StatusBadRequest, "invalid_grant")
		return
	}
	writeOIDJSON(w, http.StatusOK, map[string]any{
		"access_token": token, "token_type": "Bearer", "expires_in": max(0, int(access.ExpiresAt.Sub(h.issuer.now()).Seconds())),
		"authorization_details": []map[string]any{{
			"type": "openid_credential", "credential_configuration_id": access.CredentialConfigurationID,
			"credential_identifiers": []string{access.CredentialConfigurationID},
		}},
	})
}

func (h *Handler) nonce(w http.ResponseWriter, r *http.Request) {
	nonce, err := h.issuer.Nonce()
	if err != nil {
		writeOIDError(w, http.StatusInternalServerError, "server_error")
		return
	}
	writeOIDJSON(w, http.StatusOK, map[string]any{"c_nonce": nonce})
}

func (h *Handler) credential(w http.ResponseWriter, r *http.Request) {
	token := bearer(r)
	if token == "" {
		w.Header().Set("WWW-Authenticate", `Bearer error="invalid_token"`)
		writeOIDError(w, http.StatusUnauthorized, "invalid_token")
		return
	}
	var request struct {
		CredentialConfigurationID string              `json:"credential_configuration_id"`
		Proofs                    map[string][]string `json:"proofs"`
	}
	if !decodeOIDJSON(w, r, &request) {
		return
	}
	proofs := request.Proofs["jwt"]
	if request.CredentialConfigurationID != "PoliticalPartyMembershipCredential-v1" || len(proofs) != 1 {
		writeOIDError(w, http.StatusBadRequest, "invalid_proof")
		return
	}
	issued, err := h.issuer.Issue(r.Context(), r.PathValue("tenant"), token, proofs[0])
	if err != nil {
		code := "invalid_proof"
		if errors.Is(err, ErrInvalidToken) {
			code = "invalid_token"
		} else if errors.Is(err, ErrInvalidNonce) {
			code = "invalid_nonce"
		}
		writeOIDError(w, http.StatusBadRequest, code)
		return
	}
	writeOIDJSON(w, http.StatusOK, map[string]any{"credentials": []map[string]any{{"credential": issued.JWT}}})
}

func (h *Handler) statusList(w http.ResponseWriter, r *http.Request) {
	purpose := r.PathValue("purpose")
	list, err := h.issuer.StatusList(r.Context(), r.PathValue("tenant"), purpose)
	if err != nil {
		writeOIDError(w, http.StatusNotFound, "status_list_not_found")
		return
	}
	w.Header().Set("Cache-Control", "public, max-age=300")
	w.Header().Set("Content-Type", "application/vc+jwt")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(list.JWT))
}

func (h *Handler) authorizeAdmin(r *http.Request, tenantID, scope string) bool {
	token := bearer(r)
	_, err := h.capabilities.Authorize(token, tenantID, scope)
	return err == nil
}

func bearer(r *http.Request) string {
	header := r.Header.Get("Authorization")
	if len(header) < 8 || !strings.EqualFold(header[:7], "Bearer ") {
		return ""
	}
	return strings.TrimSpace(header[7:])
}

func decodeOIDJSON(w http.ResponseWriter, r *http.Request, target any) bool {
	if contentType := r.Header.Get("Content-Type"); contentType != "" && !strings.HasPrefix(contentType, "application/json") {
		writeOIDError(w, http.StatusUnsupportedMediaType, "invalid_request")
		return false
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeOIDError(w, http.StatusBadRequest, "invalid_request")
		return false
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		writeOIDError(w, http.StatusBadRequest, "invalid_request")
		return false
	}
	return true
}

func writeOIDError(w http.ResponseWriter, status int, code string) {
	writeOIDJSON(w, status, map[string]any{"error": code})
}

func writeOIDJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
