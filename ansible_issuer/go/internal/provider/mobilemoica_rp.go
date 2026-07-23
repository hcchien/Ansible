package provider

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/digitorus/pkcs7"
)

var (
	ErrMobileMoicaApprovalMissing       = errors.New("mobilemoica approval missing")
	ErrMobileMoicaChecksumConfig        = errors.New("mobilemoica checksum config")
	ErrMobileMoicaChecksumInvalid       = errors.New("mobilemoica checksum invalid")
	ErrMobileMoicaOfferNotFound         = errors.New("mobilemoica offer not found")
	ErrMobileMoicaResultPending         = errors.New("mobilemoica result pending")
	ErrMobileMoicaTicketInvalid         = errors.New("mobilemoica ticket invalid")
	ErrMobileMoicaSignedContentInvalid  = errors.New("mobilemoica signed content invalid")
	ErrMobileMoicaCertificateInvalid    = errors.New("mobilemoica certificate invalid")
	ErrMobileMoicaCertificateRevoked    = errors.New("mobilemoica certificate revoked")
	ErrMobileMoicaProviderUnavailable   = errors.New("mobilemoica provider unavailable")
	ErrMobileMoicaProductionUnavailable = errors.New("mobilemoica production adapter unavailable")
)

const mobileMoicaChecksumIVSize = 12

type MobileMoicaApprovalConfig struct {
	LegalApprovalID        string
	PrivacyApprovalID      string
	SecurityApprovalID     string
	ConstitutionApprovalID string
}

func ValidateMobileMoicaApprovalConfig(config MobileMoicaApprovalConfig) error {
	if config.LegalApprovalID == "" ||
		config.PrivacyApprovalID == "" ||
		config.SecurityApprovalID == "" ||
		config.ConstitutionApprovalID == "" {
		return ErrMobileMoicaApprovalMissing
	}
	return nil
}

type MobileMoicaTicketChecksumInput struct {
	TransactionID string
	ServiceID     string
	NationalID    string
	OpCode        string
	OpMode        string
	Hint          string
	SignData      string
}

func MobileMoicaTicketChecksumPayload(input MobileMoicaTicketChecksumInput) string {
	payload := input.TransactionID +
		input.ServiceID +
		input.NationalID +
		input.OpCode +
		input.OpMode +
		input.Hint
	if strings.EqualFold(input.OpCode, "SIGN") {
		payload += input.SignData
	}
	return payload
}

func MobileMoicaResultChecksumPayload(transactionID, serviceID, spTicketID string) string {
	return transactionID + serviceID + spTicketID
}

func MobileMoicaTicketResponseChecksumPayload(transactionID, errorCode, spTicket string) string {
	return transactionID + errorCode + spTicket
}

func MobileMoicaSignResultResponseChecksumPayload(transactionID, errorCode, hashedIDNumber, signedResponse string) string {
	return transactionID + errorCode + hashedIDNumber + signedResponse
}

// GenerateMobileMoicaSPChecksum prefixes the AES-GCM payload with a fresh
// 12-byte IV. GenerateMobileMoicaSPChecksumWithIV is reserved for deterministic
// interoperability tests against the MobileMoica v2.9 fixed-IV examples.
func GenerateMobileMoicaSPChecksum(payload, encodedAPIKey string) (string, error) {
	iv := make([]byte, mobileMoicaChecksumIVSize)
	if _, err := rand.Read(iv); err != nil {
		return "", fmt.Errorf("%w: random IV", ErrMobileMoicaChecksumConfig)
	}
	return GenerateMobileMoicaSPChecksumWithIV(payload, encodedAPIKey, iv)
}

func GenerateMobileMoicaSPChecksumWithIV(payload, encodedAPIKey string, iv []byte) (string, error) {
	if len(iv) != mobileMoicaChecksumIVSize {
		return "", fmt.Errorf("%w: IV must be %d bytes", ErrMobileMoicaChecksumConfig, mobileMoicaChecksumIVSize)
	}
	gcm, err := mobileMoicaChecksumGCM(encodedAPIKey)
	if err != nil {
		return "", err
	}

	digestHex := mobileMoicaSHA256Hex(payload)
	ciphertext := gcm.Seal(nil, iv, []byte(digestHex), nil)
	checksumBytes := make([]byte, 0, len(iv)+len(ciphertext))
	checksumBytes = append(checksumBytes, iv...)
	checksumBytes = append(checksumBytes, ciphertext...)
	return hex.EncodeToString(checksumBytes), nil
}

func VerifyMobileMoicaChecksum(payload, checksumHex, encodedAPIKey string) error {
	raw, err := hex.DecodeString(strings.TrimSpace(checksumHex))
	if err != nil {
		return fmt.Errorf("%w: decode checksum", ErrMobileMoicaChecksumInvalid)
	}
	if len(raw) < mobileMoicaChecksumIVSize+16 {
		return fmt.Errorf("%w: checksum too short", ErrMobileMoicaChecksumInvalid)
	}
	gcm, err := mobileMoicaChecksumGCM(encodedAPIKey)
	if err != nil {
		return err
	}

	plaintext, err := gcm.Open(nil, raw[:mobileMoicaChecksumIVSize], raw[mobileMoicaChecksumIVSize:], nil)
	if err != nil {
		return fmt.Errorf("%w: decrypt checksum", ErrMobileMoicaChecksumInvalid)
	}
	digestHex := mobileMoicaSHA256Hex(payload)
	if subtle.ConstantTimeCompare([]byte(digestHex), plaintext) != 1 {
		return fmt.Errorf("%w: digest mismatch", ErrMobileMoicaChecksumInvalid)
	}
	return nil
}

func mobileMoicaChecksumGCM(encodedAPIKey string) (cipher.AEAD, error) {
	key, err := base64.StdEncoding.DecodeString(strings.TrimSpace(encodedAPIKey))
	if err != nil {
		return nil, fmt.Errorf("%w: decode AES key", ErrMobileMoicaChecksumConfig)
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("%w: AES key length", ErrMobileMoicaChecksumConfig)
	}
	gcm, err := cipher.NewGCMWithNonceSize(block, mobileMoicaChecksumIVSize)
	if err != nil {
		return nil, fmt.Errorf("%w: GCM nonce size", ErrMobileMoicaChecksumConfig)
	}
	return gcm, nil
}

func mobileMoicaSHA256Hex(payload string) string {
	digest := sha256.Sum256([]byte(payload))
	return hex.EncodeToString(digest[:])
}

type MobileMoicaSPTicket struct {
	TransactionID  string
	OperationCode  string
	OperationMode  string
	ServiceID      string
	TicketID       string
	ExpirationTime string
	HashedIDNumber string
}

type mobileMoicaSPTicketPayload struct {
	TransactionID  string `json:"transaction_id"`
	OperationCode  string `json:"op_code"`
	OperationMode  string `json:"op_mode"`
	ServiceID      string `json:"sp_service_id"`
	TicketID       string `json:"sp_ticket_id"`
	ExpirationTime string `json:"expiration_time"`
	HashedIDNumber string `json:"hashed_id_num"`
}

func ParseMobileMoicaSPTicket(ticket string) (MobileMoicaSPTicket, error) {
	parts := strings.Split(strings.TrimSpace(ticket), ".")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return MobileMoicaSPTicket{}, fmt.Errorf("%w: format", ErrMobileMoicaTicketInvalid)
	}

	actualDigest, err := mobileMoicaDecodeBase64URL(parts[1])
	if err != nil {
		return MobileMoicaSPTicket{}, fmt.Errorf("%w: digest encoding", ErrMobileMoicaTicketInvalid)
	}
	expectedDigest := sha256.Sum256([]byte(parts[0]))
	if subtle.ConstantTimeCompare(expectedDigest[:], actualDigest) != 1 {
		return MobileMoicaSPTicket{}, fmt.Errorf("%w: digest mismatch", ErrMobileMoicaTicketInvalid)
	}

	payloadBytes, err := mobileMoicaDecodeBase64URL(parts[0])
	if err != nil {
		return MobileMoicaSPTicket{}, fmt.Errorf("%w: payload encoding", ErrMobileMoicaTicketInvalid)
	}
	var payload mobileMoicaSPTicketPayload
	if err := json.Unmarshal(payloadBytes, &payload); err != nil {
		return MobileMoicaSPTicket{}, fmt.Errorf("%w: payload json", ErrMobileMoicaTicketInvalid)
	}
	if payload.TransactionID == "" || payload.TicketID == "" {
		return MobileMoicaSPTicket{}, fmt.Errorf("%w: required payload fields", ErrMobileMoicaTicketInvalid)
	}

	return MobileMoicaSPTicket{
		TransactionID:  payload.TransactionID,
		OperationCode:  payload.OperationCode,
		OperationMode:  payload.OperationMode,
		ServiceID:      payload.ServiceID,
		TicketID:       payload.TicketID,
		ExpirationTime: payload.ExpirationTime,
		HashedIDNumber: payload.HashedIDNumber,
	}, nil
}

func mobileMoicaDecodeBase64URL(value string) ([]byte, error) {
	if decoded, err := base64.RawURLEncoding.DecodeString(value); err == nil {
		return decoded, nil
	}
	return base64.URLEncoding.DecodeString(value)
}

type MobileMoicaStartRequest struct {
	OfferID         string
	State           string
	HolderDID       string
	NationalID      string
	ConsentVersion  string
	ConsentCopyHash string
	ReturnURL       string
	ExpiresAt       time.Time
}

type MobileMoicaStartResult struct {
	DeepLinkURL string
	TicketID    string
	ExpiresAt   time.Time
}

type MobileMoicaVerificationResult struct {
	ProviderSubject  string
	ReplayID         string
	AssuranceContext string
	ExpiresAt        time.Time
}

type MobileMoicaRPBroker interface {
	Start(context.Context, MobileMoicaStartRequest) (MobileMoicaStartResult, error)
	Verify(context.Context, string, string) (MobileMoicaVerificationResult, error)
}

type ContractMobileMoicaRPConfig struct {
	ReturnURL  string
	Now        func() time.Time
	AutoVerify bool
}

type contractMobileMoicaRPBroker struct {
	mu         sync.Mutex
	returnURL  string
	now        func() time.Time
	autoVerify bool
	offers     map[string]MobileMoicaStartRequest
}

func NewContractMobileMoicaRPBroker(config ContractMobileMoicaRPConfig) MobileMoicaRPBroker {
	now := config.Now
	if now == nil {
		now = time.Now
	}
	returnURL := config.ReturnURL
	if returnURL == "" {
		returnURL = "trisaura://mobilemoica/callback"
	}
	return &contractMobileMoicaRPBroker{
		returnURL:  returnURL,
		now:        now,
		autoVerify: config.AutoVerify,
		offers:     make(map[string]MobileMoicaStartRequest),
	}
}

func (b *contractMobileMoicaRPBroker) Start(_ context.Context, request MobileMoicaStartRequest) (MobileMoicaStartResult, error) {
	if request.ReturnURL == "" {
		request.ReturnURL = b.returnURL
	}
	if request.ExpiresAt.IsZero() {
		request.ExpiresAt = b.now().Add(5 * time.Minute)
	}
	ticketID := "contract-ticket-" + request.OfferID

	deepLink := url.URL{
		Scheme: "mobilemoica",
		Host:   "moica.moi.gov.tw",
		Path:   "/a2a/verifySign",
	}
	values := url.Values{}
	values.Set("sp_ticket", ticketID)
	values.Set("rtn_url", base64.RawURLEncoding.EncodeToString([]byte(request.ReturnURL)))
	values.Set("rtn_val", base64.RawURLEncoding.EncodeToString(nil))
	deepLink.RawQuery = values.Encode()

	stored := request
	stored.NationalID = ""
	b.mu.Lock()
	b.offers[request.OfferID] = stored
	b.mu.Unlock()

	return MobileMoicaStartResult{
		DeepLinkURL: deepLink.String(),
		TicketID:    ticketID,
		ExpiresAt:   request.ExpiresAt,
	}, nil
}

func (b *contractMobileMoicaRPBroker) Verify(_ context.Context, offerID, state string) (MobileMoicaVerificationResult, error) {
	b.mu.Lock()
	request, ok := b.offers[offerID]
	b.mu.Unlock()
	if !ok || request.State != state {
		return MobileMoicaVerificationResult{}, ErrMobileMoicaOfferNotFound
	}
	if !b.autoVerify {
		return MobileMoicaVerificationResult{}, ErrMobileMoicaResultPending
	}
	subjectDigest := sha256.Sum256([]byte(fmt.Sprintf("%s|%s|%s", request.OfferID, request.State, request.HolderDID)))
	return MobileMoicaVerificationResult{
		ProviderSubject:  "contract-mobilemoica-subject-" + hex.EncodeToString(subjectDigest[:16]),
		ReplayID:         "contract-mobilemoica-replay-" + request.OfferID,
		AssuranceContext: "mobilemoica_rp_explicit_disclosure",
		ExpiresAt:        request.ExpiresAt,
	}, nil
}

// MobileMoicaSignedResponseVerifier validates the provider's PKCS#7 response
// and returns an ephemeral provider subject plus a replay identifier. Neither
// value is suitable for logs, VCs, or federation payloads.
type MobileMoicaSignedResponseVerifier interface {
	Verify(context.Context, string, []byte) (providerSubject, replayID string, err error)
}

type MobileMoicaRevocationChecker interface {
	Check(context.Context, *x509.Certificate, []*x509.Certificate) error
}

type StaticCRLMobileMoicaChecker struct {
	Lists []*x509.RevocationList
	Now   func() time.Time
}

func (c StaticCRLMobileMoicaChecker) Check(
	_ context.Context,
	certificate *x509.Certificate,
	chain []*x509.Certificate,
) error {
	if len(c.Lists) == 0 {
		return ErrMobileMoicaProductionUnavailable
	}
	now := time.Now()
	if c.Now != nil {
		now = c.Now()
	}
	for _, list := range c.Lists {
		if list == nil || now.Before(list.ThisUpdate) || !now.Before(list.NextUpdate) {
			continue
		}
		for _, issuer := range chain {
			if issuer == nil || list.CheckSignatureFrom(issuer) != nil {
				continue
			}
			for _, revoked := range list.RevokedCertificateEntries {
				if certificate.SerialNumber.Cmp(revoked.SerialNumber) == 0 {
					return ErrMobileMoicaCertificateRevoked
				}
			}
			return nil
		}
	}
	return ErrMobileMoicaProductionUnavailable
}

type PKCS7MobileMoicaVerifier struct {
	Roots      *x509.CertPool
	Revocation MobileMoicaRevocationChecker
	Now        func() time.Time
}

func (v PKCS7MobileMoicaVerifier) Verify(
	ctx context.Context,
	encoded string,
	expectedContent []byte,
) (string, string, error) {
	if v.Roots == nil || v.Revocation == nil {
		return "", "", ErrMobileMoicaProductionUnavailable
	}
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(encoded))
	if err != nil {
		raw, err = base64.RawStdEncoding.DecodeString(strings.TrimSpace(encoded))
	}
	if err != nil {
		raw, err = base64.RawURLEncoding.DecodeString(strings.TrimSpace(encoded))
		if err != nil {
			return "", "", fmt.Errorf("%w: base64", ErrMobileMoicaSignedContentInvalid)
		}
	}
	message, err := pkcs7.Parse(raw)
	if err != nil {
		return "", "", fmt.Errorf("%w: parse", ErrMobileMoicaSignedContentInvalid)
	}
	now := time.Now()
	if v.Now != nil {
		now = v.Now()
	}
	if err := message.VerifyWithChainAtTime(v.Roots, now); err != nil {
		return "", "", fmt.Errorf("%w: signature or chain", ErrMobileMoicaCertificateInvalid)
	}
	if subtle.ConstantTimeCompare(message.Content, expectedContent) != 1 {
		return "", "", fmt.Errorf("%w: offer binding", ErrMobileMoicaSignedContentInvalid)
	}
	signer := message.GetOnlySigner()
	if signer == nil {
		return "", "", fmt.Errorf("%w: signer", ErrMobileMoicaCertificateInvalid)
	}
	if err := v.Revocation.Check(ctx, signer, message.Certificates); err != nil {
		if errors.Is(err, ErrMobileMoicaCertificateRevoked) {
			return "", "", ErrMobileMoicaCertificateRevoked
		}
		return "", "", fmt.Errorf("%w: revocation unavailable", ErrMobileMoicaProductionUnavailable)
	}
	subjectDigest := sha256.Sum256(signer.RawSubjectPublicKeyInfo)
	replayDigest := sha256.Sum256(raw)
	return hex.EncodeToString(subjectDigest[:]), hex.EncodeToString(replayDigest[:]), nil
}

type ProductionMobileMoicaRPConfig struct {
	TicketEndpoint string
	ResultEndpoint string
	ServiceID      string
	EncodedAPIKey  string
	ReturnURL      string
	Hint           string
	HTTPClient     *http.Client
	Verifier       MobileMoicaSignedResponseVerifier
	Now            func() time.Time
}

type productionMobileMoicaOffer struct {
	state         string
	transactionID string
	ticketID      string
	signedContent []byte
	expiresAt     time.Time
}

type productionMobileMoicaRPBroker struct {
	config ProductionMobileMoicaRPConfig
	mu     sync.Mutex
	offers map[string]productionMobileMoicaOffer
}

type mobileMoicaTicketRequest struct {
	TransactionID string `json:"transaction_id"`
	ServiceID     string `json:"sp_service_id"`
	NationalID    string `json:"id_num"`
	OpCode        string `json:"op_code"`
	OpMode        string `json:"op_mode"`
	Hint          string `json:"hint"`
	SignType      string `json:"sign_type"`
	TBSEncoding   string `json:"tbs_encoding"`
	HashAlgorithm string `json:"hash_algorithm"`
	SignData      string `json:"sign_data"`
	SPChecksum    string `json:"sp_checksum"`
}

type mobileMoicaTicketResponse struct {
	TransactionID string `json:"transaction_id"`
	ErrorCode     string `json:"error_code"`
	SPTicket      string `json:"sp_ticket"`
	IDPChecksum   string `json:"idp_checksum"`
}

type mobileMoicaResultRequest struct {
	TransactionID string `json:"transaction_id"`
	ServiceID     string `json:"sp_service_id"`
	SPTicketID    string `json:"sp_ticket_id"`
	SPChecksum    string `json:"sp_checksum"`
}

type mobileMoicaResultResponse struct {
	TransactionID string `json:"transaction_id"`
	ErrorCode     string `json:"error_code"`
	HashedID      string `json:"hashed_id_num"`
	Signed        string `json:"signed_response"`
	IDPChecksum   string `json:"idp_checksum"`
}

type mobileMoicaSignedContent struct {
	Schema          string `json:"schema"`
	IssuerOrigin    string `json:"issuer_origin"`
	OfferID         string `json:"offer_id"`
	HolderDID       string `json:"holder_did"`
	Purpose         string `json:"purpose"`
	ConsentVersion  string `json:"consent_version"`
	ConsentCopyHash string `json:"consent_copy_hash"`
	Nonce           string `json:"nonce"`
	IssuedAt        string `json:"issued_at"`
	ExpiresAt       string `json:"expires_at"`
}

func NewProductionMobileMoicaRPBroker(config ProductionMobileMoicaRPConfig) (MobileMoicaRPBroker, error) {
	if config.TicketEndpoint == "" || config.ResultEndpoint == "" ||
		config.ServiceID == "" || config.EncodedAPIKey == "" ||
		config.Verifier == nil {
		return nil, ErrMobileMoicaProductionUnavailable
	}
	for _, endpoint := range []string{config.TicketEndpoint, config.ResultEndpoint} {
		parsed, err := url.Parse(endpoint)
		if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
			return nil, fmt.Errorf("%w: HTTPS endpoint", ErrMobileMoicaProductionUnavailable)
		}
	}
	if _, err := mobileMoicaChecksumGCM(config.EncodedAPIKey); err != nil {
		return nil, err
	}
	if config.HTTPClient == nil {
		config.HTTPClient = &http.Client{Timeout: 15 * time.Second}
	}
	if config.Now == nil {
		config.Now = time.Now
	}
	return &productionMobileMoicaRPBroker{
		config: config,
		offers: make(map[string]productionMobileMoicaOffer),
	}, nil
}

func (b *productionMobileMoicaRPBroker) Start(
	ctx context.Context,
	request MobileMoicaStartRequest,
) (MobileMoicaStartResult, error) {
	now := b.config.Now().UTC()
	if request.ExpiresAt.IsZero() {
		request.ExpiresAt = now.Add(5 * time.Minute)
	}
	transactionID, err := mobileMoicaRandomID()
	if err != nil {
		return MobileMoicaStartResult{}, err
	}
	content, err := json.Marshal(mobileMoicaSignedContent{
		Schema:          "trisaura.mobilemoica_rp.v1",
		IssuerOrigin:    mobileMoicaOrigin(request.ReturnURL),
		OfferID:         request.OfferID,
		HolderDID:       request.HolderDID,
		Purpose:         "issue_trisaura_humanity_credential",
		ConsentVersion:  request.ConsentVersion,
		ConsentCopyHash: request.ConsentCopyHash,
		Nonce:           request.State,
		IssuedAt:        now.Format(time.RFC3339),
		ExpiresAt:       request.ExpiresAt.UTC().Format(time.RFC3339),
	})
	if err != nil {
		return MobileMoicaStartResult{}, err
	}
	signData := base64.StdEncoding.EncodeToString(content)
	checksum, err := GenerateMobileMoicaSPChecksum(MobileMoicaTicketChecksumPayload(
		MobileMoicaTicketChecksumInput{
			TransactionID: transactionID, ServiceID: b.config.ServiceID,
			NationalID: request.NationalID, OpCode: "SIGN", OpMode: "APP2APP",
			Hint: b.config.Hint, SignData: signData,
		},
	), b.config.EncodedAPIKey)
	if err != nil {
		return MobileMoicaStartResult{}, err
	}
	var response mobileMoicaTicketResponse
	err = b.postJSON(ctx, b.config.TicketEndpoint, mobileMoicaTicketRequest{
		TransactionID: transactionID, ServiceID: b.config.ServiceID,
		NationalID: request.NationalID, OpCode: "SIGN", OpMode: "APP2APP",
		Hint: b.config.Hint, SignType: "PKCS#7", TBSEncoding: "base64",
		HashAlgorithm: "SHA256", SignData: signData, SPChecksum: checksum,
	}, &response)
	if err != nil {
		return MobileMoicaStartResult{}, err
	}
	if response.TransactionID != transactionID || response.ErrorCode != "0" {
		return MobileMoicaStartResult{}, ErrMobileMoicaProviderUnavailable
	}
	if err := VerifyMobileMoicaChecksum(
		MobileMoicaTicketResponseChecksumPayload(response.TransactionID, response.ErrorCode, response.SPTicket),
		response.IDPChecksum,
		b.config.EncodedAPIKey,
	); err != nil {
		return MobileMoicaStartResult{}, err
	}
	ticket, err := ParseMobileMoicaSPTicket(response.SPTicket)
	if err != nil {
		return MobileMoicaStartResult{}, err
	}
	if ticket.TransactionID != transactionID || ticket.ServiceID != b.config.ServiceID ||
		!strings.EqualFold(ticket.OperationCode, "SIGN") ||
		!strings.EqualFold(ticket.OperationMode, "APP2APP") {
		return MobileMoicaStartResult{}, ErrMobileMoicaTicketInvalid
	}
	if expiry, err := mobileMoicaTicketExpiry(ticket.ExpirationTime); err != nil ||
		!expiry.After(now) ||
		expiry.After(request.ExpiresAt.Add(time.Minute)) {
		return MobileMoicaStartResult{}, fmt.Errorf("%w: expiry", ErrMobileMoicaTicketInvalid)
	}
	b.mu.Lock()
	b.offers[request.OfferID] = productionMobileMoicaOffer{
		state: request.State, transactionID: transactionID, ticketID: ticket.TicketID,
		signedContent: append([]byte(nil), content...), expiresAt: request.ExpiresAt,
	}
	b.mu.Unlock()

	returnURL := request.ReturnURL
	if returnURL == "" {
		returnURL = b.config.ReturnURL
	}
	deepLink := url.URL{Scheme: "mobilemoica", Host: "moica.moi.gov.tw", Path: "/a2a/verifySign"}
	query := url.Values{}
	query.Set("sp_ticket", response.SPTicket)
	query.Set("rtn_url", base64.RawURLEncoding.EncodeToString([]byte(returnURL)))
	query.Set("rtn_val", base64.RawURLEncoding.EncodeToString([]byte(request.OfferID)))
	deepLink.RawQuery = query.Encode()
	return MobileMoicaStartResult{DeepLinkURL: deepLink.String(), TicketID: ticket.TicketID, ExpiresAt: request.ExpiresAt}, nil
}

func (b *productionMobileMoicaRPBroker) Verify(
	ctx context.Context,
	offerID, state string,
) (MobileMoicaVerificationResult, error) {
	b.mu.Lock()
	offer, ok := b.offers[offerID]
	b.mu.Unlock()
	if !ok || offer.state != state {
		return MobileMoicaVerificationResult{}, ErrMobileMoicaOfferNotFound
	}
	if !offer.expiresAt.After(b.config.Now()) {
		return MobileMoicaVerificationResult{}, ErrExpiredSessionState
	}
	checksum, err := GenerateMobileMoicaSPChecksum(
		MobileMoicaResultChecksumPayload(offer.transactionID, b.config.ServiceID, offer.ticketID),
		b.config.EncodedAPIKey,
	)
	if err != nil {
		return MobileMoicaVerificationResult{}, err
	}
	var response mobileMoicaResultResponse
	err = b.postJSON(ctx, b.config.ResultEndpoint, mobileMoicaResultRequest{
		TransactionID: offer.transactionID, ServiceID: b.config.ServiceID,
		SPTicketID: offer.ticketID, SPChecksum: checksum,
	}, &response)
	if err != nil {
		return MobileMoicaVerificationResult{}, err
	}
	if response.TransactionID != offer.transactionID {
		return MobileMoicaVerificationResult{}, ErrMobileMoicaChecksumInvalid
	}
	if response.ErrorCode != "0" {
		return MobileMoicaVerificationResult{}, ErrMobileMoicaResultPending
	}
	if err := VerifyMobileMoicaChecksum(
		MobileMoicaSignResultResponseChecksumPayload(response.TransactionID, response.ErrorCode, response.HashedID, response.Signed),
		response.IDPChecksum,
		b.config.EncodedAPIKey,
	); err != nil {
		return MobileMoicaVerificationResult{}, err
	}
	subject, replayID, err := b.config.Verifier.Verify(ctx, response.Signed, offer.signedContent)
	if err != nil {
		return MobileMoicaVerificationResult{}, err
	}
	b.mu.Lock()
	delete(b.offers, offerID)
	b.mu.Unlock()
	return MobileMoicaVerificationResult{
		ProviderSubject: subject, ReplayID: replayID,
		AssuranceContext: "mobilemoica_rp_explicit_disclosure",
		ExpiresAt:        offer.expiresAt,
	}, nil
}

func (b *productionMobileMoicaRPBroker) postJSON(ctx context.Context, endpoint string, body, output any) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(encoded))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := b.config.HTTPClient.Do(request)
	if err != nil {
		return ErrMobileMoicaProviderUnavailable
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		return ErrMobileMoicaProviderUnavailable
	}
	decoder := json.NewDecoder(io.LimitReader(response.Body, 1<<20))
	if err := decoder.Decode(output); err != nil {
		return ErrMobileMoicaProviderUnavailable
	}
	return nil
}

func mobileMoicaTicketExpiry(value string) (time.Time, error) {
	if parsed, err := time.Parse(time.RFC3339, value); err == nil {
		return parsed, nil
	}
	milliseconds, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		return time.Time{}, err
	}
	return time.UnixMilli(milliseconds), nil
}

func mobileMoicaRandomID() (string, error) {
	raw := make([]byte, 24)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

func mobileMoicaOrigin(returnURL string) string {
	parsed, err := url.Parse(returnURL)
	if err != nil {
		return ""
	}
	if parsed.Scheme == "https" {
		return parsed.Scheme + "://" + parsed.Host
	}
	return parsed.Scheme + "://"
}
