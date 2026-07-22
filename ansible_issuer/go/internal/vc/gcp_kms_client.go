package vc

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"hash/crc32"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	cloudKMSBaseURL  = "https://cloudkms.googleapis.com/v1/"
	metadataTokenURL = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
)

var castagnoliTable = crc32.MakeTable(crc32.Castagnoli)

// GCPKMSRESTClient is a dependency-light Cloud KMS adapter suitable for Cloud
// Run. It obtains short-lived credentials from the metadata server and checks
// KMS request/response CRC32C fields before returning a signature.
type GCPKMSRESTClient struct {
	httpClient *http.Client
	baseURL    string
	tokenURL   string

	mu          sync.Mutex
	accessToken string
	tokenExpiry time.Time
}

func NewGCPKMSRESTClient(httpClient *http.Client) *GCPKMSRESTClient {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 10 * time.Second}
	}
	return &GCPKMSRESTClient{
		httpClient: httpClient,
		baseURL:    cloudKMSBaseURL,
		tokenURL:   metadataTokenURL,
	}
}

type kmsPublicKeyResponse struct {
	PEM             string `json:"pem"`
	Algorithm       string `json:"algorithm"`
	ProtectionLevel string `json:"protectionLevel"`
}

func (c *GCPKMSRESTClient) PublicKey(ctx context.Context, keyVersion string) (string, string, string, error) {
	var result kmsPublicKeyResponse
	if err := c.doJSON(ctx, http.MethodGet, keyVersion+"/publicKey", nil, &result); err != nil {
		return "", "", "", err
	}
	return result.PEM, result.Algorithm, result.ProtectionLevel, nil
}

type kmsSignRequest struct {
	Data       string `json:"data"`
	DataCRC32C string `json:"dataCrc32c"`
}

type kmsSignResponse struct {
	Signature          string `json:"signature"`
	SignatureCRC32C    string `json:"signatureCrc32c"`
	VerifiedDataCRC32C bool   `json:"verifiedDataCrc32c"`
	ProtectionLevel    string `json:"protectionLevel"`
}

func (c *GCPKMSRESTClient) AsymmetricSign(ctx context.Context, keyVersion string, data []byte) ([]byte, string, error) {
	request := kmsSignRequest{
		Data:       base64.StdEncoding.EncodeToString(data),
		DataCRC32C: strconv.FormatUint(uint64(crc32.Checksum(data, castagnoliTable)), 10),
	}
	var result kmsSignResponse
	if err := c.doJSON(ctx, http.MethodPost, keyVersion+":asymmetricSign", request, &result); err != nil {
		return nil, "", err
	}
	if !result.VerifiedDataCRC32C {
		return nil, "", errors.New("KMS did not verify request CRC32C")
	}
	signature, err := base64.StdEncoding.DecodeString(result.Signature)
	if err != nil {
		return nil, "", fmt.Errorf("decode KMS signature: %w", err)
	}
	wantCRC, err := strconv.ParseUint(result.SignatureCRC32C, 10, 32)
	if err != nil {
		return nil, "", fmt.Errorf("parse KMS signature CRC32C: %w", err)
	}
	if uint64(crc32.Checksum(signature, castagnoliTable)) != wantCRC {
		return nil, "", errors.New("KMS signature CRC32C mismatch")
	}
	return signature, result.ProtectionLevel, nil
}

func (c *GCPKMSRESTClient) doJSON(ctx context.Context, method, resource string, body any, result any) error {
	if !validKMSKeyVersion(resource) {
		return errors.New("invalid KMS key-version resource name")
	}
	token, err := c.token(ctx)
	if err != nil {
		return err
	}
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = strings.NewReader(string(encoded))
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+resource, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		limited, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("KMS HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(limited)))
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(result); err != nil {
		return fmt.Errorf("decode KMS response: %w", err)
	}
	return nil
}

func validKMSKeyVersion(resource string) bool {
	resource = strings.TrimSuffix(strings.TrimSuffix(resource, "/publicKey"), ":asymmetricSign")
	parts := strings.Split(resource, "/")
	return len(parts) == 10 && parts[0] == "projects" && parts[2] == "locations" &&
		parts[4] == "keyRings" && parts[6] == "cryptoKeys" && parts[8] == "cryptoKeyVersions" &&
		parts[1] != "" && parts[3] != "" && parts[5] != "" && parts[7] != "" && parts[9] != ""
}

type metadataTokenResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int    `json:"expires_in"`
}

func (c *GCPKMSRESTClient) token(ctx context.Context) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.accessToken != "" && time.Now().Add(time.Minute).Before(c.tokenExpiry) {
		return c.accessToken, nil
	}
	if _, err := url.ParseRequestURI(c.tokenURL); err != nil {
		return "", fmt.Errorf("invalid metadata token URL: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.tokenURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Metadata-Flavor", "Google")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("get metadata access token: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("metadata token HTTP %d", resp.StatusCode)
	}
	var result metadataTokenResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&result); err != nil {
		return "", fmt.Errorf("decode metadata token: %w", err)
	}
	if result.AccessToken == "" || result.ExpiresIn <= 0 {
		return "", errors.New("metadata server returned an invalid access token")
	}
	c.accessToken = result.AccessToken
	c.tokenExpiry = time.Now().Add(time.Duration(result.ExpiresIn) * time.Second)
	return c.accessToken, nil
}
