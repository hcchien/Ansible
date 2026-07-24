package vc

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

const MembershipCredentialType = "PoliticalPartyMembershipCredential"

type MembershipIssueRequest struct {
	IssuerDID         string
	IssuerURL         string
	HolderPairwiseDID string
	HolderJWK         map[string]string
	MembershipClass   string
	ForumHostID       string
	BoardID           string
	StatusListIndex   int64
	StatusListBaseURL string
	Now               time.Time
	TTL               time.Duration
}

type IssuedJWTCredential struct {
	ID        string
	JWT       string
	Hash      string
	IssuedAt  time.Time
	ExpiresAt time.Time
}

// IssueMembershipJWT emits the OID4VCI jwt_vc_json profile. The holder's
// purpose-separated hardware JWK is placed in cnf and no legal identity,
// membership number, or provider assertion is included.
func IssueMembershipJWT(signer Signer, request MembershipIssueRequest) (IssuedJWTCredential, error) {
	if signer == nil || signer.Algorithm() != eddsaJCS2022 || request.IssuerDID == "" ||
		request.IssuerURL == "" || request.HolderPairwiseDID == "" || request.StatusListIndex < 0 ||
		request.StatusListBaseURL == "" || request.ForumHostID == "" || request.BoardID == "" || request.HolderJWK["kty"] != "EC" || request.HolderJWK["crv"] != "P-256" ||
		request.HolderJWK["x"] == "" || request.HolderJWK["y"] == "" {
		return IssuedJWTCredential{}, errors.New("invalid membership credential request")
	}
	now := request.Now.UTC()
	if now.IsZero() {
		now = time.Now().UTC()
	}
	if request.TTL <= 0 || request.TTL > 365*24*time.Hour {
		request.TTL = 90 * 24 * time.Hour
	}
	expiresAt := now.Add(request.TTL)
	idDigest := sha256.Sum256([]byte(fmt.Sprintf("%s\x00%s\x00%d\x00%d", request.IssuerDID, request.HolderPairwiseDID, request.StatusListIndex, now.UnixNano())))
	credentialID := request.IssuerURL + "/credentials/" + hex.EncodeToString(idDigest[:16])
	subject := map[string]any{
		"id": request.HolderPairwiseDID, "organization_id": request.IssuerDID, "membership": true, "forum_host_id": request.ForumHostID, "board_id": request.BoardID,
	}
	if request.MembershipClass != "" {
		subject["membership_class"] = request.MembershipClass
	}
	vcPayload := map[string]any{
		"@context": []string{"https://www.w3.org/2018/credentials/v1"},
		"id":       credentialID, "type": []string{"VerifiableCredential", MembershipCredentialType},
		"issuer": request.IssuerDID, "validFrom": now.Format(time.RFC3339), "validUntil": expiresAt.Format(time.RFC3339),
		"credentialSubject": subject,
		"credentialStatus": []map[string]any{
			statusListEntry(request.StatusListBaseURL+"/revocation/1", "revocation", request.StatusListIndex),
			statusListEntry(request.StatusListBaseURL+"/suspension/1", "suspension", request.StatusListIndex),
		},
	}
	claims := map[string]any{
		"iss": request.IssuerDID, "sub": request.HolderPairwiseDID, "jti": credentialID,
		"iat": now.Unix(), "nbf": now.Unix(), "exp": expiresAt.Unix(), "vc": vcPayload,
		"cnf": map[string]any{"jwk": request.HolderJWK},
	}
	header := map[string]any{"alg": "EdDSA", "typ": "JWT", "kid": signer.KeyID()}
	headerJSON, err := json.Marshal(header)
	if err != nil {
		return IssuedJWTCredential{}, err
	}
	claimsJSON, err := json.Marshal(claims)
	if err != nil {
		return IssuedJWTCredential{}, err
	}
	unsigned := base64.RawURLEncoding.EncodeToString(headerJSON) + "." + base64.RawURLEncoding.EncodeToString(claimsJSON)
	signature, err := signer.Sign([]byte(unsigned))
	if err != nil {
		return IssuedJWTCredential{}, err
	}
	compact := unsigned + "." + base64.RawURLEncoding.EncodeToString(signature)
	hash := sha256.Sum256([]byte(compact))
	return IssuedJWTCredential{ID: credentialID, JWT: compact, Hash: hex.EncodeToString(hash[:]), IssuedAt: now, ExpiresAt: expiresAt}, nil
}

func statusListEntry(url, purpose string, index int64) map[string]any {
	return map[string]any{
		"id": fmt.Sprintf("%s#%d", url, index), "type": "BitstringStatusListEntry",
		"statusPurpose": purpose, "statusListIndex": fmt.Sprintf("%d", index), "statusListCredential": url,
	}
}
