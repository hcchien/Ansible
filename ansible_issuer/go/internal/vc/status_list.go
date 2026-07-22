package vc

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"time"
)

const minimumStatusListEntries = 131072

type CredentialStatusEntry struct {
	Index  int64
	Status string
}

type IssuedStatusList struct {
	JWT         string
	Hash        string
	EncodedList string
	IssuedAt    time.Time
}

func IssueBitstringStatusList(signer Signer, issuerDID, listURL, purpose string, entries []CredentialStatusEntry, now time.Time) (IssuedStatusList, error) {
	if signer == nil || issuerDID == "" || listURL == "" || (purpose != "revocation" && purpose != "suspension") {
		return IssuedStatusList{}, errors.New("invalid status list request")
	}
	bitstring := make([]byte, minimumStatusListEntries/8)
	for _, entry := range entries {
		if entry.Index < 0 || entry.Index >= minimumStatusListEntries {
			return IssuedStatusList{}, errors.New("status index outside list")
		}
		set := (purpose == "revocation" && entry.Status == "revoked") || (purpose == "suspension" && entry.Status == "suspended")
		if set {
			bitstring[entry.Index/8] |= byte(1 << (7 - uint(entry.Index%8)))
		}
	}
	var compressed bytes.Buffer
	writer, err := gzip.NewWriterLevel(&compressed, gzip.BestCompression)
	if err != nil {
		return IssuedStatusList{}, err
	}
	writer.Header.ModTime = time.Unix(0, 0)
	writer.Header.OS = 255
	if _, err := writer.Write(bitstring); err != nil {
		return IssuedStatusList{}, err
	}
	if err := writer.Close(); err != nil {
		return IssuedStatusList{}, err
	}
	// 'u' is the multibase prefix for base64url without padding.
	encodedList := "u" + base64.RawURLEncoding.EncodeToString(compressed.Bytes())
	issuedAt := now.UTC()
	credential := map[string]any{
		"@context": []string{"https://www.w3.org/ns/credentials/v2", "https://w3id.org/vc/status-list/2021/v1"},
		"id":       listURL, "type": []string{"VerifiableCredential", "BitstringStatusListCredential"},
		"issuer": issuerDID, "validFrom": issuedAt.Format(time.RFC3339),
		"credentialSubject": map[string]any{
			"id": listURL + "#list", "type": "BitstringStatusList", "statusPurpose": purpose,
			"encodedList": encodedList,
		},
	}
	claims := map[string]any{"iss": issuerDID, "sub": listURL + "#list", "jti": listURL, "iat": issuedAt.Unix(), "nbf": issuedAt.Unix(), "vc": credential}
	headerJSON, _ := json.Marshal(map[string]any{"alg": "EdDSA", "typ": "JWT", "kid": signer.KeyID()})
	claimsJSON, err := json.Marshal(claims)
	if err != nil {
		return IssuedStatusList{}, err
	}
	unsigned := base64.RawURLEncoding.EncodeToString(headerJSON) + "." + base64.RawURLEncoding.EncodeToString(claimsJSON)
	signature, err := signer.Sign([]byte(unsigned))
	if err != nil {
		return IssuedStatusList{}, err
	}
	compact := unsigned + "." + base64.RawURLEncoding.EncodeToString(signature)
	hash := sha256.Sum256([]byte(compact))
	return IssuedStatusList{JWT: compact, Hash: hex.EncodeToString(hash[:]), EncodedList: encodedList, IssuedAt: issuedAt}, nil
}
