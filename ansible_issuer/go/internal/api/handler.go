package api

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"regexp"
	"time"

	"github.com/trisaura/ansible_issuer/internal/commitment"
	"github.com/trisaura/ansible_issuer/internal/metrics"
	"github.com/trisaura/ansible_issuer/internal/otp"
	"github.com/trisaura/ansible_issuer/internal/provider"
	"github.com/trisaura/ansible_issuer/internal/vc"
)

var (
	reDID            = regexp.MustCompile(`^did:(plc:[a-z2-7]{10,}|web:.+)$`)
	reEmail          = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)
	reNationality    = regexp.MustCompile(`^[A-Z]{3}$`)
	reNationalID     = regexp.MustCompile(`^[A-Z][0-9]{9}$`)
	rePersonhoodHash = regexp.MustCompile(`^[A-Za-z0-9:_-]{16,128}$`)
)

// Handler wires all VC HTTP endpoints.
type Handler struct {
	otpStore *otp.Store
	provider provider.TwIdentityProvider
	issuer   *vc.Issuer
	pepper   string
	mockMode bool

	twStore    provider.SessionStore
	twVerifier provider.ProofVerifier
	twAuthURL  string
	twTTL      time.Duration
	twCounters AuditCounters
	now        func() time.Time

	mobileMoicaStore     provider.SessionStore
	mobileMoicaBroker    provider.MobileMoicaRPBroker
	mobileMoicaEnabled   bool
	mobileMoicaApproval  provider.MobileMoicaApprovalConfig
	mobileMoicaReturnURL string
	mobileMoicaTTL       time.Duration

	passportVerifier PassportBindingVerifier

	metrics *metrics.Registry
}

type TWProviderConfig struct {
	SessionStore provider.SessionStore
	Verifier     provider.ProofVerifier
	BaseAuthURL  string
	TTL          time.Duration
	Retention    time.Duration
	Counters     AuditCounters
}

type MobileMoicaRPConfig struct {
	Enabled   bool
	Store     provider.SessionStore
	Broker    provider.MobileMoicaRPBroker
	Approval  provider.MobileMoicaApprovalConfig
	ReturnURL string
	TTL       time.Duration
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
		now:      time.Now,
		metrics:  metrics.NewRegistry(),
	}
}

// Metrics exposes the issuer's metric registry (for the /metrics scrape target).
func (h *Handler) Metrics() *metrics.Registry {
	return h.metrics
}

// Register mounts all VC endpoints on mux.
//
// Every endpoint is wrapped with request counting (Phase 0 — observability
// baseline); /metrics serves the Prometheus exposition and is intentionally
// unwrapped so scrapes do not inflate the request series.
func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /healthz", h.healthz)
	mux.HandleFunc("GET /readyz", h.readyz)
	mux.HandleFunc("GET /metrics", h.metrics.Handler())
	mux.HandleFunc("GET /.well-known/did.json", h.didDocument)
	mux.HandleFunc("POST /api/v1/vc/request", h.instrument("vc_request", h.request))
	mux.HandleFunc("POST /api/v1/vc/issue", h.instrument("vc_issue", h.issue))
	mux.HandleFunc("GET /api/v1/vc/status/{id}", h.instrument("vc_status", h.status))
	mux.HandleFunc("POST /api/v1/vc/tw/start", h.instrument("vc_tw_start", h.twStart))
	mux.HandleFunc("POST /api/v1/vc/tw/callback", h.instrument("vc_tw_callback", h.twCallback))
	mux.HandleFunc("GET /api/v1/vc/tw/status/{offer_id}", h.instrument("vc_tw_status", h.twStatus))
	mux.HandleFunc("POST /api/v1/vc/tw/issue", h.instrument("vc_tw_issue", h.twIssue))
	mux.HandleFunc("POST /api/v1/vc/mobilemoica/start", h.instrument("vc_mobilemoica_start", h.mobileMoicaStart))
	mux.HandleFunc("GET /api/v1/vc/mobilemoica/status/{offer_id}", h.instrument("vc_mobilemoica_status", h.mobileMoicaStatus))
	mux.HandleFunc("POST /api/v1/vc/mobilemoica/issue", h.instrument("vc_mobilemoica_issue", h.mobileMoicaIssue))
	mux.HandleFunc("POST /api/v1/vc/passport/issue", h.instrument("vc_passport_issue", h.passportIssue))
}

// instrument wraps a handler with request counting and error counting (4xx/5xx)
// keyed by a stable endpoint label.
func (h *Handler) instrument(endpoint string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		h.metrics.IncRequest(endpoint)
		sw := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next(sw, r)
		if sw.status >= 400 {
			h.metrics.IncError(endpoint)
		}
	}
}

// statusRecorder captures the response status so the wrapper can classify
// errors without the handlers having to report them.
type statusRecorder struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (s *statusRecorder) WriteHeader(code int) {
	if !s.wroteHeader {
		s.status = code
		s.wroteHeader = true
	}
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Write(b []byte) (int, error) {
	s.wroteHeader = true
	return s.ResponseWriter.Write(b)
}

func (h *Handler) ConfigureTWProvider(config TWProviderConfig) {
	h.twStore = config.SessionStore
	h.twVerifier = config.Verifier
	h.twAuthURL = config.BaseAuthURL
	h.twTTL = config.TTL
	h.twCounters = config.Counters
	if h.twTTL <= 0 {
		h.twTTL = 5 * time.Minute
	}
	if h.now == nil {
		h.now = time.Now
	}
}

func (h *Handler) ConfigureMobileMoicaRP(config MobileMoicaRPConfig) {
	h.mobileMoicaEnabled = config.Enabled
	h.mobileMoicaStore = config.Store
	h.mobileMoicaBroker = config.Broker
	h.mobileMoicaApproval = config.Approval
	h.mobileMoicaReturnURL = config.ReturnURL
	h.mobileMoicaTTL = config.TTL
	if h.mobileMoicaReturnURL == "" {
		h.mobileMoicaReturnURL = "trisaura://mobilemoica/callback"
	}
	if h.mobileMoicaTTL <= 0 {
		h.mobileMoicaTTL = 5 * time.Minute
	}
	if h.now == nil {
		h.now = time.Now
	}
}

func (h *Handler) ConfigurePassport(config PassportConfig) {
	h.passportVerifier = config.Verifier
}

func (h *Handler) healthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

// didDocument serves the issuer's did:web DID document so external W3C verifiers
// can resolve the assertion key used in issued credential proofs.
func (h *Handler) didDocument(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, h.issuer.DIDDocument())
}

func (h *Handler) readyz(w http.ResponseWriter, r *http.Request) {
	if h.twStore == nil || h.twVerifier == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{
			"status":      "not_ready",
			"tw_provider": "unconfigured",
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":      "ready",
		"tw_provider": "configured",
	})
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

// POST /api/v1/vc/issue — verify OTP and return a signed EmailCredential.
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

	credMap, err := h.issuer.IssueEmail(body.DID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "issuance_error")
		return
	}

	h.metrics.IncCredentialIssued("email")
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

func (h *Handler) twStart(w http.ResponseWriter, r *http.Request) {
	if !h.twConfigured(w) {
		return
	}

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
	expiresAt := h.now().Add(h.twTTL)
	if err := h.twStore.CreateAuthSession(provider.AuthSession{
		OfferID:   offerID,
		DID:       body.DID,
		Email:     body.Email,
		State:     state,
		ExpiresAt: expiresAt,
	}); err != nil {
		writeError(w, http.StatusInternalServerError, "provider_session_error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"offer_id":          offerID,
		"state":             state,
		"authorization_url": authorizationURL(h.twAuthURL, offerID, state),
		"expires_at":        expiresAt.Format(time.RFC3339),
	})
}

func (h *Handler) twCallback(w http.ResponseWriter, r *http.Request) {
	if !h.twConfigured(w) {
		return
	}

	var callback map[string]string
	if !decodeJSON(w, r, &callback) {
		return
	}

	assertion, err := h.twVerifier.Verify(callback)
	if err != nil {
		h.writeProofError(w, err)
		return
	}

	session, err := h.twStore.ConsumeAuthState(assertion.State, assertion.ReplayID)
	if err != nil {
		h.writeSessionError(w, err)
		return
	}

	expiresAt := session.ExpiresAt
	if assertion.ExpiresAt.Before(expiresAt) {
		expiresAt = assertion.ExpiresAt
	}
	comm := commitment.Compute(h.pepper, assertion.ProviderSubject, assertion.AssuranceContext)
	if err := h.twStore.StoreVerifiedSession(provider.VerifiedSession{
		OfferID:           session.OfferID,
		DID:               session.DID,
		Email:             session.Email,
		SubjectCommitment: comm,
		VerifiedAt:        h.now(),
		ExpiresAt:         expiresAt,
	}); err != nil {
		writeError(w, http.StatusInternalServerError, "provider_session_error")
		return
	}

	h.incrementAuditCounter("tw_callback_verified")
	writeJSON(w, http.StatusOK, map[string]any{"status": "verified", "offer_id": session.OfferID})
}

func (h *Handler) twStatus(w http.ResponseWriter, r *http.Request) {
	if !h.twConfigured(w) {
		return
	}

	offerID := r.PathValue("offer_id")
	if offerID == "" {
		writeError(w, http.StatusBadRequest, "missing_id")
		return
	}
	if _, err := h.twStore.GetVerifiedSession(offerID); err == nil {
		writeJSON(w, http.StatusOK, map[string]any{"status": "verified"})
		return
	}
	if store, ok := h.twStore.(interface {
		GetAuthSessionByOfferID(string) (provider.AuthSession, error)
	}); ok {
		if _, err := store.GetAuthSessionByOfferID(offerID); err == nil {
			writeJSON(w, http.StatusOK, map[string]any{"status": "pending"})
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "not_found"})
}

func (h *Handler) twIssue(w http.ResponseWriter, r *http.Request) {
	if !h.twConfigured(w) {
		return
	}

	var body struct {
		DID     string `json:"did"`
		Email   string `json:"email"`
		OfferID string `json:"offer_id"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	if !validateDID(w, body.DID) || !validateEmail(w, body.Email) {
		return
	}
	if body.OfferID == "" {
		writeError(w, http.StatusUnprocessableEntity, "missing_field")
		return
	}

	verified, err := h.twStore.ConsumeVerifiedSession(body.OfferID)
	if err != nil {
		if errors.Is(err, provider.ErrVerifiedNotFound) {
			writeError(w, http.StatusConflict, "provider_not_verified")
			return
		}
		writeError(w, http.StatusInternalServerError, "provider_session_error")
		return
	}
	if verified.DID != body.DID || verified.Email != body.Email {
		writeError(w, http.StatusUnauthorized, "state_mismatch")
		return
	}

	credMap, err := h.issuer.Issue(body.DID, verified.SubjectCommitment)
	if err != nil {
		if errors.Is(err, vc.ErrDuplicateActiveCredential) {
			writeError(w, http.StatusConflict, "duplicate_active_credential")
			return
		}
		writeError(w, http.StatusInternalServerError, "issuance_error")
		return
	}

	h.metrics.IncCredentialIssued("email")
	writeJSON(w, http.StatusOK, map[string]any{"vc": credMap})
}

func (h *Handler) twConfigured(w http.ResponseWriter) bool {
	if h.twStore == nil || h.twVerifier == nil {
		writeError(w, http.StatusServiceUnavailable, "tw_provider_unconfigured")
		return false
	}
	return true
}

func (h *Handler) passportIssue(w http.ResponseWriter, r *http.Request) {
	if h.passportVerifier == nil {
		writeError(w, http.StatusServiceUnavailable, "passport_verifier_unconfigured")
		return
	}

	var body struct {
		DID                 string `json:"did"`
		Nationality         string `json:"nationality"`
		NationalIDHash      string `json:"national_id_hash"`
		PassportNumberHash  string `json:"passport_number_hash"`
		ZKPProof            string `json:"zkp_proof"`
		ZKPCircuitVersion   string `json:"zkp_circuit_version"`
		VerificationKeyHash string `json:"verification_key_hash"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	if !validateDID(w, body.DID) ||
		!validateNationality(w, body.Nationality) ||
		!validatePersonhoodHash(w, body.NationalIDHash, "invalid_national_id_hash") ||
		!validatePersonhoodHash(w, body.PassportNumberHash, "invalid_passport_number_hash") ||
		!validateRequired(w, body.ZKPProof) ||
		!validateRequired(w, body.ZKPCircuitVersion) ||
		!validateRequired(w, body.VerificationKeyHash) {
		return
	}

	binding, err := h.passportVerifier.VerifyPassportBinding(PassportBindingProof{
		DID:                 body.DID,
		Nationality:         body.Nationality,
		NationalIDHash:      body.NationalIDHash,
		PassportNumberHash:  body.PassportNumberHash,
		ZKPProof:            body.ZKPProof,
		ZKPCircuitVersion:   body.ZKPCircuitVersion,
		VerificationKeyHash: body.VerificationKeyHash,
	})
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid_passport_proof")
		return
	}
	if binding.NationalIDHash != body.NationalIDHash ||
		binding.PassportNumberHash != body.PassportNumberHash ||
		binding.Nationality != body.Nationality {
		writeError(w, http.StatusUnauthorized, "invalid_passport_proof")
		return
	}

	credMap, err := h.issuer.IssuePassport(
		body.DID,
		binding.Nationality,
		binding.NationalIDHash,
		binding.PassportNumberHash,
	)
	if err != nil {
		if errors.Is(err, vc.ErrDuplicatePersonhoodBinding) {
			writeError(w, http.StatusConflict, "personhood_already_bound")
			return
		}
		writeError(w, http.StatusInternalServerError, "issuance_error")
		return
	}

	h.metrics.IncCredentialIssued("passport")
	writeJSON(w, http.StatusOK, map[string]any{"vc": credMap})
}

func validateNationality(w http.ResponseWriter, nationality string) bool {
	if !reNationality.MatchString(nationality) {
		writeError(w, http.StatusUnprocessableEntity, "invalid_nationality")
		return false
	}
	return true
}

func validatePersonhoodHash(w http.ResponseWriter, value, errorCode string) bool {
	if !rePersonhoodHash.MatchString(value) {
		writeError(w, http.StatusUnprocessableEntity, errorCode)
		return false
	}
	return true
}

func validateRequired(w http.ResponseWriter, value string) bool {
	if value == "" {
		writeError(w, http.StatusUnprocessableEntity, "missing_field")
		return false
	}
	return true
}

func (h *Handler) writeProofError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, provider.ErrMissingProviderProofValue):
		h.incrementAuditCounter("tw_callback_missing_provider_proof")
		writeError(w, http.StatusUnprocessableEntity, "missing_provider_proof")
	case errors.Is(err, provider.ErrProviderAudience), errors.Is(err, provider.ErrProviderSignature), errors.Is(err, provider.ErrProviderExpiry):
		h.incrementAuditCounter("tw_callback_invalid_provider_proof")
		writeError(w, http.StatusUnauthorized, "invalid_provider_proof")
	default:
		h.incrementAuditCounter("tw_callback_invalid_provider_proof")
		writeError(w, http.StatusUnauthorized, "invalid_provider_proof")
	}
}

func (h *Handler) writeSessionError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, provider.ErrReplay):
		h.incrementAuditCounter("tw_callback_replay")
		writeError(w, http.StatusConflict, "callback_replay")
	case errors.Is(err, provider.ErrStateNotFound):
		h.incrementAuditCounter("tw_callback_state_mismatch")
		writeError(w, http.StatusUnauthorized, "state_mismatch")
	case errors.Is(err, provider.ErrExpiredSessionState):
		h.incrementAuditCounter("tw_callback_expired_session")
		writeError(w, http.StatusUnauthorized, "expired_session")
	default:
		h.incrementAuditCounter("tw_callback_session_error")
		writeError(w, http.StatusInternalServerError, "provider_session_error")
	}
}

func (h *Handler) incrementAuditCounter(event string) {
	if h.twCounters != nil {
		h.twCounters.Increment(event)
	}
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

func randomToken() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(b[:]), nil
}

func authorizationURL(baseURL, offerID, state string) string {
	u, err := url.Parse(baseURL)
	if err != nil {
		return baseURL
	}
	q := u.Query()
	q.Set("offer_id", offerID)
	q.Set("state", state)
	u.RawQuery = q.Encode()
	return u.String()
}
