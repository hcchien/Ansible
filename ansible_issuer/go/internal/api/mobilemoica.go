package api

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/trisaura/ansible_issuer/internal/commitment"
	"github.com/trisaura/ansible_issuer/internal/provider"
	"github.com/trisaura/ansible_issuer/internal/vc"
)

const mobileMoicaAssuranceContext = "mobilemoica_rp_explicit_disclosure"

func (h *Handler) mobileMoicaStart(w http.ResponseWriter, r *http.Request) {
	if !h.mobileMoicaConfigured(w) {
		return
	}

	var body struct {
		HolderDID       string `json:"holder_did"`
		NationalID      string `json:"national_id"`
		ConsentVersion  string `json:"consent_version"`
		ConsentCopyHash string `json:"consent_copy_hash"`
		Locale          string `json:"locale"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	body.NationalID = strings.ToUpper(strings.TrimSpace(body.NationalID))
	if !validateDID(w, body.HolderDID) ||
		!validateNationalID(w, body.NationalID) ||
		!validateRequired(w, body.ConsentVersion) ||
		!validateRequired(w, body.ConsentCopyHash) {
		return
	}

	offerID, err := randomToken()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "random_error")
		return
	}
	state, err := randomToken()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "random_error")
		return
	}
	expiresAt := h.now().Add(h.mobileMoicaTTL)
	subjectCommitment := commitment.Compute(
		h.pepper,
		body.NationalID,
		vc.PersonhoodBindingTWNationalIDContext,
	)
	startResult, err := h.mobileMoicaBroker.Start(r.Context(), provider.MobileMoicaStartRequest{
		OfferID:         offerID,
		State:           state,
		HolderDID:       body.HolderDID,
		NationalID:      body.NationalID,
		ConsentVersion:  body.ConsentVersion,
		ConsentCopyHash: body.ConsentCopyHash,
		ReturnURL:       h.mobileMoicaReturnURL,
		ExpiresAt:       expiresAt,
	})
	if err != nil {
		h.logMobileMoicaRP("mobilemoica_rp_start", "broker_error", offerID, "error="+mobileMoicaRPErrorKind(err))
		h.writeMobileMoicaBrokerError(w, err)
		return
	}

	if err := h.mobileMoicaStore.CreateAuthSession(provider.AuthSession{
		OfferID:           offerID,
		DID:               body.HolderDID,
		State:             state,
		SubjectCommitment: subjectCommitment,
		ExpiresAt:         startResult.ExpiresAt,
	}); err != nil {
		h.logMobileMoicaRP("mobilemoica_rp_start", "session_error", offerID, "error=session_store")
		writeError(w, http.StatusInternalServerError, "provider_session_error")
		return
	}

	h.logMobileMoicaRP(
		"mobilemoica_rp_start",
		"created",
		offerID,
		"expires_at="+startResult.ExpiresAt.Format(time.RFC3339),
	)
	writeJSON(w, http.StatusOK, map[string]any{
		"offer_id":      offerID,
		"expires_at":    startResult.ExpiresAt.Format(time.RFC3339),
		"deep_link_url": startResult.DeepLinkURL,
	})
}

func (h *Handler) mobileMoicaStatus(w http.ResponseWriter, r *http.Request) {
	if !h.mobileMoicaConfigured(w) {
		return
	}

	offerID := r.PathValue("offer_id")
	if offerID == "" {
		writeError(w, http.StatusBadRequest, "missing_id")
		return
	}
	if _, err := h.mobileMoicaStore.GetVerifiedSession(offerID); err == nil {
		h.logMobileMoicaRP("mobilemoica_rp_status", "verified", offerID, "source=stored")
		writeJSON(w, http.StatusOK, map[string]any{
			"status":           "verified",
			"assurance_method": mobileMoicaAssuranceContext,
			"jurisdiction":     "TW",
		})
		return
	}

	store, ok := h.mobileMoicaStore.(interface {
		GetAuthSessionByOfferID(string) (provider.AuthSession, error)
	})
	if !ok {
		writeError(w, http.StatusInternalServerError, "provider_session_error")
		return
	}
	session, err := store.GetAuthSessionByOfferID(offerID)
	if err != nil {
		h.logMobileMoicaRP("mobilemoica_rp_status", "not_found", offerID)
		writeJSON(w, http.StatusOK, map[string]any{"status": "not_found"})
		return
	}

	result, err := h.mobileMoicaBroker.Verify(r.Context(), offerID, session.State)
	if err != nil {
		if errors.Is(err, provider.ErrMobileMoicaResultPending) {
			h.logMobileMoicaRP("mobilemoica_rp_status", "pending", offerID, "expires_at="+session.ExpiresAt.Format(time.RFC3339))
			writeJSON(w, http.StatusOK, map[string]any{
				"status":     "pending",
				"expires_at": session.ExpiresAt.Format(time.RFC3339),
			})
			return
		}
		h.logMobileMoicaRP("mobilemoica_rp_status", "broker_error", offerID, "error="+mobileMoicaRPErrorKind(err))
		h.writeMobileMoicaBrokerError(w, err)
		return
	}

	consumed, err := h.mobileMoicaStore.ConsumeAuthState(session.State, result.ReplayID)
	if err != nil {
		h.logMobileMoicaRP("mobilemoica_rp_status", "state_error", offerID, "error="+mobileMoicaRPErrorKind(err))
		h.writeSessionError(w, err)
		return
	}
	expiresAt := consumed.ExpiresAt
	if !result.ExpiresAt.IsZero() && result.ExpiresAt.Before(expiresAt) {
		expiresAt = result.ExpiresAt
	}
	comm := consumed.SubjectCommitment
	if comm == "" {
		h.logMobileMoicaRP("mobilemoica_rp_status", "session_error", offerID, "error=missing_personhood_binding")
		writeError(w, http.StatusInternalServerError, "provider_session_error")
		return
	}
	if err := h.mobileMoicaStore.StoreVerifiedSession(provider.VerifiedSession{
		OfferID:           consumed.OfferID,
		DID:               consumed.DID,
		SubjectCommitment: comm,
		VerifiedAt:        h.now(),
		ExpiresAt:         expiresAt,
	}); err != nil {
		h.logMobileMoicaRP("mobilemoica_rp_status", "session_error", offerID, "error=session_store")
		writeError(w, http.StatusInternalServerError, "provider_session_error")
		return
	}

	h.logMobileMoicaRP(
		"mobilemoica_rp_status",
		"verified",
		offerID,
		"assurance_method="+mobileMoicaAssuranceContext,
		"expires_at="+expiresAt.Format(time.RFC3339),
	)
	writeJSON(w, http.StatusOK, map[string]any{
		"status":           "verified",
		"assurance_method": mobileMoicaAssuranceContext,
		"jurisdiction":     "TW",
	})
}

func (h *Handler) mobileMoicaIssue(w http.ResponseWriter, r *http.Request) {
	if !h.mobileMoicaConfigured(w) {
		return
	}

	var body struct {
		HolderDID string `json:"holder_did"`
		OfferID   string `json:"offer_id"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	if !validateDID(w, body.HolderDID) || !validateRequired(w, body.OfferID) {
		return
	}

	verified, err := h.mobileMoicaStore.ConsumeVerifiedSession(body.OfferID)
	if err != nil {
		if errors.Is(err, provider.ErrVerifiedNotFound) {
			h.logMobileMoicaRP("mobilemoica_rp_issue", "denied", body.OfferID, "reason=provider_not_verified")
			writeError(w, http.StatusConflict, "provider_not_verified")
			return
		}
		h.logMobileMoicaRP("mobilemoica_rp_issue", "session_error", body.OfferID, "error="+mobileMoicaRPErrorKind(err))
		writeError(w, http.StatusInternalServerError, "provider_session_error")
		return
	}
	if verified.DID != body.HolderDID {
		h.logMobileMoicaRP("mobilemoica_rp_issue", "denied", body.OfferID, "reason=state_mismatch")
		writeError(w, http.StatusUnauthorized, "state_mismatch")
		return
	}

	credMap, err := h.issuer.IssueMobileMoicaRP(body.HolderDID, verified.SubjectCommitment)
	if err != nil {
		if errors.Is(err, vc.ErrDuplicateActiveCredential) {
			h.logMobileMoicaRP("mobilemoica_rp_issue", "denied", body.OfferID, "reason=duplicate_active_credential")
			writeError(w, http.StatusConflict, "duplicate_active_credential")
			return
		}
		h.logMobileMoicaRP("mobilemoica_rp_issue", "issuance_error", body.OfferID, "error=issuer")
		writeError(w, http.StatusInternalServerError, "issuance_error")
		return
	}

	h.logMobileMoicaRP("mobilemoica_rp_issue", "issued", body.OfferID, "credential_type=TrisAuraHumanityCredential")
	writeJSON(w, http.StatusOK, map[string]any{"vc": credMap})
}

func (h *Handler) mobileMoicaConfigured(w http.ResponseWriter) bool {
	if !h.mobileMoicaEnabled ||
		h.mobileMoicaStore == nil ||
		h.mobileMoicaBroker == nil ||
		provider.ValidateMobileMoicaApprovalConfig(h.mobileMoicaApproval) != nil {
		writeError(w, http.StatusServiceUnavailable, "mobilemoica_rp_unconfigured")
		return false
	}
	return true
}

func validateNationalID(w http.ResponseWriter, nationalID string) bool {
	if !reNationalID.MatchString(nationalID) {
		writeError(w, http.StatusUnprocessableEntity, "invalid_national_id")
		return false
	}
	return true
}

func (h *Handler) writeMobileMoicaBrokerError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, provider.ErrMobileMoicaProductionUnavailable):
		writeError(w, http.StatusServiceUnavailable, "mobilemoica_production_unavailable")
	case errors.Is(err, provider.ErrMobileMoicaOfferNotFound):
		writeError(w, http.StatusNotFound, "not_found")
	default:
		writeError(w, http.StatusUnauthorized, "invalid_provider_proof")
	}
}

func (h *Handler) logMobileMoicaRP(event, status, offerID string, fields ...string) {
	parts := []string{"event=" + event, "status=" + status}
	if offerID != "" {
		parts = append(parts, "offer_ref="+mobileMoicaRPOfferRef(offerID))
	}
	parts = append(parts, fields...)
	log.Print(strings.Join(parts, " "))
}

func mobileMoicaRPOfferRef(offerID string) string {
	sum := sha256.Sum256([]byte(offerID))
	return hex.EncodeToString(sum[:6])
}

func mobileMoicaRPErrorKind(err error) string {
	switch {
	case errors.Is(err, provider.ErrMobileMoicaProductionUnavailable):
		return "production_unavailable"
	case errors.Is(err, provider.ErrMobileMoicaOfferNotFound):
		return "offer_not_found"
	case errors.Is(err, provider.ErrMobileMoicaResultPending):
		return "result_pending"
	case errors.Is(err, provider.ErrMobileMoicaChecksumConfig):
		return "checksum_config"
	case errors.Is(err, provider.ErrMobileMoicaChecksumInvalid):
		return "checksum_invalid"
	case errors.Is(err, provider.ErrMobileMoicaTicketInvalid):
		return "ticket_invalid"
	case errors.Is(err, provider.ErrStateNotFound):
		return "state_not_found"
	case errors.Is(err, provider.ErrExpiredSessionState):
		return "expired_session_state"
	case errors.Is(err, provider.ErrVerifiedNotFound):
		return "verified_not_found"
	default:
		return "unknown"
	}
}
