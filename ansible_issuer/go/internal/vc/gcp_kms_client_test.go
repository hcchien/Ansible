package vc

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"hash/crc32"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
)

func TestGCPKMSRESTClientChecksIntegrity(t *testing.T) {
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(public)
	if err != nil {
		t.Fatal(err)
	}
	publicPEM := string(pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der}))

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/token":
			if r.Header.Get("Metadata-Flavor") != "Google" {
				t.Error("missing metadata header")
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "token", "expires_in": 3600})
		case "/projects/p/locations/l/keyRings/r/cryptoKeys/k/cryptoKeyVersions/1/publicKey":
			if r.Header.Get("Authorization") != "Bearer token" {
				t.Error("missing bearer token")
			}
			_ = json.NewEncoder(w).Encode(map[string]any{
				"pem": publicPEM, "algorithm": "EC_SIGN_ED25519", "protectionLevel": "HSM",
			})
		case "/projects/p/locations/l/keyRings/r/cryptoKeys/k/cryptoKeyVersions/1:asymmetricSign":
			var request kmsSignRequest
			if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
				t.Error(err)
			}
			data, _ := base64.StdEncoding.DecodeString(request.Data)
			if request.DataCRC32C != strconv.FormatUint(uint64(crc32.Checksum(data, castagnoliTable)), 10) {
				t.Error("bad request CRC32C")
			}
			signature := ed25519.Sign(private, data)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"signature":          base64.StdEncoding.EncodeToString(signature),
				"signatureCrc32c":    strconv.FormatUint(uint64(crc32.Checksum(signature, castagnoliTable)), 10),
				"verifiedDataCrc32c": true,
				"protectionLevel":    "HSM",
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := NewGCPKMSRESTClient(server.Client())
	client.baseURL = server.URL + "/"
	client.tokenURL = server.URL + "/token"
	key := "projects/p/locations/l/keyRings/r/cryptoKeys/k/cryptoKeyVersions/1"
	signer, err := NewGCPKMSEd25519Signer(context.Background(), key, client, true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := signer.Sign([]byte("credential")); err != nil {
		t.Fatal(err)
	}
}

func TestGCPKMSRESTClientRejectsBadSignatureCRC(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/token" {
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "token", "expires_in": 3600})
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"signature":       base64.StdEncoding.EncodeToString(make([]byte, ed25519.SignatureSize)),
			"signatureCrc32c": "1", "verifiedDataCrc32c": true, "protectionLevel": "HSM",
		})
	}))
	defer server.Close()
	client := NewGCPKMSRESTClient(server.Client())
	client.baseURL = server.URL + "/"
	client.tokenURL = server.URL + "/token"
	if _, _, err := client.AsymmetricSign(context.Background(), "projects/p/locations/l/keyRings/r/cryptoKeys/k/cryptoKeyVersions/1", []byte("x")); err == nil {
		t.Fatal("expected signature CRC mismatch")
	}
}
