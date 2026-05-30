package provider

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"sync"
	"time"
)

var (
	ErrMobileMoicaApprovalMissing       = errors.New("mobilemoica approval missing")
	ErrMobileMoicaChecksumConfig        = errors.New("mobilemoica checksum config")
	ErrMobileMoicaChecksumInvalid       = errors.New("mobilemoica checksum invalid")
	ErrMobileMoicaOfferNotFound         = errors.New("mobilemoica offer not found")
	ErrMobileMoicaResultPending         = errors.New("mobilemoica result pending")
	ErrMobileMoicaTicketInvalid         = errors.New("mobilemoica ticket invalid")
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

type ProductionMobileMoicaRPConfig struct{}

type productionMobileMoicaRPBroker struct{}

func NewProductionMobileMoicaRPBroker(ProductionMobileMoicaRPConfig) MobileMoicaRPBroker {
	return productionMobileMoicaRPBroker{}
}

func (productionMobileMoicaRPBroker) Start(context.Context, MobileMoicaStartRequest) (MobileMoicaStartResult, error) {
	return MobileMoicaStartResult{}, ErrMobileMoicaProductionUnavailable
}

func (productionMobileMoicaRPBroker) Verify(context.Context, string, string) (MobileMoicaVerificationResult, error) {
	return MobileMoicaVerificationResult{}, ErrMobileMoicaProductionUnavailable
}
