package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"regexp"

	"github.com/trisaura/ansible_issuer/internal/commitment"
	"github.com/trisaura/ansible_issuer/internal/otp"
	"github.com/trisaura/ansible_issuer/internal/provider"
	"github.com/trisaura/ansible_issuer/internal/vc"
)

var (
	reDID   = regexp.MustCompile(`^did:(plc:[a-z2-7]{10,}|web:.+)$`)
	reEmail = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)
)

// Handler wires all VC HTTP endpoints.
type Handler struct {
	otpStore *otp.Store
	provider provider.TwIdentityProvider
	issuer   *vc.Issuer
	pepper   string
	mockMode bool
}

func NewHandler(
	otpStore *otp.Store,
	prov provider.TwIdentityProvider,
	iss *vc.Issuer,
	pepper string,
	mockMode bool,
) *Handler {
	return &Handler{
		otpStore: otpStore,
		provider: prov,
		issuer:   iss,
		pepper:   pepper,
		mockMode: mockMode,
	}
}

// Register mounts all VC endpoints on mux.
func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/v1/vc/request", h.request)
	mux.HandleFunc("POST /api/v1/vc/issue", h.issue)
	mux.HandleFunc("GET /api/v1/vc/status/{id}", h.status)
}

// POST /api/v1/vc/request — issue OTP for email verification.
func (h *Handler) request(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DID   string `json:"did"`
		Email string `json:"email"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	if !validateDID(w, body.DID) || !validateEmail(w, body.Email) {
		return
	}

	code, err := h.otpStore.Issue(body.DID, body.Email)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "otp_store_error")
		return
	}

	resp := map[string]any{
		"status": "otp_sent",
		"hint":   "check your inbox for a 6-digit code",
	}
	if h.mockMode {
		resp["hint"] = "mock mode — use this OTP directly"
		resp["otp"] = code
	}
	writeJSON(w, http.StatusOK, resp)
}

// POST /api/v1/vc/issue — verify OTP and return a signed TrisAuraHumanityCredential.
func (h *Handler) issue(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DID   string `json:"did"`
		Email string `json:"email"`
		OTP   string `json:"otp"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	if !validateDID(w, body.DID) || !validateEmail(w, body.Email) {
		return
	}
	if body.OTP == "" {
		writeError(w, http.StatusUnprocessableEntity, "missing_field")
		return
	}

	if err := h.otpStore.VerifyAndConsume(body.DID, body.Email, body.OTP); err != nil {
		if errors.Is(err, otp.ErrExpiredOTP) {
			writeError(w, http.StatusUnauthorized, "expired_otp")
		} else {
			writeError(w, http.StatusUnauthorized, "invalid_otp")
		}
		return
	}

	subject, err := h.provider.ProviderSubject(body.DID, body.Email)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "provider_error")
		return
	}
	comm := commitment.Compute(h.pepper, subject, "tw_natural_person_certificate")

	credMap, err := h.issuer.Issue(body.DID, comm)
	if err != nil {
		if errors.Is(err, vc.ErrDuplicateActiveCredential) {
			writeError(w, http.StatusConflict, "duplicate_active_credential")
			return
		}
		writeError(w, http.StatusInternalServerError, "issuance_error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"vc": credMap})
}

// GET /api/v1/vc/status/{id} — return credential status by hex ID suffix.
func (h *Handler) status(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing_id")
		return
	}
	writeError(w, http.StatusNotFound, "not_found")
}

func decodeJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return false
	}
	return true
}

func validateDID(w http.ResponseWriter, did string) bool {
	if did == "" {
		writeError(w, http.StatusUnprocessableEntity, "missing_field")
		return false
	}
	if !reDID.MatchString(did) {
		writeError(w, http.StatusUnprocessableEntity, "invalid_did")
		return false
	}
	return true
}

func validateEmail(w http.ResponseWriter, email string) bool {
	if email == "" {
		writeError(w, http.StatusUnprocessableEntity, "missing_field")
		return false
	}
	if !reEmail.MatchString(email) {
		writeError(w, http.StatusUnprocessableEntity, "invalid_email")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, code string) {
	writeJSON(w, status, map[string]any{"error": code})
}
